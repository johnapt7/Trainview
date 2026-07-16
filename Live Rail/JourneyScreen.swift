import SwiftUI
import CoreLocation

struct JourneyScreen: View {
    let train: Train
    let boardingStation: Station
    let accent: Color
    var tracker: TrainTracker
    let onBack: () -> Void
    /// Swaps the journey screen to another train (re-route suggestions).
    var onSelectTrain: (Train) -> Void = { _ in }

    @State private var details: ServiceDetailsResponse?
    @State private var stops: [Stop] = []
    @State private var stopTimes: [Date?] = []
    @State private var showTrackingSheet = false
    @State private var duration: String = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reliability: ReliabilityStats?
    @State private var stationPins: [StationPin] = []
    @State private var legPaths: [String: [CLLocationCoordinate2D]] = [:]
    @State private var isLoadingMap = true
    @State private var movements: [MovementEvent] = []
    @State private var coaches: [CoachDisplay] = []
    @State private var divideAssociations: [TrainAssociation] = []
    /// Index of the boarding station in `stops` — the hero and fact tiles
    /// describe the user's leg from here, not the whole service.
    @State private var boardingIndex: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Stops remaining on the user's leg (boarding station → terminus).
    private var personalStopCount: Int {
        max(stops.count - 1 - boardingIndex, 0)
    }

    private var originName: String { details?.origin?.name ?? train.origin }
    private var destName: String { details?.destination?.name ?? train.destination }
    private var originCrs: String { details?.origin?.crs ?? "" }
    private var destCrs: String { details?.destination?.crs ?? "" }
    private var departPlatform: String { details?.platform ?? train.platform }

