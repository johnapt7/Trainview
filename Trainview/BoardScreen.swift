import SwiftUI

struct BoardScreen: View {
    let station: Station
    let accent: Color
    let onOpenTrain: (Train) -> Void
    let onBack: () -> Void

    /// Seeds the destination filter so a saved journey opens the board
    /// already filtered, exactly as if the user had picked the destination
    /// from the search sheet. `mode` is owned by the caller so the
    /// departures/arrivals choice survives navigating into a train and back
    /// (this view is recreated on return).
    init(
        station: Station,
        accent: Color,
        mode: Binding<BoardMode>,
        initialFilterDestination: Station? = nil,
        onOpenTrain: @escaping (Train) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.station = station
        self.accent = accent
        self.onOpenTrain = onOpenTrain
        self.onBack = onBack
        _mode = mode
        _filterDestination = State(initialValue: initialFilterDestination)
    }

    @Binding var mode: BoardMode
    @State private var filter: FilterMode = .all
    @State private var services: [Train] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var nrccMessages: [String] = []
    @State private var callingPoints: [String: [CallingPointResponse]] = [:]
    @State private var serverFilterConfirmed = false
    @State private var callingPointsTasks: [Task<Void, Never>] = []
    @State private var showFAQ = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var filterDestination: Station?
    @State private var timeOffset: Int = 0
    @State private var homeStore = HomeStationsStore.shared
    @State private var journeysStore = RecentJourneysStore.shared
    @State private var stationDisruptions: [StationDisruption] = []
    @State private var disruptionsExpanded = false
    @State private var liveFeed: StationLiveFeed?
    @State private var isSilentlyRefreshing = false
    @State private var lastLoadedAt = Date.distantPast
    @AppStorage("hideFastestHint") private var hideFastestHint = false
    @Environment(\.scenePhase) private var scenePhase

    /// Fallback cadence for the foreground auto-refresh loop. The WebSocket
    /// feed usually triggers a refresh well before this fires.
    private static let autoRefreshInterval: TimeInterval = 45

    private var fastestDestinations: [Station] {
        homeStore.stations.filter { $0.code != station.code }
    }

    private var filtered: [Train] {
        var result: [Train]
        switch filter {
        case .all: result = services
        case .onTime: result = services.filter { $0.status == .onTime }
        case .intercity: result = services.filter {
            ["GR", "XC", "AW", "GW", "TP", "VT", "EM", "HT", "GC"].contains($0.operatorCode)
        }
        }
        // The banner promises "Calling at X", so a train counts if it
        // terminates at X or its known calling points include X. Skip
        // entirely when the server already filtered — its rows all qualify,
        // and re-filtering here would drop calling-at trains whose calling
        // points haven't been fetched yet.
        if let dest = filterDestination, !serverFilterConfirmed {
            result = result.filter { train in
                train.destinationCrs == dest.code
                    || (callingPoints[train.serviceId]?.contains { $0.crs == dest.code } ?? false)
            }
        }
        // Live search: while the user types (no locked filter yet), narrow
        // the board to trains whose headline station, CRS code, or known
        // calling points match the text. Purely client-side, updates on
        // every keystroke.
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if filterDestination == nil, !query.isEmpty {
            result = result.filter { train in
                let headline = isArrival ? train.origin : train.destination
                if headline.localizedCaseInsensitiveContains(query) { return true }
                if train.destinationCrs.caseInsensitiveCompare(query) == .orderedSame { return true }
                return callingPoints[train.serviceId]?.contains {
                    $0.station.localizedCaseInsensitiveContains(query)
                        || $0.crs.caseInsensitiveCompare(query) == .orderedSame
                } ?? false
            }
        }
        return result
    }

