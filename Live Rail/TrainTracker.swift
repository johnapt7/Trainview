import Foundation
import ActivityKit

@Observable
final class TrainTracker {
    var isTracking = false
    var trackedTrain: Train?
    var trackedStops: [Stop] = []
    var boardingStation: Station?
    var currentStopIndex: Int = 0
    var nextStopIndex: Int = 1
    var progressBetweenStops: Double = 0
    var overallProgress: Double = 0
    var nextStopName: String = ""
    var nextStopExpectedTime: String = ""
    var trainStatus: TrainStatus = .onTime
    var lastPolled: Date?
    var movements: [MovementEvent] = []

    private var stopTimes: [Date?] = []
    private var pollingTask: Task<Void, Never>?
    private var activity: Activity<TrainTrackingAttributes>?
    private let notificationManager = TrainNotificationManager()

    func startTracking(train: Train, stops: [Stop], boardingStation: Station) {
        trackedTrain = train
        trackedStops = stops
        self.boardingStation = boardingStation
        stopTimes = TrainTracker.parseStopTimes(stops)
        lastPolled = Date()
        isTracking = true
        recalculatePosition()
        startLiveActivity(train: train, stops: stops)
        notificationManager.configure(train: train, boardingStation: boardingStation)
        Task { await notificationManager.requestPermissionIfNeeded() }
        startPolling()
    }

    func stopTracking() {
        isTracking = false
        pollingTask?.cancel()
        pollingTask = nil
        trackedTrain = nil
        trackedStops = []
        boardingStation = nil
        stopTimes = []
        movements = []
        lastPolled = nil
        notificationManager.reset()
        endLiveActivity()
    }

    func isTrackingService(_ serviceId: String) -> Bool {
        isTracking && trackedTrain?.serviceId == serviceId
    }

    var nextStopArrivalDate: Date? {
        guard nextStopIndex < stopTimes.count else { return nil }
        return stopTimes[nextStopIndex]
    }

    var previousStopDepartureDate: Date? {
        guard currentStopIndex >= 0, currentStopIndex < stopTimes.count else { return nil }
        return stopTimes[currentStopIndex]
    }

    var destinationArrivalDate: Date? {
        stopTimes.last ?? nil
    }

    // MARK: - Position Inference

    private func recalculatePosition() {
        guard !trackedStops.isEmpty else { return }

        let now = Date()
        var lastPassedIndex = -1

        if !movements.isEmpty {
            var departures: Set<String> = []
            var arrivals: Set<String> = []
            for event in movements {
                guard let crs = event.crs, !crs.isEmpty else { continue }
                if event.eventType == "DEPARTURE" { departures.insert(crs) }
                if event.eventType == "ARRIVAL" { arrivals.insert(crs) }
            }

            var lastDeparted = -1
            for (i, stop) in trackedStops.enumerated() {
                guard !stop.crs.isEmpty, departures.contains(stop.crs) else { continue }
                lastDeparted = i
            }

            if lastDeparted >= 0 {
                lastPassedIndex = lastDeparted
                let nextIdx = lastDeparted + 1
                if nextIdx < trackedStops.count {
                    let nextCRS = trackedStops[nextIdx].crs
                    if !nextCRS.isEmpty && arrivals.contains(nextCRS) && !departures.contains(nextCRS) {
                        lastPassedIndex = nextIdx
                    }
                }
            }
        }

        if lastPassedIndex < 0 {
            let hasConfirmedDeparture = trackedStops.contains { $0.hasDeparted }
            if hasConfirmedDeparture {
                for (i, time) in stopTimes.enumerated() {
                    guard let t = time else { continue }
                    if now >= t { lastPassedIndex = i }
                }
            }
        }

        if lastPassedIndex < 0 {
            currentStopIndex = 0
            nextStopIndex = min(1, trackedStops.count - 1)
            progressBetweenStops = 0
            overallProgress = 0
        } else if lastPassedIndex >= trackedStops.count - 1 {
            currentStopIndex = trackedStops.count - 1
            nextStopIndex = trackedStops.count - 1
            progressBetweenStops = 1
            overallProgress = 1
        } else {
            currentStopIndex = lastPassedIndex
            nextStopIndex = lastPassedIndex + 1

            if let prev = stopTimes[lastPassedIndex], let next = stopTimes[nextStopIndex] {
                let totalInterval = next.timeIntervalSince(prev)
                let elapsed = now.timeIntervalSince(prev)
                progressBetweenStops = totalInterval > 0 ? min(max(elapsed / totalInterval, 0), 1) : 0
            } else {
                progressBetweenStops = 0
            }

            let totalStops = max(trackedStops.count - 1, 1)
            overallProgress = (Double(currentStopIndex) + progressBetweenStops) / Double(totalStops)
        }

        if nextStopIndex < trackedStops.count {
            nextStopName = trackedStops[nextStopIndex].station
            nextStopExpectedTime = TrainTracker.clockTimeString(for: trackedStops[nextStopIndex])
        }
    }