    private var heroBg: Color {
        switch train.status {
        case .cancelled: return Theme.bad
        case .delayed: return Theme.warn
        case .onTime: return accent
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                if isLoading {
                    loadingSection
                        .transition(.opacity)
                } else if let error = loadError {
                    errorSection(error)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        if isTrackingThis {
                            LiveTrackingStrip(tracker: tracker, accent: accent)
                                .padding(.horizontal, 18)
                                .padding(.top, 14)
                        }
                        factsRow
                        if let reason = train.cancelReason ?? train.delayReason {
                            reasonBanner(reason)
                        }
                        if needsAlternatives {
                            AlternativesSection(
                                boardingStation: boardingStation,
                                destinationCrs: destCrs.isEmpty ? train.destinationCrs : destCrs,
                                destinationName: destName,
                                excludedServiceId: train.serviceId,
                                accent: accent,
                                onSelectTrain: onSelectTrain
                            )
                        }
                        if let divide = divideAssociations.first {
                            dividesBanner(divide)
                        }
                        if !coaches.isEmpty {
                            coachSection
                        }
                        performanceCard
                        stopsSection
                        JourneyMapSection(
                            stationPins: stationPins,
                            legPaths: legPaths,
                            isLoading: isLoadingMap,
                            accent: accent,
                            tracker: tracker,
                            serviceId: train.serviceId
                        )
                        .padding(.bottom, 48)
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .background(Theme.cream)
        // The hero paints its brand colour up behind the status bar; content
        // clears it via the hero's own top padding.
        .ignoresSafeArea(edges: .top)
        .task {
            await loadDetails()
        }
        // Untracked journeys were a one-shot snapshot — stop states never
        // updated after departure. Silent refresh keeps them live; when the
        // tracker owns this service its own poll loop covers the stops, so
        // skip the fetch (the tracker's cadence is faster anyway).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                if !isTrackingThis && !isLoading && loadError == nil {
                    await loadDetails(silent: true)
                }
            }
        }
        .sheet(isPresented: $showTrackingSheet) {
            TrackingConfirmationSheet(
                train: train,
                stops: stops,
                boardingStation: boardingStation,
                tracker: tracker,
                accent: accent
            )
        }
    }

    private var isTrackingThis: Bool {
        tracker.isTrackingService(train.serviceId)
    }

    /// While tracking, the tracker is the source of truth for stop times — its
    /// poll cadence keeps `expectedTime` / `actualTime` fresh. Otherwise we
    /// fall back to the snapshot loaded by `loadDetails()`.
    private var displayedStops: [Stop] {
        if isTrackingThis && !tracker.trackedStops.isEmpty {
            return tracker.trackedStops
        }
        return stops
    }

    /// The user's boarding stop, matched by CRS where possible (tracked stop
    /// arrays can be trimmed, so `boardingIndex` only safely indexes the
    /// snapshot `stops`).
    private var boardingStop: Stop? {
        if let match = displayedStops.first(where: { !$0.crs.isEmpty && $0.crs == boardingStation.code }) {
            return match
        }
        guard stops.indices.contains(boardingIndex) else { return nil }
        return stops[boardingIndex]
    }

    /// Re-route suggestions appear when the journey is cancelled, or delayed
    /// 15+ minutes at the boarding station (or delayed with no estimate).
    /// Once the user has departed the boarding station, alternatives from
    /// there are no use, so the card stays hidden.
    private var needsAlternatives: Bool {
        let status = isTrackingThis ? tracker.trainStatus : train.status
        switch status {
        case .cancelled:
            return true
        case .delayed:
            guard let boarding = boardingStop else { return true }
            guard !boarding.hasDeparted else { return false }
            guard let delay = boarding.delayMinutes else { return true }
            return delay >= 15
        case .onTime:
            return false
        }
    }

    private var inferredCurrentStopIndex: Int {
        let hasConfirmedDeparture = stops.contains { $0.hasDeparted }
        guard hasConfirmedDeparture else { return -1 }
        let now = Date()
        var lastPassed = -1
        for (i, t) in stopTimes.enumerated() {
            guard let t else { continue }
            if t <= now { lastPassed = i }
        }
        return lastPassed
    }

    // MARK: - TRUST Movement Correlation

    private var activeTrustMovements: [MovementEvent] {
        if isTrackingThis && !tracker.movements.isEmpty {
            return tracker.movements
        }
        return movements
    }

    private var trustCurrentIndex: Int? {
        let mvts = activeTrustMovements
        guard !mvts.isEmpty else { return nil }

        var departures: Set<String> = []
        var arrivals: Set<String> = []
        for event in mvts {
            guard let crs = event.crs, !crs.isEmpty else { continue }
            if event.eventType == "DEPARTURE" { departures.insert(crs) }
            if event.eventType == "ARRIVAL" { arrivals.insert(crs) }
        }

        let stopsToCheck = displayedStops
        var lastDeparted = -1
        for (i, stop) in stopsToCheck.enumerated() {
            guard !stop.crs.isEmpty, departures.contains(stop.crs) else { continue }
            lastDeparted = i
        }
        guard lastDeparted >= 0 else { return nil }

        let nextIdx = lastDeparted + 1
        if nextIdx < stopsToCheck.count {
            let nextCRS = stopsToCheck[nextIdx].crs
            if !nextCRS.isEmpty && arrivals.contains(nextCRS) && !departures.contains(nextCRS) {
                return nextIdx
            }
        }
        return lastDeparted
    }

    private func trustInfoForStop(_ stop: Stop) -> TRUSTStopInfo? {
        let mvts = activeTrustMovements
        guard !mvts.isEmpty, !stop.crs.isEmpty else { return nil }

        var latestDep: MovementEvent?
        var latestArr: MovementEvent?

        for event in mvts where event.crs == stop.crs {
            if event.eventType == "DEPARTURE" {
                if latestDep == nil || event.actualTimestamp > latestDep!.actualTimestamp {
                    latestDep = event
                }
            } else if event.eventType == "ARRIVAL" {
                if latestArr == nil || event.actualTimestamp > latestArr!.actualTimestamp {
                    latestArr = event
                }
            }
        }

        guard latestDep != nil || latestArr != nil else { return nil }
        let event: MovementEvent = (stop.type == .destination)
            ? (latestArr ?? latestDep!)
            : (latestDep ?? latestArr!)

        return TRUSTStopInfo(
            actualTime: formatISOToClockTime(event.actualTimestamp),
            delayMinutes: event.variationSeconds / 60,
            hasDeparted: latestDep != nil,
            hasArrived: latestArr != nil
        )
    }

    private static func parseStopTimes(_ stops: [Stop]) -> [Date?] {
        let now = Date()
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.year, .month, .day], from: now)
        return stops.map { stop in
            // "Delayed"/"Cancelled" expected times mean the real time is
            // unknown — return nil rather than falling back to the schedule,
            // so position inference can't mark the stop passed by clock.
            if let exp = stop.expectedTime, !TrainTracker.isClockTime(exp) {
                let status = exp.lowercased()
                if status != "on time" && status != "no report" && !status.isEmpty {
                    return nil
                }
            }
            let timeStr: String = {
                if let exp = stop.expectedTime, TrainTracker.isClockTime(exp) { return exp }
                return stop.time
            }()
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var comp = nowComps
            comp.hour = h
            comp.minute = m
            comp.second = 0
            guard let stopDate = cal.date(from: comp) else { return nil }
            if stopDate.timeIntervalSince(now) > 6 * 3600 {
                return cal.date(byAdding: .day, value: -1, to: stopDate) ?? stopDate
            } else if stopDate.timeIntervalSince(now) < -18 * 3600 {
                return cal.date(byAdding: .day, value: 1, to: stopDate) ?? stopDate
            }
            return stopDate
        }
    }

    private func trackingState(for index: Int) -> StopTrackingState {
        if isTrackingThis {
            if index < tracker.currentStopIndex { return .passed }
            if index == tracker.currentStopIndex { return .current }
            if index == tracker.nextStopIndex { return .next }
            return .upcoming
        }
        if let trustIdx = trustCurrentIndex {
            if index < trustIdx { return .passed }
            if index == trustIdx { return .current }
            if index == trustIdx + 1 { return .next }
            return .upcoming
        }
        let currentIdx = inferredCurrentStopIndex
        if currentIdx < 0 { return .notTracking }
        if index < currentIdx { return .passed }
        if index == currentIdx { return .current }
        if index == currentIdx + 1 { return .next }
        return .upcoming
    }

    // MARK: - Data

    /// Loads service details. Silent reloads (the auto-refresh loop) keep the
    /// last good snapshot on failure and skip the one-time extras
    /// (reliability, map coordinates).
    private func loadDetails(silent: Bool = false) async {
        do {
            let response = try await APIClient.shared.getServiceDetails(
                serviceId: train.serviceId,
                crs: boardingStation.code
            )
            details = response

            var allStops: [Stop] = []

            // previousCallingPoints are relative to the boarding station, NOT
            // the train's position — only an actual time proves them passed.
            for cp in response.previousCallingPoints {
                allStops.append(Stop(from: cp, hasDeparted: TrainTracker.hasBeenPassed(cp)))
            }

            // The boarding station itself — sits between previous and subsequent.
            // This is current/just-passed when the train is in progress.
            let boardingIsTerminal = response.subsequentCallingPoints.isEmpty
            let boardingTime = boardingIsTerminal
                ? (response.scheduledArrival ?? train.time)
                : (response.scheduledDeparture ?? train.time)
            let boardingExpected = boardingIsTerminal
                ? response.expectedArrival
                : response.expectedDeparture
            let boardingDeparted = !boardingIsTerminal && TrainTracker.boardingDeparted(
                details: response,
                movements: movements,
                boardingCRS: boardingStation.code
            )
            allStops.append(Stop(
                station: boardingStation.name,
                crs: boardingStation.code,
                time: boardingTime,
                expectedTime: boardingExpected,
                platform: response.platform ?? train.platform,
                type: .stop,
                hasDeparted: boardingDeparted
            ))

            // All subsequentCallingPoints.
            for cp in response.subsequentCallingPoints {
                allStops.append(Stop(from: cp, hasDeparted: TrainTracker.hasBeenPassed(cp)))
            }

            // Mark first as origin, last as destination.
            if !allStops.isEmpty {
                let first = allStops[0]
                allStops[0] = Stop(
                    station: first.station, crs: first.crs,
                    time: first.time, expectedTime: first.expectedTime,
                    actualTime: first.actualTime,
                    platform: first.platform, type: .origin,
                    hasDeparted: first.hasDeparted
                )
            }
            if allStops.count > 1 {
                let last = allStops[allStops.count - 1]
                allStops[allStops.count - 1] = Stop(
                    station: last.station, crs: last.crs,
                    time: last.time, expectedTime: last.expectedTime,
                    actualTime: last.actualTime,
                    platform: last.platform, type: .destination,
                    hasDeparted: last.hasDeparted
                )
            }

            stops = allStops
            stopTimes = JourneyScreen.parseStopTimes(allStops)
            // The boarding station is the row appended after the previous
            // calling points, so its index is exactly their count.
            boardingIndex = min(response.previousCallingPoints.count, max(allStops.count - 1, 0))
            let boardTime = allStops.indices.contains(boardingIndex) ? allStops[boardingIndex].time : ""
            let lastTime = allStops.last?.time ?? ""
            duration = computeDuration(from: boardTime, to: lastTime)
        } catch {
            // A failed silent refresh keeps showing the last good snapshot.
            if !silent {
                stops = []
                stopTimes = []
                loadError = (error as? APIError)?.errorDescription ?? "Could not load service details"
            }
        }

        withAnimation(.easeOut(duration: 0.35)) {
            isLoading = false
        }

        if !silent, loadError == nil,
           let dCrs = details?.destination?.crs, !dCrs.isEmpty,
           let oCrs = details?.origin?.crs, !oCrs.isEmpty {
            reliability = try? await APIClient.shared.getReliability(origin: oCrs, destination: dCrs, days: 5)
        }

        if let rid = train.rid {
            let resp = try? await APIClient.shared.getMovements(rid: rid, uid: train.uid)
            if let events = resp?.movements, !events.isEmpty {
                movements = events.sorted { $0.actualTimestamp > $1.actualTimestamp }
            }
            await loadTrainExtras(rid: rid)
        }

        if !silent {
            Task { await loadMapCoordinates() }
        }
    }

    /// Fetches formation, coach loading, and associations — all served from
    /// in-memory caches on the backend, so cheap enough to refresh on every
    /// poll. Each is best-effort: absent data just hides its section.
    private func loadTrainExtras(rid: String) async {
        async let formationFetch = try? APIClient.shared.getFormation(rid: rid)
        async let loadingFetch = try? APIClient.shared.getTrainLoading(rid: rid)
        async let associationsFetch = try? APIClient.shared.getAssociations(rid: rid)

        let formation = await formationFetch
        let loading = await loadingFetch
        let associations = await associationsFetch

        let merged = Self.mergeCoachData(
            formation: formation,
            loading: loading,
            boardingCRS: boardingStation.code
        )
        let divides = (associations?.associations ?? [])
            .filter { $0.category == "divide" && !$0.cancelled }

        withAnimation(.easeOut(duration: 0.3)) {
            coaches = merged
            divideAssociations = divides
        }
    }

    /// Merges the formation coach list with the most relevant loading record:
    /// the one observed at the boarding station if present, otherwise the
    /// first record carrying data. Falls back to loading-only coaches when
    /// no formation is cached.
    static func mergeCoachData(
        formation: FormationResponse?,
        loading: TrainLoadingResponse?,
        boardingCRS: String
    ) -> [CoachDisplay] {
        let records = loading?.loadings ?? []
        let bestLoading = records.first { $0.crs == boardingCRS && !($0.loading ?? []).isEmpty }
            ?? records.first { !($0.loading ?? []).isEmpty }
        var percentByCoach: [String: Int] = [:]
        for entry in bestLoading?.loading ?? [] {
            if let number = entry.coachNumber, let pct = entry.percent {
                percentByCoach[number] = pct
            }
        }

        let formationCoaches = formation?.formation?.first?.coaches?.coach ?? []
        if !formationCoaches.isEmpty {
            return formationCoaches.enumerated().map { index, coach in
                CoachDisplay(
                    id: "\(coach.coachNumber ?? "")-\(index)",
                    number: coach.coachNumber ?? "?",
                    isFirstClass: coach.coachClass?.lowercased() == "first",
                    toilet: coach.toiletType.flatMap { $0 == "None" ? nil : $0 },
                    loadPercent: coach.coachNumber.flatMap { percentByCoach[$0] }
                )
            }
        }

        // No formation cached — build the diagram from loading data alone.
        return (bestLoading?.loading ?? []).enumerated().compactMap { index, entry in
            guard let number = entry.coachNumber else { return nil }
            return CoachDisplay(
                id: "\(number)-\(index)",
                number: number,
                isFirstClass: false,
                toilet: nil,
                loadPercent: entry.percent
            )
        }
    }

    private func loadMapCoordinates() async {
        guard !stops.isEmpty else {
            isLoadingMap = false
            return
        }

        var entries: [(crs: String, name: String, type: StopType)] = []
        var extraCoords: [String: (lat: Double, lng: Double)] = [:]

        for stop in stops {
            if !stop.crs.isEmpty {
                entries.append((stop.crs, stop.station, stop.type))
            } else if stop.type == .origin {
                if let result = try? await APIClient.shared.searchStations(query: stop.station, limit: 1).first,
                   let lat = result.latitude, let lng = result.longitude {
                    entries.append((result.crs, stop.station, .origin))
                    extraCoords[result.crs] = (lat, lng)
                }
            } else if stop.type == .destination {
                if let result = try? await APIClient.shared.searchStations(query: stop.station, limit: 1).first,
                   let lat = result.latitude, let lng = result.longitude {
                    entries.append((result.crs, stop.station, .destination))
                    extraCoords[result.crs] = (lat, lng)
                }
            }
        }

        var coords = await APIClient.shared.getStationCoordinates(crsCodes: entries.map(\.crs))
        for (key, val) in extraCoords { coords[key] = val }

        var pins: [StationPin] = []
        for (i, entry) in entries.enumerated() {
            guard let coord = coords[entry.crs] else { continue }
            pins.append(StationPin(
                id: "\(entry.crs)-\(i)",
                crs: entry.crs,
                name: entry.name,
                coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng),
                type: entry.type
            ))
        }

        withAnimation(.easeIn(duration: 0.3)) {
            stationPins = pins
            isLoadingMap = false
        }
        await loadRouteGeometry(for: pins)
    }

    /// Real track shapes for each leg, keyed "FROM-TO" in travel direction.
    /// Best-effort: on any failure the map keeps its straight-line fallback.
    private func loadRouteGeometry(for pins: [StationPin]) async {
        guard pins.count >= 2 else { return }
        guard let response = try? await APIClient.shared.getRouteGeometry(crsCodes: pins.map(\.crs)) else {
            return
        }
        var paths: [String: [CLLocationCoordinate2D]] = [:]
        // Any routed source counts ("nwr" = Network Rail track model,
        // "osm" = OpenStreetMap fallback) — only "straight" legs are skipped
        // since the map already draws straight fallbacks itself.
        for leg in response.legs where leg.source != "straight" && leg.coords.count >= 2 {
            paths["\(leg.from)-\(leg.to)"] = leg.coords.compactMap { pair in
                pair.count == 2 ? CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1]) : nil
            }
        }
        guard !paths.isEmpty else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            legPaths = paths
        }
    }

    private func computeDuration(from start: String, to end: String) -> String {
        let parts1 = start.split(separator: ":")
        let parts2 = end.split(separator: ":")
        guard parts1.count == 2, parts2.count == 2,
              let h1 = Int(parts1[0]), let m1 = Int(parts1[1]),
              let h2 = Int(parts2[0]), let m2 = Int(parts2[1]) else { return "" }
        var diff = (h2 * 60 + m2) - (h1 * 60 + m1)
        if diff < 0 { diff += 24 * 60 }
        let hours = diff / 60
        let mins = diff % 60
        if hours == 0 { return "\(mins)m" }
        return "\(hours)h \(String(format: "%02d", mins))m"
    }

    // MARK: - Loading

    private var loadingSection: some View {
        VStack(spacing: 14) {
            skeletonFactsRow
            skeletonStops
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var skeletonFactsRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.ink.opacity(0.07))
                        .frame(width: 20, height: 16)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.ink.opacity(0.07))
                        .frame(width: 36, height: 14)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.ink.opacity(0.05))
                        .frame(width: 50, height: 10)
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .shimmer()
    }

    private var skeletonStops: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.ink.opacity(0.07))
                    .frame(width: 100, height: 22)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.ink.opacity(0.05))
                    .frame(width: 60, height: 14)
            }
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.ink.opacity(i == 0 || i == 4 ? 0.1 : 0.06))
                            .frame(width: i == 0 || i == 4 ? 14 : 10, height: i == 0 || i == 4 ? 14 : 10)
                            .frame(width: 22)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.ink.opacity(0.07))
                            .frame(width: CGFloat.random(in: 90...160), height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.ink.opacity(0.06))
                            .frame(width: 42, height: 14)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .shimmer()
    }

    // MARK: - Error

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22))
                .foregroundStyle(Theme.inkMute)
            Text("Couldn't load details")
                .font(.display(18))
            Text(error)
                .font(.ui(11))
                .foregroundStyle(Theme.inkMute)
            Button {
                isLoading = true
                loadError = nil
                Task { await loadDetails() }
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
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 0) {
            heroTopBar
            heroBody
            heroOperator
        }
        .padding(.horizontal, 18)
        .padding(.top, 54)
        .padding(.bottom, 22)
        .background(heroBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 26,
                bottomTrailingRadius: 26, topTrailingRadius: 0
            )
        )
        .foregroundStyle(Theme.ink)
        // The hero keeps its bright brand colour in dark mode; forcing light
        // resolution keeps its ink-on-accent contrast intact.
        .environment(\.colorScheme, .light)
    }

    private var heroTopBar: some View {
        ZStack {
            HStack {
                IconButton(systemName: "chevron.left", size: 14, heroStyle: true, action: onBack)
                Spacer()
                if !isLoading {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 38, height: 38)
                            .background(Theme.ink.opacity(0.14))
                            .clipShape(Circle())
                    }
                }
            }
            trackPill
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// Snapshot of the user's leg for the share sheet. While tracking with
    /// an alighting stop, the destination is the user's own stop, not the
    /// terminus.
    private var shareText: String {
        let destinationStop = isTrackingThis ? tracker.trackedStops.last : displayedStops.last
        let departTime = boardingStop.flatMap { TripShareText.bestTime(for: $0) } ?? train.time
        return TripShareText.compose(
            originName: boardingStation.name,
            platform: boardingStop?.platform ?? departPlatform,
            destName: destinationStop?.station ?? destName,
            departTime: departTime,
            arrivalTime: destinationStop.flatMap { TripShareText.bestTime(for: $0) },
            status: isTrackingThis ? tracker.trainStatus : train.status,
            delayMinutes: destinationStop?.delayMinutes,
            operatorName: train.operator
        )
    }

    @ViewBuilder
    private var trackPill: some View {
        switch train.status {
        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.trackPillCancelledFg)
                    .frame(width: 20, height: 20)
                    .background(Theme.trackPillCancelledFg.opacity(0.18))
                    .clipShape(Circle())
                Text("Cancelled")
                    .font(.ui(11, weight: .semibold))
                    .tracking(0.2)
            }
            .padding(.horizontal, 12)
            .padding(.leading, -4)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.trackPillCancelledFg)
            .background(Theme.trackPillCancelledBg)
            .clipShape(Capsule())

        case .delayed:
            Button {
                if isTrackingThis { tracker.stopTracking() } else { showTrackingSheet = true }
            } label: {
                HStack(spacing: 8) {
                    LiveDotColored(color: Theme.trackPillDelayedFg)
                    Text(isTrackingThis ? "Tracking" : "Delayed")
                        .font(.ui(11, weight: .semibold))
                    Text(train.statusNote)
                        .font(.mono(10, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(Theme.trackPillDelayedFg.opacity(0.7))
                        .padding(.leading, 4)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.trackPillDelayedFg.opacity(0.25))
                                .frame(width: 1)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.leading, -4)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.trackPillDelayedFg)
                .background(Theme.trackPillDelayedBg)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .onTime:
            Button {
                if isTrackingThis { tracker.stopTracking() } else { showTrackingSheet = true }
            } label: {
                HStack(spacing: 8) {
                    LiveDotColored(color: accent)
                    Text(isTrackingThis ? "Tracking" : "Track live")
                        .font(.ui(11, weight: .semibold))
                    Text(train.statusNote)
                        .font(.mono(10, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(accent.opacity(0.7))
                        .padding(.leading, 4)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(accent.opacity(0.25))
                                .frame(width: 1)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.leading, -4)
                .padding(.vertical, 6)
                .foregroundStyle(accent)
                .background(Theme.ink)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var heroBody: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(train.time)
                    .font(.mono(14, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkSoft)
                // The user's boarding station — train.time and the platform
                // are both relative to it, so the origin name would mislead
                // anyone boarding mid-route.
                Text(boardingStation.name)
                    .font(.display(22))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Platform \(departPlatform)")
                    .font(.mono(10, weight: .medium))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSoft)
                if boardingIndex > 0 {
                    Text("Service from \(train.origin)")
                        .font(.mono(9))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                if !duration.isEmpty {
                    Text(duration)
                        .font(.mono(11, weight: .semibold))
                        .tracking(0.4)
                }
                connectorLine
                if personalStopCount > 1 {
                    Text("\(personalStopCount) STOPS")
                        .font(.mono(9))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(minWidth: 110)

            VStack(alignment: .trailing, spacing: 2) {
                if let lastTime = stops.last?.time, !lastTime.isEmpty {
                    Text(lastTime)
                        .font(.mono(14, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(train.destination)
                    .font(.display(22))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastPlat = stops.last?.platform, lastPlat != "—" {
                    Text("Platform \(lastPlat)")
                        .font(.mono(10, weight: .medium))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 14)
    }

    private var connectorLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Theme.ink)
                .frame(width: 6, height: 6)
            StrokeLine()
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                .frame(height: 1.2)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(height: 14)
        .padding(.vertical, 2)
    }

    private var operatorBrand: OperatorBrand {
        OperatorBrand.brand(for: train.operatorCode)
    }

    /// "Pendolino · Service 12345678" when the rolling stock is known.
    private var heroServiceLine: String {
        let service = "Service \(train.serviceId.prefix(8).uppercased())"
        if let stock = train.rollingStock?.label {
            return "\(stock) · \(service)"
        }
        return service
    }

    private var heroOperator: some View {
        HStack(spacing: 10) {
            Text(train.operatorCode)
                .font(.mono(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(operatorBrand.fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(operatorBrand.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(train.operator)
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(operatorBrand.bg)
                Text(heroServiceLine)
                    .font(.mono(10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(operatorBrand.bg.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 18)
    }

    // MARK: - Facts

    /// Carriage count from the richest source available: the departure
    /// board's length, then the service details' length, then counting the
    /// coaches in the live formation diagram.
    private var carriageCount: Int? {
        train.carriages
            ?? details?.length
            ?? (coaches.isEmpty ? nil : coaches.count)
    }

    private var factsRow: some View {
        HStack(spacing: 8) {
            FactTile(icon: "train.side.front.car", value: carriageCount.map { "\($0)" } ?? "—", label: "Carriages")
            FactTile(icon: "clock", value: duration.isEmpty ? "—" : duration, label: "Journey")
            FactTile(icon: "mappin.and.ellipse", value: personalStopCount < 1 ? "—" : "\(personalStopCount)", label: "Stops")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - Reason Banner

    private func reasonBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(train.status == .cancelled ? Theme.cancelledText : Theme.delayedText)
            Text(reason)
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(train.status == .cancelled ? Theme.bad.opacity(0.3) : Theme.warn.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Divides Banner

    /// Darwin association of category "divide": part of this train separates
    /// at the named station. Coach-level portion data isn't available, so
    /// the copy stays general.
    private func dividesBanner(_ divide: TrainAssociation) -> some View {
        let place = divide.station ?? divide.crs ?? "an intermediate station"
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("This train divides at \(place)")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Check you're in the right portion for your stop — ask staff or listen for announcements on board.")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Coaches

    private var quietestCoach: CoachDisplay? {
        coaches.filter { $0.loadPercent != nil && !$0.isFirstClass }
            .min { ($0.loadPercent ?? 101) < ($1.loadPercent ?? 101) }
    }

    private var hasLoadingData: Bool {
        coaches.contains { $0.loadPercent != nil }
    }

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR TRAIN")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                if hasLoadingData {
                    HStack(spacing: 5) {
                        LiveDot(size: 8)
                        Text("Live busyness")
                            .font(.mono(9, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(Theme.inkMute)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(coaches) { coach in
                        CoachCell(coach: coach, accent: accent)
                    }
                }
            }

            if let quietest = quietestCoach, let pct = quietest.loadPercent {
                Text("Quietest: coach \(Text(quietest.number).bold()) · \(pct)% full")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkSoft)
            } else if !hasLoadingData {
                Text("Coach busyness appears here once reported during the journey")
                    .font(.ui(10))
                    .foregroundStyle(Theme.inkMute)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Performance

    private var performanceCard: some View {
        Group {
            if let stats = reliability {
                let onTimePct = Int(stats.onTimePercent)
                let tone: String = onTimePct >= 80 ? "good" : onTimePct >= 60 ? "ok" : "bad"

                VStack(spacing: 10) {
                    Text("ON-TIME PERFORMANCE")
                        .font(.mono(9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkMute)

                    Text("On time \(Text("\(onTimePct)% of services").font(.ui(17, weight: .semibold)).foregroundColor(tone == "good" ? Theme.perfGood : tone == "bad" ? Theme.perfBad : Theme.ink)) \(Text("over \(stats.period)").font(.mono(14, weight: .medium)).foregroundColor(Theme.inkSoft))")
                        .font(.ui(17))
                        .multilineTextAlignment(.center)

                    // Equal thirds so the counters sit balanced across the
                    // card instead of clustering at the leading edge.
                    HStack(spacing: 0) {
                        StatBadge(value: "\(stats.onTimeServices)", label: "On time", color: Theme.perfGood)
                            .frame(maxWidth: .infinity)
                        StatBadge(value: "\(stats.delayedServices)", label: "Delayed", color: Theme.delayedText)
                            .frame(maxWidth: .infinity)
                        StatBadge(value: "\(stats.cancelledServices)", label: "Cancelled", color: Theme.cancelledText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
    }

    // MARK: - Movements
    //
    // TRUST movements are no longer rendered as their own section — the raw
    // event feed wasn't useful on screen. The data still powers stop states
    // (trustCurrentIndex / trustInfoForStop) and departure evidence.

    private func formatISOToClockTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            df.timeZone = .current
            return df.string(from: date)
        }
        let parts = iso.split(separator: "T")
        if parts.count == 2 {
            let time = parts[1].prefix(5)
            return String(time)
        }
        return iso
    }

    // MARK: - Stops

    private var stopsSection: some View {
        Group {
            if !displayedStops.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Calling at")
                            .font(.display(26, weight: .medium))
                            .tracking(-0.9)
                        Spacer()
                        Text("\(displayedStops.count - 1) stops")
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(Theme.inkMute)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(displayedStops.enumerated()), id: \.element.id) { index, stop in
                            StopRow(
                                stop: stop,
                                isFirst: index == 0,
                                isLast: index == displayedStops.count - 1,
                                accent: accent,
                                trackingState: trackingState(for: index),
                                trustInfo: trustInfoForStop(stop)
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            }
        }
    }
}

// MARK: - Sub-components

/// One coach in the "Your train" diagram: formation identity merged with
/// the latest reported loading percentage (nil until the operator reports).
struct CoachDisplay: Identifiable {
    let id: String
    let number: String
    let isFirstClass: Bool
    let toilet: String?
    let loadPercent: Int?
}

private struct CoachCell: View {
    let coach: CoachDisplay
    let accent: Color

    private var fillColor: Color {
        guard let pct = coach.loadPercent else { return Theme.ink.opacity(0.05) }
        if pct <= 40 { return Theme.perfGood.opacity(0.28) }
        if pct <= 70 { return Theme.warn.opacity(0.45) }
        return Theme.cancelledText.opacity(0.3)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(coach.number)
                .font(.mono(10, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if coach.isFirstClass {
                Text("1st")
                    .font(.mono(8, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else if let pct = coach.loadPercent {
                Text("\(pct)%")
                    .font(.mono(9))
                    .foregroundStyle(Theme.inkSoft)
            } else if coach.toilet == "Accessible" {
                Image(systemName: "figure.roll")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.inkMute)
            } else {
                Text("—")
                    .font(.mono(9))
                    .foregroundStyle(Theme.inkMute.opacity(0.5))
            }
        }
        .frame(width: 44, height: 46)
        .background(fillColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(coach.isFirstClass ? Theme.ink.opacity(0.4) : Theme.line, lineWidth: 1)
        )
    }
}

private struct FactTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Text(value)
                .font(.display(15))
                .lineLimit(1)
            Text(label.uppercased())
                .font(.mono(9))
                .tracking(0.7)
                .foregroundStyle(Theme.inkMute)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.mono(16, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.mono(9))
                .tracking(0.5)
                .foregroundStyle(Theme.inkMute)
        }
    }
}

private struct LiveDotColored: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 20, height: 20)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

enum StopTrackingState {
    case notTracking
    case passed
    case current
    case next
    case upcoming
}

struct TRUSTStopInfo {
    let actualTime: String
    let delayMinutes: Int
    let hasDeparted: Bool
    let hasArrived: Bool
}

private struct StopRow: View {
    let stop: Stop
    let isFirst: Bool
    let isLast: Bool
    let accent: Color
    var trackingState: StopTrackingState = .notTracking
    var trustInfo: TRUSTStopInfo? = nil

    private var isEndpoint: Bool {
        stop.type == .origin || stop.type == .destination
    }

    private var isPassed: Bool { trackingState == .passed }
    private var isCurrent: Bool { trackingState == .current }
    private var isNext: Bool { trackingState == .next }

    var body: some View {
        HStack(spacing: 12) {
            timeline
            content
            Spacer()
            timeColumn
        }
        .padding(.vertical, 10)
        .opacity(isPassed ? 0.5 : 1)
    }

    private var lineColor: Color {
        isPassed || isCurrent ? accent : Theme.lineStrong
    }

    private var timeline: some View {
        ZStack {
            if !isFirst {
                VStack {
                    Rectangle()
                        .fill(isPassed || isCurrent ? accent : Theme.lineStrong)
                        .frame(width: 2)
                    Spacer()
                }
                .frame(height: 20)
                .offset(y: -15)
            }

            if !isLast {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(isPassed ? accent : Theme.lineStrong)
                        .frame(width: 2)
                }
                .frame(height: 20)
                .offset(y: 15)
            }

            if isCurrent {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 16, height: 16)
                    Circle()
                        .stroke(accent.opacity(0.4), lineWidth: 3)
                        .frame(width: 22, height: 22)
                    Image(systemName: "tram.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.ink)
                }
            } else if isPassed {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: isEndpoint ? 14 : 10, height: isEndpoint ? 14 : 10)
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            } else if isEndpoint {
                ZStack {
                    Circle()
                        .fill(isNext ? accent : accent)
                        .stroke(Theme.ink, lineWidth: 2)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 5, height: 5)
                }
            } else {
                Circle()
                    .fill(Theme.cream)
                    .stroke(isNext ? accent : Theme.inkMute, lineWidth: isNext ? 2 : 1.5)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 22, height: 30)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(stop.station)
                    .font(isEndpoint || isCurrent ? .display(17) : .ui(14, weight: .medium))
                    .tracking(isEndpoint ? -0.1 : -0.05)
                    .foregroundStyle(Theme.ink)
                if isNext {
                    CodeTag(text: "NEXT", bg: accent, fg: Theme.ink)
                }
            }

            HStack(spacing: 6) {
                if stop.type == .origin {
                    CodeTag(text: "DEPART")
                }
                if stop.type == .destination {
                    CodeTag(text: "ARRIVE", bg: accent, fg: Theme.ink)
                }
                if stop.platform != "—" {
                    Text("Plat. \(Text(stop.platform).bold())")
                }
            }
            .font(.mono(10, weight: .medium))
            .tracking(0.4)
            .foregroundStyle(Theme.inkMute)
        }
    }

    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let trust = trustInfo {
                HStack(spacing: 5) {
                    Text(trust.actualTime)
                        .font(.mono(14, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(trust.delayMinutes > 0 ? Theme.delayedText : Theme.ink)
                    if trust.delayMinutes != 0 {
                        DelayChip(minutes: trust.delayMinutes)
                    }
                }
                if trust.actualTime != stop.time {
                    Text(stop.time)
                        .font(.mono(11))
                        .tracking(-0.1)
                        .foregroundStyle(Theme.inkMute)
                        .strikethrough(color: Theme.inkMute)
                }
            } else {
                HStack(spacing: 5) {
                    Text(displayTime)
                        .font(.mono(14, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(timeColor)
                    if !showsActualTime, let delay = stop.delayMinutes, delay != 0 {
                        DelayChip(minutes: delay)
                    }
                }
            }
            if !stopStatusLabel.isEmpty {
                Text(stopStatusLabel)
                    .font(.mono(9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(stopStatusColor)
            }
        }
    }

    private var showsActualTime: Bool {
        guard let actual = stop.actualTime else { return false }
        return StopRow.parsesAsTime(actual)
    }

    /// When we've replaced the scheduled time with a real observed time, tint
    /// it amber if late so the change is still legible at a glance.
    private var timeColor: Color {
        guard showsActualTime, let delay = stop.delayMinutes, delay > 0 else {
            return Theme.ink
        }
        return Theme.delayedText
    }

    private var displayTime: String {
        if let actual = stop.actualTime, StopRow.parsesAsTime(actual) {
            return actual
        }
        return stop.time
    }

    static func parsesAsTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        guard parts.count == 2 else { return false }
        return Int(parts[0]) != nil && Int(parts[1]) != nil
    }

    /// Minutes from now until a same-day "HH:MM" clock time; nil when the
    /// string isn't a clock time. Times more than 6h in the past are treated
    /// as tomorrow (post-midnight wrap), matching TrainTracker's anchoring.
    static func minutesUntil(_ timeStr: String) -> Int? {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let now = Date()
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = h
        c.minute = m
        c.second = 0
        guard var target = cal.date(from: c) else { return nil }
        if target.timeIntervalSince(now) < -6 * 3600 {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return Int(target.timeIntervalSince(now) / 60)
    }

    private var stopStatusLabel: String {
        if isPassed {
            return stop.type == .destination ? "ARRIVED" : "DEPARTED"
        }
        if isCurrent {
            if stop.type == .destination { return "ARRIVED" }
            if let trust = trustInfo, trust.hasArrived && !trust.hasDeparted {
                return "AT STATION"
            }
            if stop.type == .origin && !stop.hasDeparted {
                // "Boarding" only means something close to departure — an
                // hour out the train usually isn't even at the platform.
                if let minutes = StopRow.minutesUntil(TrainTracker.clockTimeString(for: stop)),
                   minutes > 15 {
                    return "DEPARTS \(TrainTracker.clockTimeString(for: stop))"
                }
                return "BOARDING"
            }
            return "DEPARTED"
        }
        // Silence means "fine" — only exceptional states get a caption, so
        // delays stand out instead of drowning in a column of "ON TIME".
        switch stop.type {
        case .origin, .destination, .stop: return ""
        case .major: return "DELAYED"
        }
    }

    private var stopStatusColor: Color {
        if isPassed || isCurrent { return Theme.inkMute }
        return stop.type == .major ? Theme.delayedText : Theme.onTimeSub
    }
}

private struct StrokeLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

// MARK: - Delay chip

private struct DelayChip: View {
    let minutes: Int

    private var color: Color {
        minutes > 0 ? Theme.delayedText : Theme.perfGood
    }

    var body: some View {
        Text(minutes > 0 ? "+\(minutes)" : "\(minutes)")
            .font(.mono(10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Live tracking strip

private struct LiveTrackingStrip: View {
    var tracker: TrainTracker
    let accent: Color

    private var statusTint: Color {
        switch tracker.trainStatus {
        case .delayed: return Theme.delayedText
        case .cancelled: return Theme.cancelledText
        case .onTime: return accent
        }
    }

    private var operatorBrand: OperatorBrand? {
        guard let code = tracker.trackedTrain?.operatorCode, !code.isEmpty else { return nil }
        return OperatorBrand.brand(for: code)
    }

    private var lastDeparted: Stop? {
        let idx = tracker.currentStopIndex
        guard idx >= 0, idx < tracker.trackedStops.count else { return nil }
        return tracker.trackedStops[idx]
    }

    private var nextStop: Stop? {
        let idx = tracker.nextStopIndex
        guard idx >= 0, idx < tracker.trackedStops.count else { return nil }
        return tracker.trackedStops[idx]
    }

    private var destinationStop: Stop? { tracker.trackedStops.last }

    private var atOrigin: Bool {
        tracker.currentStopIndex == 0 && tracker.overallProgress == 0
    }

    private var atTerminus: Bool {
        tracker.overallProgress >= 1.0 ||
        (tracker.trackedStops.count > 1 && tracker.currentStopIndex == tracker.trackedStops.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stopRow
            progressBar
            Divider().overlay(Theme.line)
            footerRow
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(statusTint.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.2))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(statusTint)
                    .frame(width: 7, height: 7)
            }
            HStack(spacing: 6) {
                Text("TRACKING LIVE")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.ink)
                freshnessLabel
            }
            if let brand = operatorBrand, let code = tracker.trackedTrain?.operatorCode {
                Text(code)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(brand.fg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(brand.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            Button {
                tracker.stopTracking()
            } label: {
                Text("Stop")
                    .font(.ui(11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.ink.opacity(0.06))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var freshnessLabel: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            if let polled = tracker.lastPolled {
                let secondsAgo = Int(context.date.timeIntervalSince(polled))
                let stale = secondsAgo > 120
                Text("· \(formatAge(secondsAgo))")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(stale ? Theme.delayedText : Theme.inkMute)
            }
        }
    }

    private func formatAge(_ seconds: Int) -> String {
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    // MARK: - Stop row (Departed from | Next stop)

    private var stopRow: some View {
        HStack(alignment: .top, spacing: 12) {
            stopColumn(
                label: atOrigin ? "DEPARTING FROM" : "DEPARTED FROM",
                stop: lastDeparted,
                trailing: false
            )
            stopColumn(
                label: atTerminus ? "ARRIVED AT" : "NEXT STOP",
                stop: atTerminus ? destinationStop : nextStop,
                trailing: true
            )
        }
    }

    @ViewBuilder
    private func stopColumn(label: String, stop: Stop?, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(label)
                .font(.mono(9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Theme.inkMute)
            HStack(spacing: 6) {
                Text(stop?.station ?? "—")
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let stop, let time = stopClockTime(stop) {
                    Text(time)
                        .font(.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                }
                if let stop, let delay = stop.delayMinutes, delay != 0 {
                    DelayChip(minutes: delay)
                }
            }
            if let stop, let platform = displayPlatform(stop) {
                Text("Platform \(platform)")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(Theme.inkMute)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func stopClockTime(_ stop: Stop) -> String? {
        let s = TrainTracker.clockTimeString(for: stop)
        return s.isEmpty ? nil : s
    }

    private func displayPlatform(_ stop: Stop) -> String? {
        (stop.platform.isEmpty || stop.platform == "—") ? nil : stop.platform
    }

    // MARK: - Multi-stop timeline

    private var progressBar: some View {
        let stopCount = max(tracker.trackedStops.count, 2)
        let segmentCount = max(stopCount - 1, 1)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.ink.opacity(0.08))
                .frame(height: 3)

            HStack(spacing: 0) {
                ForEach(0..<segmentCount, id: \.self) { i in
                    timelineSegment(index: i)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 3)

            GeometryReader { geo in
                ForEach(0..<stopCount, id: \.self) { i in
                    let fraction = CGFloat(i) / CGFloat(segmentCount)
                    timelineDot(at: i, totalStops: stopCount)
                        .position(x: fraction * geo.size.width, y: geo.size.height / 2)
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private func timelineSegment(index: Int) -> some View {
        if index < tracker.currentStopIndex {
            // Passed segment — solid fill
            Capsule()
                .fill(statusTint)
                .frame(height: 3)
        } else if index == tracker.currentStopIndex,
                  let prev = tracker.previousStopDepartureDate,
                  let next = tracker.nextStopArrivalDate,
                  prev < next,
                  tracker.currentStopIndex != tracker.nextStopIndex {
            // Active segment — smooth timer-driven fill
            ProgressView(timerInterval: prev...next, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(statusTint)
            .frame(height: 3)
        } else {
            Color.clear.frame(height: 3)
        }
    }

    @ViewBuilder
    private func timelineDot(at index: Int, totalStops: Int) -> some View {
        let isPassed = index < tracker.currentStopIndex
        let isCurrent = index == tracker.currentStopIndex && tracker.currentStopIndex != tracker.nextStopIndex
        let isNext = index == tracker.nextStopIndex && !isCurrent
        let isEndpoint = index == 0 || index == totalStops - 1

        if isCurrent {
            ZStack {
                Circle().fill(statusTint.opacity(0.25)).frame(width: 16, height: 16)
                Circle().fill(statusTint).frame(width: 8, height: 8)
            }
        } else if isPassed {
            Circle()
                .fill(statusTint)
                .frame(width: isEndpoint ? 8 : 5, height: isEndpoint ? 8 : 5)
        } else if isNext {
            Circle()
                .fill(Theme.card)
                .overlay(Circle().stroke(statusTint, lineWidth: 2))
                .frame(width: 10, height: 10)
        } else if isEndpoint {
            Circle()
                .fill(Theme.ink.opacity(0.25))
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(Theme.ink.opacity(0.18))
                .frame(width: 4, height: 4)
        }
    }

    // MARK: - Footer (Time to next | Destination)

    private var footerRow: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            VStack(alignment: .leading, spacing: 6) {
                sentenceCountdown(now: context.date)
                destinationStatusText
                    .font(.ui(13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sentenceCountdown(now: Date) -> some View {
        if atTerminus {
            Text("Arrived at \(tracker.nextStopName)")
                .font(.ui(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        } else if atOrigin {
            // lastDeparted is the origin row here — nextStopName would be
            // the stop *after* the one the user is actually boarding at.
            let boardingName = lastDeparted?.station ?? tracker.nextStopName
            if tracker.isBoarding {
                Text("Boarding at \(boardingName)")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            } else if let dep = tracker.previousStopDepartureDate {
                Text("Departs \(boardingName) at \(clockString(dep))")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            } else {
                Text("Awaiting departure from \(boardingName)")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
        } else if let arrival = tracker.nextStopArrivalDate {
            let remaining = arrival.timeIntervalSince(now)
            if remaining < 30 && remaining > -120 {
                Text("Approaching \(tracker.nextStopName)")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            } else if remaining > 0 {
                Text("Arrives at \(tracker.nextStopName) in \(formatRemainingDuration(remaining))")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            } else {
                Text("Due now at \(tracker.nextStopName)")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
        } else {
            Text("—")
                .font(.mono(15, weight: .semibold))
                .foregroundStyle(Theme.inkMute)
        }
    }

    private func clockString(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: d)
    }

    private var destinationTimeString: String {
        if let d = tracker.destinationArrivalDate {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: d)
        }
        if let stop = destinationStop {
            return TrainTracker.clockTimeString(for: stop)
        }
        return ""
    }

    private var destinationStatusText: Text {
        let name = destinationStop?.station ?? "destination"
        let timeStr = destinationTimeString

        if tracker.trainStatus == .cancelled {
            return Text("\(Text("Cancelled — final destination ").foregroundColor(Theme.inkSoft))\(Text(name).foregroundColor(Theme.ink).fontWeight(.semibold))")
        }

        let prefix: Text = {
            if let delay = destinationStop?.delayMinutes, delay > 0 {
                return Text("\(delay) min late")
                    .foregroundColor(Theme.delayedText)
                    .fontWeight(.semibold)
            } else if let delay = destinationStop?.delayMinutes, delay < 0 {
                return Text("\(abs(delay)) min early")
                    .foregroundColor(Theme.perfGood)
                    .fontWeight(.semibold)
            } else if tracker.trainStatus == .delayed {
                return Text("Delayed")
                    .foregroundColor(Theme.delayedText)
                    .fontWeight(.semibold)
            } else {
                return Text("Still on time")
                    .foregroundColor(Theme.perfGood)
                    .fontWeight(.semibold)
            }
        }()

        var result = Text("\(prefix)\(Text(" for ").foregroundColor(Theme.inkSoft))\(Text(name).foregroundColor(Theme.ink).fontWeight(.semibold))")

        if !timeStr.isEmpty {
            result = Text("\(result)\(Text(" · ").foregroundColor(Theme.inkSoft))\(Text(timeStr).foregroundColor(Theme.ink))")
        }
        return result
    }

    private func formatRemainingDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds + 30) / 60)
        if totalMinutes < 1 { return "<1 min" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

}