    private var isArrival: Bool { mode == .arrivals }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let date = Date().addingTimeInterval(TimeInterval(timeOffset * 60))
        return fmt.string(from: date)
    }

    private var footerLabel: String {
        if timeOffset != 0 {
            return isArrival ? "END OF ARRIVALS AT \(timeString)" : "END OF DEPARTURES AT \(timeString)"
        }
        return isArrival ? "END OF SCHEDULED ARRIVALS" : "END OF SCHEDULED DEPARTURES"
    }

    private var timeLabel: String {
        if timeOffset == 0 { return "NOW" }
        let mins = abs(timeOffset)
        let span: String
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            span = m > 0 ? "\(h) HR \(m) MIN" : "\(h) HR"
        } else {
            span = "\(mins) MIN"
        }
        return timeOffset < 0 ? "\(span) AGO" : "IN \(span)"
    }

    var body: some View {
        VStack(spacing: 0) {
            pinnedTopBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    stationCard
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                    if !isArrival && !fastestDestinations.isEmpty {
                        FastestDeparturesCard(
                            originCrs: station.code,
                            originName: station.name,
                            favourites: fastestDestinations,
                            accent: accent,
                            onOpenTrain: onOpenTrain
                        )
                        .padding(.top, 14)
                    } else if !isArrival && !hideFastestHint {
                        fastestHintCard
                    }
                    destinationSearchBar
                    filterRow
                    resultsRow
                    trainList
                }
            }
        }
        .background(Theme.cream)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await loadBoard()
        }
        .task {
            await loadBoard()
        }
        // Foreground auto-refresh: silent reloads so the board tracks platform
        // changes and delays without a pull. Cancelled whenever the app leaves
        // the active scene phase; refreshes immediately on return if stale.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if Date().timeIntervalSince(lastLoadedAt) > 30 {
                await loadBoard(silent: true)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autoRefreshInterval))
                guard !Task.isCancelled else { break }
                await loadBoard(silent: true)
            }
        }
        .onAppear {
            let feed = StationLiveFeed(crs: station.code) {
                Task { await loadBoard(silent: true) }
            }
            liveFeed = feed
            feed.connect()
        }
        .onDisappear {
            liveFeed?.disconnect()
            liveFeed = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                liveFeed?.connect()
            } else {
                liveFeed?.disconnect()
            }
        }
        .onChange(of: mode) { _, _ in
            Task { await loadBoard() }
        }
        .sheet(isPresented: $showFAQ) {
            FAQSheet()
        }
    }

    // MARK: - Data

    /// Loads the board. Silent loads (auto-refresh, WebSocket triggers) never
    /// show the skeleton state and keep the last good board on failure, so a
    /// network blip mid-refresh doesn't blank a screen the user is reading.
    private func loadBoard(silent: Bool = false) async {
        if silent {
            guard !isSilentlyRefreshing && !isLoading else { return }
            isSilentlyRefreshing = true
        } else {
            isLoading = true
            loadError = nil
        }
        do {
            let response = try await APIClient.shared.getBoard(
                crs: station.code,
                type: mode == .departures ? "departures" : "arrivals",
                filterCrs: filterDestination?.code,
                timeOffset: timeOffset != 0 ? timeOffset : nil
            )
            withAnimation(.easeOut(duration: 0.3)) {
                services = response.services.map {
                    var train = Train(from: $0)
                    train.isArrival = mode == .arrivals
                    return train
                }
                nrccMessages = response.nrccMessages ?? []
            }
            // When the server confirms it applied the destination filter
            // (echoed back in the response), every row already calls at the
            // destination and the client-side re-filter must stay out of the
            // way — it can only wrongly drop calling-at trains.
            serverFilterConfirmed = response.filterCrs != nil
            loadError = nil
            lastLoadedAt = Date()

            // Calling points delivered inline with the board (details
            // operations) — the per-service fan-out below only fills gaps.
            var seededPoints: [String: [CallingPointResponse]] = [:]
            for svc in response.services {
                let points = mode == .departures
                    ? svc.subsequentCallingPoints
                    : svc.previousCallingPoints
                if let points, !points.isEmpty {
                    seededPoints[svc.serviceId] = points
                }
            }

            if let disruptions = try? await APIClient.shared.getStationDisruptions(crs: station.code) {
                let activeOperators = Set(response.services.map(\.operatorCode))
                withAnimation(.easeOut(duration: 0.3)) {
                    stationDisruptions = disruptions.disruptions.filter { activeOperators.contains($0.id) }
                }
            }
            loadCallingPoints(incremental: silent, seeded: seededPoints)
        } catch {
            if !silent {
                services = []
                nrccMessages = []
                stationDisruptions = []
                loadError = (error as? APIError)?.errorDescription ?? "Could not load services"
                loadCallingPoints()
            }
        }
        if silent {
            isSilentlyRefreshing = false
        } else {
            isLoading = false
        }
    }

    /// Incremental mode keeps calling points already on screen and only
    /// fetches rows new to the board — a silent refresh shouldn't fan out a
    /// service-details request per visible train every tick. `seeded` holds
    /// calling points that arrived inline with the board response; those
    /// services never need a details request at all.
    private func loadCallingPoints(incremental: Bool = false, seeded: [String: [CallingPointResponse]] = [:]) {
        if incremental {
            let current = Set(services.map(\.serviceId))
            var kept = callingPoints.filter { current.contains($0.key) }
            for (id, points) in seeded { kept[id] = points }
            callingPoints = kept
            callingPointsTasks.removeAll { $0.isCancelled }
        } else {
            for task in callingPointsTasks { task.cancel() }
            callingPointsTasks.removeAll()
            callingPoints = seeded
        }
        let currentMode = mode
        // With 40-row boards a per-service fan-out would burst 40 requests at
        // once; a handful of workers drain the list in board order instead,
        // so the rows the user sees first fill in first.
        let missing = services.map(\.serviceId).filter { callingPoints[$0] == nil }
        guard !missing.isEmpty else { return }
        let queue = MissingServiceQueue(ids: missing)
        for _ in 0..<min(5, missing.count) {
            let task = Task {
                while let serviceId = await queue.next() {
                    guard !Task.isCancelled else { return }
                    guard let details = try? await APIClient.shared.getServiceDetails(serviceId: serviceId) else { continue }
                    guard !Task.isCancelled else { return }
                    let points = currentMode == .departures
                        ? details.subsequentCallingPoints
                        : details.previousCallingPoints
                    withAnimation(.easeIn(duration: 0.25)) {
                        callingPoints[serviceId] = points
                    }
                }
            }
            callingPointsTasks.append(task)
        }
    }

    // MARK: - Header

    /// Sits outside the ScrollView so the back / mode toggle / filter / info
    /// controls stay reachable while the board scrolls beneath. The system
    /// safe area keeps it clear of the status bar and Dynamic Island.
    private var pinnedTopBar: some View {
        topBar
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Theme.cream)
    }

    private var topBar: some View {
        HStack {
            IconButton(systemName: "chevron.left", size: 14, action: onBack)

            Spacer()

            HStack(spacing: 2) {
                tabButton("Departures", isActive: mode == .departures) {
                    mode = .departures
                    filter = .all
                }
                tabButton("Arrivals", isActive: mode == .arrivals) {
                    mode = .arrivals
                    filter = .all
                }
            }
            .padding(4)
            .background(Theme.ink.opacity(0.08))
            .clipShape(Capsule())

            Spacer()

            IconButton(systemName: "info.circle", size: 14) { showFAQ = true }
        }
        .padding(.vertical, 6)
        .padding(.bottom, 10)
    }

    private func tabButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, weight: .medium))
                .tracking(0.1)
                .foregroundStyle(isActive ? Theme.cream : Theme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isActive ? Theme.ink : .clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Station Card

    private var onTimeCount: Int { services.filter { $0.status == .onTime }.count }
    private var delayedCount: Int { services.filter { $0.status == .delayed }.count }
    private var cancelledCount: Int { services.filter { $0.status == .cancelled }.count }

    private var stationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text(isArrival ? "ARRIVING AT" : "DEPARTING FROM")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                Text("\(services.count) \(isArrival ? "INBOUND" : "OUTBOUND")")
                    .font(.mono(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkMute)
            }

            HStack(alignment: .bottom) {
                Text(station.name)
                    .font(.display(30))
                    .tracking(-0.3)
                    .lineLimit(1)
                Spacer()
                Button {
                    mode = isArrival ? .departures : .arrivals
                    filter = .all
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.ink)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 6)

            if !services.isEmpty {
                statusTallyRow
                    .padding(.top, 8)
            }

            if !nrccMessages.isEmpty || !stationDisruptions.isEmpty {
                disruptionsBanner
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                CodeTag(text: station.code)
                DotSeparator()
                HStack(spacing: 4) {
                    LiveDot(size: 10)
                    Text("Live")
                        .font(.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Theme.ink.opacity(0.05), radius: 0, y: 1)
    }

    private var statusTallyRow: some View {
        HStack(spacing: 12) {
            tallyItem(count: onTimeCount, label: "on time", color: Theme.perfGood)
            if delayedCount > 0 {
                tallyItem(count: delayedCount, label: "delayed", color: Theme.delayedText)
            }
            if cancelledCount > 0 {
                tallyItem(count: cancelledCount, label: "cancelled", color: Theme.cancelledText)
            }
        }
    }

    private func tallyItem(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var disruptionsBanner: some View {
        let totalCount = nrccMessages.count + stationDisruptions.count
        let hasHigh = stationDisruptions.contains { $0.severity == "High" }
        let tint = hasHigh ? Theme.cancelledText : Theme.delayedText

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    disruptionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                    Text(totalCount == 1 ? "1 disruption" : "\(totalCount) disruptions")
                        .font(.ui(12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                        .rotationEffect(.degrees(disruptionsExpanded ? -180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if disruptionsExpanded {
                Divider().overlay(tint.opacity(0.3))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(nrccMessages.enumerated()), id: \.offset) { _, message in
                        Text(stripHTML(message))
                            .font(.ui(11))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(stationDisruptions) { disruption in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(disruption.description)
                                .font(.ui(11))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !disruption.affectedOperators.isEmpty {
                                HStack(spacing: 3) {
                                    ForEach(disruption.affectedOperators, id: \.self) { op in
                                        Text(op)
                                            .font(.mono(8, weight: .medium))
                                            .tracking(0.3)
                                            .foregroundStyle(Theme.inkSoft)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Theme.ink.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .background(tint.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Destination Search Bar

    /// The journey the active filter represents, direction-corrected for the
    /// board mode: on arrivals the filtered station is where the train came
    /// FROM, so it is the journey's origin, not its destination.
    private var filteredJourney: RecentJourney? {
        guard let dest = filterDestination else { return nil }
        return isArrival
            ? RecentJourney(origin: dest, destination: station)
            : RecentJourney(origin: station, destination: dest)
    }

    /// The single station the typed text resolves to among trains actually
    /// on this board (headline stations and known calling points). Nil while
    /// the text is ambiguous or matches nothing, so the save star only
    /// appears once the search means one specific place the board serves.
    private var liveSearchMatch: Station? {
        guard filterDestination == nil else { return nil }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        var matches: [String: String] = [:]
        for train in services {
            if isArrival {
                if !train.originCrs.isEmpty,
                   train.origin.localizedCaseInsensitiveContains(query)
                    || train.originCrs.caseInsensitiveCompare(query) == .orderedSame {
                    matches[train.originCrs] = train.origin
                }
            } else if train.destination.localizedCaseInsensitiveContains(query)
                        || train.destinationCrs.caseInsensitiveCompare(query) == .orderedSame {
                matches[train.destinationCrs] = train.destination
            }
            for point in callingPoints[train.serviceId] ?? []
            where point.station.localizedCaseInsensitiveContains(query)
                || point.crs.caseInsensitiveCompare(query) == .orderedSame {
                matches[point.crs] = point.station
            }
        }
        matches.removeValue(forKey: station.code)
        guard matches.count == 1, let match = matches.first else { return nil }
        return Station(code: match.key, name: match.value)
    }

    /// Journey for the unambiguous live match, direction-corrected the same
    /// way as `filteredJourney`.
    private var liveSearchJourney: RecentJourney? {
        guard let match = liveSearchMatch else { return nil }
        return isArrival
            ? RecentJourney(origin: match, destination: station)
            : RecentJourney(origin: station, destination: match)
    }

    /// Always-visible entry point for the destination filter, replacing the
    /// old funnel icon in the top bar. Idle it's a live search field that
    /// narrows the board's trains as the user types — no station lookup, it
    /// only ever matches what's on the board. A board opened from a saved
    /// journey shows the locked filter banner with save + clear instead.
    private var destinationSearchBar: some View {
        Group {
            if filterDestination != nil {
                activeFilterBar
            } else {
                searchField
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMute)
            TextField(isArrival ? "Coming from..." : "Going to...", text: $searchText)
                .font(.ui(15))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            if let journey = liveSearchJourney {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        journeysStore.togglePin(journey)
                    }
                } label: {
                    Image(systemName: journeysStore.isPinned(journey) ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(journeysStore.isPinned(journey) ? Theme.ink : Theme.inkMute)
                        .frame(width: 24, height: 24)
                        .background(journeysStore.isPinned(journey) ? accent : Theme.ink.opacity(0.08))
                        .clipShape(Circle())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkMute)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(searchFocused ? Theme.ink.opacity(0.3) : Theme.line, lineWidth: 1)
        )
        // Tapping anywhere on the field focuses it, not just the text.
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
        .animation(.easeOut(duration: 0.2), value: liveSearchJourney?.id)
    }

    private var activeFilterBar: some View {
        let journey = filteredJourney
        let isPinned = journey.map { journeysStore.isPinned($0) } ?? false

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(accent)
            Text("\(isArrival ? "From" : "Calling at") \(Text(filterDestination?.name ?? "").font(.ui(12, weight: .semibold)).foregroundStyle(Theme.ink))")
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Spacer()
            Button {
                guard let journey else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    journeysStore.togglePin(journey)
                }
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPinned ? Theme.ink : Theme.inkMute)
                    .frame(width: 24, height: 24)
                    .background(isPinned ? accent : Theme.ink.opacity(0.08))
                    .clipShape(Circle())
            }
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    filterDestination = nil
                }
                Task { await loadBoard() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkMute)
                    .frame(width: 24, height: 24)
                    .background(Theme.ink.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Filters

    private var filterRow: some View {
        HStack {
            Button {
                guard timeOffset != 0 else { return }
                timeOffset = 0
                Task { await loadBoard() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: timeOffset == 0 ? "clock" : "clock.arrow.circlepath")
                        .font(.system(size: 10))
                    Text("\(timeLabel) \u{00B7} \(timeString)")
                        .font(.mono(11, weight: .medium))
                        .tracking(0.8)
                    if timeOffset != 0 {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(timeOffset == 0 ? Theme.inkSoft : Theme.ink)
                .padding(.horizontal, timeOffset != 0 ? 9 : 0)
                .padding(.vertical, timeOffset != 0 ? 5 : 0)
                .background(timeOffset != 0 ? accent.opacity(0.25) : .clear)
                .clipShape(Capsule())
            }
            .disabled(timeOffset == 0)
            Spacer()
            HStack(spacing: 6) {
                filterChip("All", mode: .all)
                filterChip("On time", mode: .onTime)
                filterChip("Intercity", mode: .intercity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func filterChip(_ label: String, mode: FilterMode) -> some View {
        Button {
            filter = mode
        } label: {
            Text(label)
                .font(.ui(11, weight: filter == mode ? .semibold : .medium))
                .foregroundStyle(filter == mode ? Theme.ink : Theme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filter == mode ? accent : Theme.ink.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    // MARK: - Results Row

    private var resultsRow: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(filtered.count)")
                    .font(.display(52))
                    .tracking(-1)
                    .lineSpacing(-8)
                VStack(alignment: .leading, spacing: 0) {
                    Text("trains")
                    Text(isArrival ? "arriving" : "departing")
                }
                .font(.mono(11))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 3)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: - Fastest Hint

    /// Shown in place of the fastest-departures strip until the user has
    /// home stations (or dismisses it) — the strip is invisible otherwise
    /// and nothing else explains what home stations unlock here.
    private var fastestHintCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Add home stations you travel to — the fastest trains to them will appear here.")
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    hideFastestHint = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkMute)
                    .frame(width: 24, height: 24)
                    .background(Theme.ink.opacity(0.06))
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Earlier Trains

    private var earlierTrainsButton: some View {
        Button {
            timeOffset = max(timeOffset - 30, -120)
            Task { await loadBoard() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(timeOffset == 0 ? "Show earlier trains" : "Show 30 min earlier")
                    .font(.ui(12, weight: .semibold))
                    .tracking(0.2)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Later Trains

    private var laterTrainsButton: some View {
        Button {
            timeOffset = min(timeOffset + 30, 90)
            Task { await loadBoard() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(timeOffset == 0 ? "Show later trains" : "Show 30 min later")
                    .font(.ui(12, weight: .semibold))
                    .tracking(0.2)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Train List

    /// One board hour and the trains scheduled in it, in board order.
    private struct HourGroup: Identifiable {
        let id: String
        let label: String
        let startIndex: Int
        var trains: [Train]
    }

    /// Consecutive runs of the same scheduled hour. Walking the sorted list
    /// (rather than bucketing by hour value) keeps midnight-crossing boards
    /// in order: 23:00 and the following 00:00 stay separate groups.
    private var hourGroups: [HourGroup] {
        var groups: [HourGroup] = []
        var index = 0
        for train in filtered {
            let label = train.time.split(separator: ":").first.map { "\($0):00" } ?? "—"
            if var last = groups.last, last.label == label {
                last.trains.append(train)
                groups[groups.count - 1] = last
            } else {
                groups.append(HourGroup(id: "\(label)-\(groups.count)", label: label, startIndex: index, trains: [train]))
            }
            index += 1
        }
        return groups
    }

    private func hourHeader(_ group: HourGroup) -> some View {
        HStack(spacing: 10) {
            Text(group.label)
                .font(.mono(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSoft)
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
            Text("\(group.trains.count) train\(group.trains.count == 1 ? "" : "s")")
                .font(.mono(10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.cream)
    }

    private var trainList: some View {
        VStack(spacing: 12) {
            if isLoading && services.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonTrainCard()
                }
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.inkMute)
                    Text("Couldn't load board")
                        .font(.display(18))
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                    Button {
                        Task { await loadBoard() }
                    } label: {
                        Text("Try again")
                            .font(.ui(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if services.isEmpty {
                if timeOffset > -120 {
                    earlierTrainsButton
                }
                VStack(spacing: 4) {
                    Text(filterDestination != nil ? "No direct trains" : "No services")
                        .font(.display(18))
                    Text(filterDestination.map { "Nothing runs direct to \($0.name) right now" }
                        ?? "No \(isArrival ? "arrivals" : "departures") currently scheduled")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                if let dest = filterDestination, !isArrival {
                    TransferSection(
                        originStation: station,
                        destinationCrs: dest.code,
                        destinationName: dest.name,
                        accent: accent,
                        onSelectTrain: onOpenTrain
                    )
                }
                if timeOffset < 90 {
                    laterTrainsButton
                }
            } else {
                if timeOffset > -120 {
                    earlierTrainsButton
                }
                // Live search matched nothing on this board.
                let liveQuery = searchText.trimmingCharacters(in: .whitespaces)
                if filtered.isEmpty, filterDestination == nil, !liveQuery.isEmpty {
                    VStack(spacing: 4) {
                        Text("No matching trains")
                            .font(.display(18))
                        Text("Nothing on this board \(isArrival ? "arrives from" : "calls at") \u{201C}\(liveQuery)\u{201D}")
                            .font(.ui(11))
                            .foregroundStyle(Theme.inkMute)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                // Client-side filtering can empty a non-empty board (server
                // filter unconfirmed); give that the same transfer fallback
                // as an empty server-filtered board.
                if filtered.isEmpty, let dest = filterDestination, !isArrival {
                    VStack(spacing: 4) {
                        Text("No direct trains")
                            .font(.display(18))
                        Text("Nothing runs direct to \(dest.name) right now")
                            .font(.ui(11))
                            .foregroundStyle(Theme.inkMute)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    TransferSection(
                        originStation: station,
                        destinationCrs: dest.code,
                        destinationName: dest.name,
                        accent: accent,
                        onSelectTrain: onOpenTrain
                    )
                }
                // Hour sections with sticky headers: the header pins below
                // the top bar while its hour scrolls, so a long board reads
                // as "this hour / next hour" instead of a 40-row wall.
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(hourGroups) { group in
                        Section {
                            ForEach(Array(group.trains.enumerated()), id: \.element.id) { index, train in
                                TrainCard(
                                    train: train,
                                    mode: mode,
                                    accent: accent,
                                    callingPoints: callingPoints[train.serviceId] ?? []
                                ) {
                                    onOpenTrain(train)
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .easeOut(duration: 0.3).delay(Double(group.startIndex + index) * 0.04),
                                    value: filtered.count
                                )
                            }
                        } header: {
                            hourHeader(group)
                        }
                    }
                }
                if timeOffset < 90 {
                    laterTrainsButton
                }
            }
            HStack {
                Text(footerLabel)
                    .font(.mono(10))
                    .tracking(1.8)
                    .foregroundStyle(Theme.inkMute)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
    }
}

// MARK: - Train Card

struct TrainCard: View {
    let train: Train
    let mode: BoardMode
    let accent: Color
    let callingPoints: [CallingPointResponse]
    let onTap: () -> Void

    private var isArrival: Bool { mode == .arrivals }
    private var ribbonColor: Color {
        if train.status == .cancelled { return Theme.bad }
        if train.isPredictedPlatform { return accent.opacity(0.45) }
        return accent
    }

    private var callingPreview: [CallingPointResponse] {
        guard !callingPoints.isEmpty else { return [] }
        if isArrival {
            return Array(callingPoints.dropFirst().suffix(3))
        } else {
            return Array(callingPoints.dropLast().prefix(3))
        }
    }

    private var hasMoreStops: Bool {
        if isArrival {
            return callingPoints.dropFirst().count > 3
        } else {
            return callingPoints.dropLast().count > 3
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                ribbon
                cardBody
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.04), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ribbon

    private var ribbon: some View {
        VStack(spacing: 0) {
            Text(train.isPredictedPlatform ? "PREDICTED" : "PLATFORM")
                .font(.mono(train.isPredictedPlatform ? 9 : 10, weight: .medium))
                .tracking(train.isPredictedPlatform ? 1.8 : 2.4)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(maxHeight: .infinity)

            Text(train.platform)
                .font(.display(26))
                .tracking(-0.3)
                .strikethrough(train.status == .cancelled)
                .opacity(train.status == .cancelled ? 0.7 : 1)
        }
        .foregroundStyle(train.isPredictedPlatform ? Theme.ink.opacity(0.7) : Theme.ink)
        .frame(width: 42)
        .padding(.vertical, 14)
        .background(ribbonColor)
        .overlay(alignment: .leading) {
            if train.isPredictedPlatform {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 2)
                    .overlay(
                        Line()
                            .stroke(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    )
            }
        }
    }

    // MARK: - Body

    private var cardBody: some View {
        VStack(spacing: 10) {
            topRow
            routeSection
            if let reason = train.cancelReason ?? train.delayReason {
                reasonRow(reason)
            }
            if !callingPreview.isEmpty {
                callingRow
            }
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(train.time)
                    .font(.mono(22, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(train.status == .delayed ? Theme.inkMute : timeColor)
                    .strikethrough(train.status == .cancelled || train.status == .delayed)
                if train.status == .delayed {
                    Text(train.statusNote)
                        .font(.mono(18, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.delayedText)
                }
            }
            Spacer()
            StatusPill(
                status: train.status,
                label: train.status == .delayed ? "Delayed" : train.statusNote
            )
        }
    }

    private var timeColor: Color {
        switch train.status {
        case .delayed: return Theme.delayedText
        case .cancelled: return Theme.cancelledText.opacity(0.75)
        case .onTime: return Theme.ink
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isArrival ? "FROM" : "TO")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
                Text(isArrival ? train.origin : train.destination)
                    .font(.display(21))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            if !metaFacts.isEmpty {
                Text(metaFacts.joined(separator: " · "))
                    .font(.mono(11, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(Theme.inkMute)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Single-line facts shown under the destination: duration, via, arrival.
    /// Each piece is dropped when the data isn't available so the line stays
    /// tight on shorter journeys.
    private var metaFacts: [String] {
        var parts: [String] = []
        if let duration = journeyDurationString {
            parts.append(duration)
        }
        if !train.via.isEmpty {
            parts.append("via \(train.via)")
        }
        if let arrival = arrivalAtTerminus {
            parts.append(isArrival ? "dep \(arrival)" : "arr \(arrival)")
        }
        return parts
    }

    private var journeyDurationString: String? {
        guard let depart = journeyDepartTime, let arrive = journeyArriveTime else { return nil }
        return TimeFormat.journeyDuration(from: depart, to: arrive)
    }

    private var arrivalAtTerminus: String? {
        isArrival ? journeyDepartTime : journeyArriveTime
    }

    private var journeyDepartTime: String? {
        if isArrival {
            guard let first = callingPoints.first else { return nil }
            return first.expectedTime.flatMap { TimeFormat.parseClockTime($0) }
                ?? first.scheduledTime
        }
        return TimeFormat.parseClockTime(train.statusNote) ?? train.time
    }

    private var journeyArriveTime: String? {
        if isArrival {
            return TimeFormat.parseClockTime(train.statusNote) ?? train.time
        }
        guard let last = callingPoints.last else { return nil }
        return last.expectedTime.flatMap { TimeFormat.parseClockTime($0) }
            ?? last.scheduledTime
    }

    private func reasonRow(_ reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(train.status == .cancelled ? Theme.cancelledText : Theme.delayedText)
            Text(reason)
                .font(.ui(11))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(train.status == .cancelled ? Theme.bad.opacity(0.15) : Theme.warn.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func callingPointLabel(_ cp: CallingPointResponse) -> String {
        if let p = cp.platform, !p.isEmpty { return "\(cp.station) [\(p)]" }
        return cp.station
    }

    private var callingRow: some View {
        let stops = callingPreview.map { callingPointLabel($0) }.joined(separator: " · ")
        let body = stops + (hasMoreStops ? " · …" : "")
        return Text("Calls at \(Text(body).foregroundStyle(Theme.inkSoft))").foregroundStyle(Theme.inkMute)
            .font(.ui(11))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var operatorBrand: OperatorBrand {
        OperatorBrand.brand(for: train.operatorCode)
    }

    private var bottomRow: some View {
        HStack {
            HStack(spacing: 0) {
                Text(train.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(operatorBrand.bg)
                    .foregroundStyle(operatorBrand.fg)
                Text(train.operator)
                    .font(.ui(11, weight: .medium))
                    .foregroundStyle(operatorBrand.label)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
            }
            .background(operatorBrand.bg.opacity(0.1))
            .clipShape(Capsule())
            if let stock = train.rollingStock?.label {
                Text(stock)
                    .font(.mono(10, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(Theme.inkMute)
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 10)
            if let carriages = train.carriages {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkMute)
                    Text("\(carriages)")
                        .font(.mono(10))
                        .foregroundStyle(Theme.inkMute)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.clear)
                .frame(height: 1)
                .overlay(
                    Line()
                        .stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
    }
}

// MARK: - Shapes

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Hands out service IDs one at a time to the calling-point workers, keeping
/// the number of in-flight detail requests bounded regardless of board size.
private actor MissingServiceQueue {
    private var ids: [String]

    init(ids: [String]) {
        self.ids = ids
    }

    func next() -> String? {
        ids.isEmpty ? nil : ids.removeFirst()
    }
}
