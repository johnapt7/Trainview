import Foundation
import ActivityKit

/// Everything needed to pick tracking back up after the app is relaunched.
/// Live state is deliberately absent — the first poll refetches it.
struct TrackingSnapshot: Codable {
    let serviceId: String
    let rid: String?
    let uid: String?
    let time: String
    let origin: String
    let destination: String
    let destinationCrs: String
    let platform: String
    let operatorName: String
    let operatorCode: String
    let boardingCode: String
    let boardingName: String
    let alightingCRS: String?
    let savedAt: Date
}

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
    private var alightingCRS: String?
    private var pollingTask: Task<Void, Never>?
    private var activity: Activity<TrainTrackingAttributes>?
    private var pushTokenTask: Task<Void, Never>?
    private var registeredPushToken: String?
    private let notificationManager = TrainNotificationManager()

    // Confirmed platform from the latest poll; nil until the boards announce
    // one. Gates the "boarding" state — see isBoarding.
    private var announcedPlatform: String?

    // One-shot notification state for the tracked journey. Baselined on the
    // first poll so a resumed session doesn't replay old alerts.
    private var notificationBaselineSet = false
    private var didNotifyDeparted = false
    private var lastNotifiedNextStop = 1

    private static let snapshotKey = "trackingSnapshot"

    func startTracking(train: Train, stops: [Stop], boardingStation: Station, alightingCRS: String? = nil) {
        trackedTrain = train
        self.alightingCRS = alightingCRS
        trackedStops = personalStops(stops)
        self.boardingStation = boardingStation
        stopTimes = TrainTracker.parseStopTimes(trackedStops)
        lastPolled = Date()
        isTracking = true
        notificationBaselineSet = false
        didNotifyDeparted = false
        lastNotifiedNextStop = 1
        saveSnapshot(train: train, boardingStation: boardingStation)
        recalculatePosition()
        startLiveActivity(train: train, stops: trackedStops)
        notificationManager.configure(train: train, boardingStation: boardingStation)
        Task { await notificationManager.requestPermissionIfNeeded() }
        startPolling()
    }

    func stopTracking() {
        isTracking = false
        pollingTask?.cancel()
        pollingTask = nil
        pushTokenTask?.cancel()
        pushTokenTask = nil
        if let token = registeredPushToken {
            registeredPushToken = nil
            // Best-effort: the server also ends registrations on its own
            // arrival evidence, so a lost unregister is not fatal.
            Task { try? await APIClient.shared.unregisterLiveActivity(token: token) }
        }
        trackedTrain = nil
        trackedStops = []
        boardingStation = nil
        alightingCRS = nil
        stopTimes = []
        movements = []
        lastPolled = nil
        notificationManager.reset()
        announcedPlatform = nil
        notificationBaselineSet = false
        didNotifyDeparted = false
        lastNotifiedNextStop = 1
        endLiveActivity()
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    // MARK: - Relaunch restoration

    private func saveSnapshot(train: Train, boardingStation: Station) {
        let snapshot = TrackingSnapshot(
            serviceId: train.serviceId, rid: train.rid, uid: train.uid,
            time: train.time, origin: train.origin,
            destination: train.destination, destinationCrs: train.destinationCrs,
            platform: train.platform, operatorName: train.operator,
            operatorCode: train.operatorCode,
            boardingCode: boardingStation.code, boardingName: boardingStation.name,
            alightingCRS: alightingCRS, savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    /// Rebuilds tracking after an app relaunch (force-quit, Xcode rerun,
    /// system eviction). Re-adopts the existing Live Activity instead of
    /// spawning a second one; if the user dismissed the activity, tracking
    /// resumes in-app only. Returns whether tracking is live afterwards.
    @MainActor
    func resumeIfNeeded() async -> Bool {
        if isTracking { return true }
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(TrackingSnapshot.self, from: data) else {
            return false
        }
        guard Date().timeIntervalSince(snapshot.savedAt) < 12 * 3600 else {
            UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
            return false
        }

        let train = Train(
            restoredId: snapshot.serviceId, time: snapshot.time,
            origin: snapshot.origin, destination: snapshot.destination,
            destinationCrs: snapshot.destinationCrs, platform: snapshot.platform,
            operator: snapshot.operatorName, operatorCode: snapshot.operatorCode,
            rid: snapshot.rid, uid: snapshot.uid
        )
        let boarding = Station(code: snapshot.boardingCode, name: snapshot.boardingName)
        trackedTrain = train
        boardingStation = boarding
        alightingCRS = snapshot.alightingCRS
        lastPolled = Date()
        isTracking = true

        activity = Activity<TrainTrackingAttributes>.activities.first {
            $0.attributes.serviceId == snapshot.serviceId
        }
        if activity != nil {
            observePushToken(train: train)
        }
        notificationManager.configure(train: train, boardingStation: boarding)
        // Re-establish authorization: the manager's cached flag starts false
        // in every new process, which silently disabled all alerts after a
        // relaunch until this call existed.
        Task { await notificationManager.requestPermissionIfNeeded() }

        await poll()
        // The catch-up poll may have detected arrival and ended everything.
        guard isTracking else { return false }
        startPolling()
        return true
    }

    /// Immediate refresh for foreground return, so the screen and Live
    /// Activity catch up without waiting out the poll loop's sleep.
    func pollNow() {
        guard isTracking else { return }
        Task {
            // The user may have flipped notification permission in Settings
            // while we were backgrounded — re-read it before evaluating.
            await notificationManager.refreshAuthorization()
            await self.poll()
        }
    }

    /// The user's journey ends where they get off, not where the train
    /// terminates. Trims trailing stops past the alighting station and
    /// re-marks it as the destination, so progress, ETAs, the Live Activity,
    /// and auto-stop all describe the user's journey. Leading stops are kept —
    /// before boarding, "how far away is the train" is the useful signal.
    private func personalStops(_ stops: [Stop]) -> [Stop] {
        guard let crs = alightingCRS,
              let idx = stops.lastIndex(where: { $0.crs == crs }),
              idx > 0, idx < stops.count - 1 else { return stops }
        var trimmed = Array(stops[0...idx])
        let last = trimmed[trimmed.count - 1]
        trimmed[trimmed.count - 1] = Stop(
            station: last.station, crs: last.crs,
            time: last.time, expectedTime: last.expectedTime,
            actualTime: last.actualTime,
            platform: last.platform, type: .destination,
            hasDeparted: last.hasDeparted
        )
        return trimmed
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

    /// True once the journey hasn't started, the platform has actually been
    /// announced, AND we're close enough to the boarding station's departure
    /// (within 15 minutes, or the time is unknown/delayed). Without an
    /// announced platform nobody can be boarding — at a terminus the doors
    /// effectively open when the board shows the platform, not before.
    var isBoarding: Bool {
        guard hasAnnouncedPlatform else { return false }
        guard !trackedStops.contains(where: { $0.hasDeparted }) else { return false }
        let idx = trackedStops.firstIndex { $0.crs == boardingStation?.code } ?? 0
        guard idx < stopTimes.count, let dep = stopTimes[idx] else { return true }
        return dep.timeIntervalSinceNow <= 15 * 60
    }

    private var hasAnnouncedPlatform: Bool {
        guard let announcedPlatform else { return false }
        return !announcedPlatform.isEmpty && announcedPlatform != "—"
    }

    // MARK: - Position Inference

    /// How long the train realistically stands at a stop before departing.
    /// LDBWS calling points carry a single time per stop, so without a dwell
    /// the model's arrival and departure are the same instant — the map icon
    /// would leave the moment it arrives, then jump back when the real
    /// departure time lands. A quarter of the leg, capped at 60s, keeps
    /// short suburban legs sensible.
    static func dwellSeconds(legInterval: TimeInterval?) -> TimeInterval {
        guard let gap = legInterval, gap > 0 else { return 60 }
        return min(60, gap * 0.25)
    }

    private func legInterval(after index: Int) -> TimeInterval? {
        guard index >= 0, index + 1 < stopTimes.count,
              let t = stopTimes[index], let next = stopTimes[index + 1] else { return nil }
        return next.timeIntervalSince(t)
    }

    private func recalculatePosition() {
        guard !trackedStops.isEmpty else { return }

        let now = Date()
        var lastPassedIndex = -1
        var standingAtNextStop = false

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
                        // Arrived but not yet departed: the train is standing
                        // at that station. Hold the icon there instead of
                        // marking the stop passed — advancing on the arrival
                        // event made the icon depart instantly and glitch
                        // back when the real departure arrived.
                        standingAtNextStop = true
                    }
                }
            }
        }

        if lastPassedIndex < 0 {
            let hasConfirmedDeparture = trackedStops.contains { $0.hasDeparted }
            if hasConfirmedDeparture {
                for (i, time) in stopTimes.enumerated() {
                    guard let t = time else { continue }
                    // A stop's single time marks arrival; without feed
                    // evidence, only count it departed once the dwell has
                    // also elapsed, so the icon pauses at the platform.
                    let dwell = Self.dwellSeconds(legInterval: legInterval(after: i))
                    if now >= t.addingTimeInterval(dwell) { lastPassedIndex = i }
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

            if standingAtNextStop {
                progressBetweenStops = 1
            } else if let prev = stopTimes[lastPassedIndex], let next = stopTimes[nextStopIndex] {
                // The leg starts at the previous stop's departure (its time
                // plus dwell), not its arrival. Progress past 1 clamps, which
                // is what holds the icon at the next station between its
                // arrival time and its inferred departure.
                let dwell = Self.dwellSeconds(legInterval: next.timeIntervalSince(prev))
                let departed = prev.addingTimeInterval(dwell)
                let totalInterval = next.timeIntervalSince(departed)
                let elapsed = now.timeIntervalSince(departed)
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

    /// A calling point has verifiably been passed when LDBWS reports an
    /// actual time for it. Schedule position alone is not evidence — LDBWS
    /// splits calling points relative to the queried board station, not the
    /// train's position, so "previous" stops may still be ahead of the train.
    /// LDBWS frequently reports the actual as the literal string "On time"
    /// rather than a clock time — that is still a positive "it happened"
    /// report, so it counts as passed. "No report"/"Delayed" do not.
    static func hasBeenPassed(_ cp: CallingPointResponse) -> Bool {
        guard let at = cp.actualTime else { return false }
        return isClockTime(at) || at.lowercased() == "on time"
    }

    /// Whether the boarding station has verifiably been departed: the next
    /// calling point reporting an actual time, a TRUST departure event at the
    /// boarding CRS, or (last resort) the expected departure time passing.
    /// A non-clock expected time like "Delayed" blocks the clock fallback —
    /// a delayed train must not be inferred departed from its schedule.
    static func boardingDeparted(
        details: ServiceDetailsResponse,
        movements: [MovementEvent],
        boardingCRS: String
    ) -> Bool {
        if let next = details.subsequentCallingPoints.first, hasBeenPassed(next) {
            return true
        }
        if movements.contains(where: { $0.crs == boardingCRS && $0.eventType == "DEPARTURE" }) {
            return true
        }
        if let exp = details.expectedDeparture, !isClockTime(exp) {
            return false
        }
        let depTime = details.expectedDeparture ?? details.scheduledDeparture
        guard let depTime else { return false }
        return timeHasPassed(depTime)
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
            if let exp = stop.expectedTime {
                if let d = parse(exp) { return d }
                // Non-clock statuses: "On time"/"No report" mean the schedule
                // holds; "Delayed"/"Cancelled" mean the real time is unknown —
                // return nil so position inference can't mark the stop passed
                // just because its scheduled time elapsed.
                let status = exp.lowercased()
                if status != "on time" && status != "no report" && !status.isEmpty {
                    return nil
                }
            }
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
            // First poll immediately — waiting out a full interval before the
            // first fetch delays every notification, and can miss the
            // departure-reminder window entirely for imminent trains.
            await self?.poll()
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

        // Fetch TRUST movements before building stops so departed flags can
        // use this poll's evidence, not the previous one's.
        if let rid = train.rid {
            let resp = try? await APIClient.shared.getMovements(rid: rid, uid: train.uid)
            if let events = resp?.movements, !events.isEmpty {
                movements = events
            }
        }

        var updatedStops: [Stop] = []

        // Previous calling points are relative to the boarding station, NOT
        // the train's position — only an actual time proves they were passed.
        for cp in details.previousCallingPoints {
            updatedStops.append(Stop(from: cp, hasDeparted: TrainTracker.hasBeenPassed(cp)))
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
            let boardDeparted = !isTerminus && TrainTracker.boardingDeparted(
                details: details,
                movements: movements,
                boardingCRS: boarding.code
            )
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
            updatedStops.append(Stop(from: cp, hasDeparted: TrainTracker.hasBeenPassed(cp)))
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

        trackedStops = personalStops(updatedStops)
        stopTimes = TrainTracker.parseStopTimes(trackedStops)
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
        // Only the announced (confirmed) platform counts for boarding state —
        // a predicted platform means the boards haven't shown one yet.
        announcedPlatform = confirmedPlatform
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

        recalculatePosition()
        updateLiveActivity()

        // Baseline on the first poll of a session: a resumed journey must not
        // replay departure/stop alerts for legs already travelled.
        if !notificationBaselineSet {
            notificationBaselineSet = true
            didNotifyDeparted = boardingHasDeparted
            lastNotifiedNextStop = nextStopIndex
        }

        if boardingHasDeparted {
            if !didNotifyDeparted,
               notificationManager.notifyDeparted(from: boardingStation?.name ?? "the station") {
                // Consume the one-shot only when the alert was actually
                // scheduled — a not-yet-authorized attempt retries next poll.
                didNotifyDeparted = true
            }
        } else if !details.isCancelled,
                  let bIdx = trackedStops.firstIndex(where: { $0.crs == boardingStation?.code }),
                  bIdx < stopTimes.count, let departure = stopTimes[bIdx] {
            notificationManager.scheduleDepartureReminder(departure: departure, platform: platformToReport)
        }

        // Per-stop alert as the train passes each calling point. The final
        // stop is excluded — notifyStopIsNext below owns that moment. The
        // marker only advances when the alert was actually scheduled (or
        // needed no alert), so a blocked attempt retries next poll.
        if nextStopIndex > lastNotifiedNextStop {
            let alertable = nextStopIndex < trackedStops.count - 1
                && trackedStops.contains(where: { $0.hasDeparted })
            if !alertable || notificationManager.notifyNextStop(
                trackedStops[nextStopIndex].station,
                expectedTime: TrainTracker.clockTimeString(for: trackedStops[nextStopIndex]),
                stopsToGo: trackedStops.count - 1 - nextStopIndex
            ) {
                lastNotifiedNextStop = nextStopIndex
            }
        }

        // The stop the user gets off at is the last tracked stop (trimmed to
        // the alighting station above). Alert once, as soon as it becomes the
        // next stop after a confirmed departure.
        if trackedStops.count > 1,
           nextStopIndex == trackedStops.count - 1,
           currentStopIndex == nextStopIndex - 1,
           trackedStops.contains(where: { $0.hasDeparted }) {
            notificationManager.notifyStopIsNext(trackedStops[nextStopIndex].station)
        }

        // End tracking only on evidence of arrival at the destination — an
        // actual time from LDBWS or a TRUST arrival event — never from clock
        // inference alone, which self-terminates tracking on delayed trains.
        // A 30-minute grace past the last known arrival time is the safety
        // net so tracking can't run forever if evidence never arrives.
        if destinationArrived() {
            stopTracking()
        }
    }

    private func destinationArrived() -> Bool {
        guard let last = trackedStops.last else { return false }
        if let at = last.actualTime, TrainTracker.isClockTime(at) { return true }
        if !last.crs.isEmpty && movements.contains(where: { $0.crs == last.crs && $0.eventType == "ARRIVAL" }) {
            return true
        }
        if let arrival = stopTimes.last ?? nil, Date().timeIntervalSince(arrival) > 30 * 60 {
            return true
        }
        return false
    }

    // MARK: - Live Activity

    private func startLiveActivity(train: Train, stops: [Stop]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TrainTrackingAttributes(
            serviceId: train.serviceId,
            origin: train.origin,
            destination: stops.last?.station ?? train.destination,
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
                pushType: .token
            )
            observePushToken(train: train)
        } catch {
            // Live Activity not available — in-app tracking still works
        }
    }

    /// Streams the activity's push token (it can rotate) to the backend so
    /// it can push updates while the app is suspended. Requires a rid — the
    /// backend correlates TRUST movements by it; without one, tracking stays
    /// app-driven only.
    private func observePushToken(train: Train) {
        pushTokenTask?.cancel()
        guard let activity, let rid = train.rid,
              let boardingCRS = boardingStation?.code else { return }
        let registration = { [weak self] (token: String) async in
            let request = LiveActivityRegistration(
                token: token,
                rid: rid,
                serviceId: train.serviceId,
                uid: train.uid,
                boardingCrs: boardingCRS,
                alightingCrs: self?.alightingCRS
            )
            for attempt in 0..<3 {
                if (try? await APIClient.shared.registerLiveActivity(request)) != nil {
                    await MainActor.run { self?.registeredPushToken = token }
                    return
                }
                try? await Task.sleep(for: .seconds(5 << attempt))
            }
        }
        pushTokenTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await registration(token)
            }
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
            isBoarding: isBoarding,
            progressFraction: overallProgress,
            previousStopDepartureDate: previousStopDepartureDate,
            nextStopArrivalDate: nextStopArrivalDate,
            destinationArrivalDate: destinationArrivalDate,
            destinationDelayMinutes: trackedStops.last?.delayMinutes,
            lastUpdated: Date()
        )
    }
}
