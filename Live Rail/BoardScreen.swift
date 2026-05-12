import SwiftUI

struct BoardScreen: View {
    let station: Station
    let accent: Color
    let onOpenTrain: (Train) -> Void
    let onBack: () -> Void

    @State private var mode: BoardMode = .departures
    @State private var filter: FilterMode = .all
    @State private var services: [Train] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var nrccMessages: [String] = []
    @State private var callingPoints: [String: [CallingPointResponse]] = [:]
    @State private var callingPointsTasks: [Task<Void, Never>] = []
    @State private var showSearch = false
    @State private var showFAQ = false
    @State private var filterDestination: Station?
    @State private var timeOffset: Int = 0
    @State private var favouriteStore = FavouriteStationsStore()
    @State private var stationDisruptions: [StationDisruption] = []
    @State private var disruptionsExpanded = false

    private var fastestDestinations: [Station] {
        favouriteStore.stations.filter { $0.code != station.code }
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
        if let dest = filterDestination {
            result = result.filter { $0.destinationCrs == dest.code }
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
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)H \(m)M AGO" : "\(h)H AGO"
        }
        return "\(mins)M AGO"
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
                            favourites: fastestDestinations,
                            accent: accent,
                            onOpenTrain: onOpenTrain
                        )
                        .padding(.top, 14)
                    }
                    if filterDestination != nil {
                        destinationBanner
                    }
                    filterRow
                    resultsRow
                    trainList
                }
            }
        }
        .background(Theme.cream)
        .refreshable {
            await loadBoard()
        }
        .task {
            await loadBoard()
        }
        .onChange(of: mode) { _, _ in
            Task { await loadBoard() }
        }
        .sheet(isPresented: $showSearch) {
            StationSearchSheet(currentStation: station.code) { selected in
                filterDestination = selected
                Task { await loadBoard() }
            }
        }
        .sheet(isPresented: $showFAQ) {
            FAQSheet()
        }
    }

    // MARK: - Data

    private func loadBoard() async {
        isLoading = true
        loadError = nil
        do {
            let response = try await APIClient.shared.getBoard(
                crs: station.code,
                type: mode == .departures ? "departures" : "arrivals",
                filterCrs: filterDestination?.code,
                timeOffset: timeOffset != 0 ? timeOffset : nil
            )
            withAnimation(.easeOut(duration: 0.3)) {
                services = response.services.map { Train(from: $0) }
                nrccMessages = response.nrccMessages ?? []
            }

            if let disruptions = try? await APIClient.shared.getStationDisruptions(crs: station.code) {
                let activeOperators = Set(response.services.map(\.operatorCode))
                withAnimation(.easeOut(duration: 0.3)) {
                    stationDisruptions = disruptions.disruptions.filter { activeOperators.contains($0.id) }
                }
            }
        } catch {
            services = []
            nrccMessages = []
            stationDisruptions = []
            loadError = (error as? APIError)?.errorDescription ?? "Could not load services"
        }
        isLoading = false
        loadCallingPoints()
    }

    private func loadCallingPoints() {
        for task in callingPointsTasks { task.cancel() }
        callingPointsTasks.removeAll()
        callingPoints = [:]
        let currentMode = mode
        for train in services {
            let serviceId = train.serviceId
            let task = Task {
                guard let details = try? await APIClient.shared.getServiceDetails(serviceId: serviceId) else { return }
                guard !Task.isCancelled else { return }
                let points = currentMode == .departures
                    ? details.subsequentCallingPoints
                    : details.previousCallingPoints
                withAnimation(.easeIn(duration: 0.25)) {
                    callingPoints[serviceId] = points
                }
            }
            callingPointsTasks.append(task)
        }
    }

    // MARK: - Header

    /// Sits outside the ScrollView so the back / mode toggle / search / info
    /// controls stay reachable while the board scrolls beneath. Top padding
    /// keeps it clear of the status bar and Dynamic Island.
    private var pinnedTopBar: some View {
        topBar
            .padding(.horizontal, 18)
            .padding(.top, 62)
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

            HStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    IconButton(systemName: "magnifyingglass", size: 14) { showSearch = true }
                    if filterDestination != nil {
                        Circle()
                            .fill(Color(hex: 0xC94A2E))
                            .frame(width: 7, height: 7)
                            .offset(x: -4, y: 4)
                    }
                }
                IconButton(systemName: "info.circle", size: 14) { showFAQ = true }
            }
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
                Button(action: onBack) {
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

    // MARK: - Destination Banner

    private var destinationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent)
            Text("Calling at \(Text(filterDestination?.name ?? "").font(.ui(12, weight: .semibold)).foregroundStyle(Theme.ink))")
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 18)
        .padding(.top, 12)
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
            Button {} label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                    if filter != .all {
                        Circle()
                            .fill(Color(hex: 0xC94A2E))
                            .frame(width: 7, height: 7)
                            .offset(x: -8, y: 8)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
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

    // MARK: - Train List

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
                    Text("No services")
                        .font(.display(18))
                    Text("No \(isArrival ? "arrivals" : "departures") currently scheduled")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                if timeOffset > -120 {
                    earlierTrainsButton
                }
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, train in
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
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.04), value: filtered.count)
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
                    .foregroundStyle(operatorBrand.bg)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
            }
            .background(operatorBrand.bg.opacity(0.1))
            .clipShape(Capsule())
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