    static func clockTimeString(for stop: Stop) -> String {
        if let exp = stop.expectedTime, isClockTime(exp) {
            return exp
        }
        return stop.time
    }

    static func isClockTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        return parts.count == 2 && Int(parts[0]) != nil && Int(parts[1]) != nil
    }

    static func timeHasPassed(_ timeStr: String) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = h
        c.minute = m
        c.second = 0
        guard let target = cal.date(from: c) else { return false }
        if target.timeIntervalSince(now) > 6 * 3600 { return false }
        return target < now
    }

    private static func parseStopTimes(_ stops: [Stop]) -> [Date?] {
        let now = Date()
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.year, .month, .day], from: now)

        func parse(_ s: String) -> Date? {
            let parts = s.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var c = nowComps
            c.hour = h
            c.minute = m
            c.second = 0
            guard let d = cal.date(from: c) else { return nil }
            if d.timeIntervalSince(now) > 6 * 3600 {
                return cal.date(byAdding: .day, value: -1, to: d) ?? d
            } else if d.timeIntervalSince(now) < -18 * 3600 {
                return cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        }

        return stops.map { stop in
            if let exp = stop.expectedTime, let d = parse(exp) { return d }
            return parse(stop.time)
        }
    }

    // MARK: - Polling

    @MainActor
    private func nextPollDelay() -> Duration {
        guard let next = nextStopArrivalDate else { return .seconds(45) }
        let secondsUntil = next.timeIntervalSinceNow
        if secondsUntil < 0 { return .seconds(15) }
        if secondsUntil < 60 { return .seconds(8) }
        if secondsUntil < 180 { return .seconds(15) }
        if secondsUntil < 600 { return .seconds(30) }
        return .seconds(60)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await MainActor.run { self?.nextPollDelay() } ?? .seconds(30)
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { break }
                await self?.poll()
            }
        }
    }

    @MainActor
    private func poll() async {
        guard let train = trackedTrain else { return }
        guard let details = try? await APIClient.shared.getServiceDetails(
            serviceId: train.serviceId,
            crs: boardingStation?.code
        ) else { return }

        var updatedStops: [Stop] = []

        // Previous calling points — the train has already departed these.
        for cp in details.previousCallingPoints {
            updatedStops.append(Stop(from: cp, hasDeparted: true))
        }

        // Boarding station, sitting between previous and subsequent.
        if let boarding = boardingStation {
            let isTerminus = details.subsequentCallingPoints.isEmpty
            let boardTime = isTerminus
                ? (details.scheduledArrival ?? train.time)
                : (details.scheduledDeparture ?? train.time)
            let boardExpected = isTerminus
                ? details.expectedArrival
                : details.expectedDeparture
            let boardDeparted: Bool = {
                if isTerminus { return false }
                if !details.previousCallingPoints.isEmpty { return true }
                let depTime = boardExpected ?? boardTime
                return TrainTracker.timeHasPassed(depTime)
            }()
            updatedStops.append(Stop(
                station: boarding.name,
                crs: boarding.code,
                time: boardTime,
                expectedTime: boardExpected,
                platform: details.platform ?? train.platform,
                type: .stop,
                hasDeparted: boardDeparted
            ))
        }

        // Subsequent calling points.
        for cp in details.subsequentCallingPoints {
            updatedStops.append(Stop(from: cp))
        }

        // Mark first as origin and last as destination.
        if !updatedStops.isEmpty {
            let first = updatedStops[0]
            updatedStops[0] = Stop(
                station: first.station, crs: first.crs,
                time: first.time, expectedTime: first.expectedTime,
                actualTime: first.actualTime,
                platform: first.platform, type: .origin,
                hasDeparted: first.hasDeparted
            )
        }
        if updatedStops.count > 1 {
            let last = updatedStops[updatedStops.count - 1]
            updatedStops[updatedStops.count - 1] = Stop(
                station: last.station, crs: last.crs,
                time: last.time, expectedTime: last.expectedTime,
                actualTime: last.actualTime,
                platform: last.platform, type: .destination,
                hasDeparted: last.hasDeparted
            )
        }

        trackedStops = updatedStops
        stopTimes = TrainTracker.parseStopTimes(updatedStops)
        lastPolled = Date()

        if details.isCancelled {
            trainStatus = .cancelled
        } else if details.delayReason != nil {
            trainStatus = .delayed
        } else {
            trainStatus = .onTime
        }

        let boardingHasDeparted = updatedStops.first { $0.crs == boardingStation?.code }?.hasDeparted ?? false
        let confirmedPlatform = details.platform
        let isPredicted = confirmedPlatform == nil && details.predictedPlatform != nil
        let platformToReport = confirmedPlatform ?? details.predictedPlatform?.platform
        notificationManager.evaluateChanges(
            platform: platformToReport,
            isPredictedPlatform: isPredicted,
            expectedDeparture: details.expectedDeparture,
            scheduledDeparture: details.scheduledDeparture ?? train.time,
            isCancelled: details.isCancelled,
            hasDepartedBoardingStation: boardingHasDeparted
        )

        if let rid = train.rid {
            let resp = try? await APIClient.shared.getMovements(rid: rid, uid: train.uid)
            if let events = resp?.movements, !events.isEmpty {
                movements = events
            }
        }

        recalculatePosition()
        updateLiveActivity()

        if overallProgress >= 1.0 {
            stopTracking()
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(train: Train, stops: [Stop]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TrainTrackingAttributes(
            serviceId: train.serviceId,
            origin: train.origin,
            destination: train.destination,
            operatorCode: train.operatorCode,
            operatorName: train.operator,
            scheduledDeparture: stops.first?.time ?? train.time,
            scheduledArrival: stops.last?.time ?? "",
            totalStops: stops.count
        )

        let state = makeContentState()

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(180)),
                pushType: nil
            )
        } catch {
            // Live Activity not available — in-app tracking still works
        }
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let state = makeContentState()
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(180)))
        }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let state = makeContentState()
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
        }
        self.activity = nil
    }

    private func makeContentState() -> TrainTrackingAttributes.ContentState {
        let nextStop: Stop? = {
            guard nextStopIndex < trackedStops.count else { return nil }
            return trackedStops[nextStopIndex]
        }()

        let nextPlatform: String? = {
            guard let p = nextStop?.platform else { return nil }
            return (p.isEmpty || p == "—") ? nil : p
        }()

        let currentName: String = {
            guard currentStopIndex >= 0, currentStopIndex < trackedStops.count else { return "" }
            return trackedStops[currentStopIndex].station
        }()

        let departed = trackedStops.contains { $0.hasDeparted }

        return TrainTrackingAttributes.ContentState(
            currentStopIndex: currentStopIndex,
            currentStopName: currentName,
            nextStopName: nextStopName,
            nextStopExpectedTime: nextStopExpectedTime,
            nextStopPlatform: nextPlatform,
            nextStopDelayMinutes: nextStop?.delayMinutes,
            platform: trackedTrain?.platform ?? "—",
            status: trainStatus.rawValue,
            hasDeparted: departed,
            progressFraction: overallProgress,
            previousStopDepartureDate: previousStopDepartureDate,
            nextStopArrivalDate: nextStopArrivalDate,
            destinationArrivalDate: destinationArrivalDate,
            destinationDelayMinutes: trackedStops.last?.delayMinutes,
            lastUpdated: Date()
        )
    }
}
