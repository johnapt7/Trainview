import UserNotifications

final class TrainNotificationManager {

    struct Snapshot {
        let platform: String?
        let isPredictedPlatform: Bool
        let expectedDeparture: String?
        let isCancelled: Bool
    }

    private var lastSnapshot: Snapshot?
    private var trainDescription = ""
    private var serviceId = ""
    private var isAuthorized = false
    private var didNotifyStopIsNext = false
    private var scheduledReminderKey: String?

    func configure(train: Train, boardingStation: Station) {
        serviceId = train.serviceId
        trainDescription = "Your \(train.time) to \(train.destination)"
        lastSnapshot = nil
        didNotifyStopIsNext = false
        scheduledReminderKey = nil
    }

    /// Fired once per tracked journey, when the user's alighting stop becomes
    /// the next stop.
    func notifyStopIsNext(_ stationName: String) {
        guard isAuthorized, !didNotifyStopIsNext else { return }
        didNotifyStopIsNext = true
        scheduleNotification(
            id: "\(serviceId)-stop-next",
            title: "Your stop is next",
            body: "Get ready to get off at \(stationName)"
        )
    }

    /// Pre-departure reminder, pended with the system so it fires even if the
    /// app is suspended by then. Re-scheduled whenever the expected departure
    /// or platform changes; the key guard avoids churning identical requests.
    func scheduleDepartureReminder(departure: Date, platform: String?) {
        guard isAuthorized else { return }
        let fireInterval = departure.addingTimeInterval(-5 * 60).timeIntervalSinceNow
        guard fireInterval > 10 else { return }

        let key = "\(Int(departure.timeIntervalSince1970))-\(platform ?? "?")"
        guard key != scheduledReminderKey else { return }
        scheduledReminderKey = key

        var body = "\(trainDescription) leaves in 5 minutes"
        if let platform, !platform.isEmpty {
            body += " from Platform \(platform)"
        }

        let content = UNMutableNotificationContent()
        content.title = "Departing soon"
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceId

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(serviceId)-departing-soon"])
        center.add(UNNotificationRequest(
            identifier: "\(serviceId)-departing-soon",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireInterval, repeats: false)
        ))
    }

    /// Fired once when the boarding station's departure is confirmed. Also
    /// clears any still-pending "departing soon" reminder — it's now stale.
    func notifyDeparted(from stationName: String) {
        guard isAuthorized else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["\(serviceId)-departing-soon"])
        scheduleNotification(
            id: "\(serviceId)-departed",
            title: "On the move",
            body: "\(trainDescription) has departed \(stationName)"
        )
    }

    /// Fired as the journey advances past each calling point. The alighting
    /// stop is excluded — it gets the dedicated "Your stop is next" alert.
    func notifyNextStop(_ stationName: String, expectedTime: String?, stopsToGo: Int) {
        guard isAuthorized else { return }
        var body = "Next stop \(stationName)"
        if let expectedTime, isClockTime(expectedTime) {
            body += " · \(expectedTime)"
        }
        if stopsToGo == 1 {
            body += " — 1 stop before yours"
        } else if stopsToGo > 1 {
            body += " — \(stopsToGo) stops before yours"
        }
        scheduleNotification(
            id: "\(serviceId)-next-\(stationName)",
            title: "Next stop",
            body: body
        )
    }

    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    func evaluateChanges(
        platform: String?,
        isPredictedPlatform: Bool,
        expectedDeparture: String?,
        scheduledDeparture: String?,
        isCancelled: Bool,
        hasDepartedBoardingStation: Bool
    ) {
        guard isAuthorized, !hasDepartedBoardingStation else { return }

        let currentPlatform = normalizedPlatform(platform)
        let currentExpected = expectedDeparture

        defer {
            lastSnapshot = Snapshot(
                platform: currentPlatform,
                isPredictedPlatform: isPredictedPlatform,
                expectedDeparture: currentExpected,
                isCancelled: isCancelled
            )
        }

        guard let previous = lastSnapshot else { return }

        if isCancelled && !previous.isCancelled {
            scheduleNotification(
                id: "\(serviceId)-cancelled",
                title: "Train Cancelled",
                body: "\(trainDescription) has been cancelled. Open Trainview for alternatives."
            )
            return
        }

        if let newPlat = currentPlatform {
            if let oldPlat = previous.platform, newPlat != oldPlat {
                scheduleNotification(
                    id: "\(serviceId)-platform-\(newPlat)",
                    title: "Platform Change",
                    body: "\(trainDescription) has moved to Platform \(newPlat)"
                )
            } else if !isPredictedPlatform && previous.isPredictedPlatform {
                scheduleNotification(
                    id: "\(serviceId)-platform-confirmed",
                    title: "Platform Confirmed",
                    body: "\(trainDescription) is confirmed for Platform \(newPlat)"
                )
            }
        }

        if let newExp = currentExpected,
           let scheduled = scheduledDeparture,
           newExp != previous.expectedDeparture,
           isClockTime(newExp),
           newExp != scheduled {
            scheduleNotification(
                id: "\(serviceId)-delay-\(newExp)",
                title: "Delay Update",
                body: "\(trainDescription) is now expected at \(newExp)"
            )
        }
    }

    func reset() {
        lastSnapshot = nil
        didNotifyStopIsNext = false
        scheduledReminderKey = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "\(serviceId)-cancelled",
                "\(serviceId)-platform",
                "\(serviceId)-delay",
                "\(serviceId)-stop-next",
                "\(serviceId)-departing-soon",
                "\(serviceId)-departed"
            ]
        )
    }

    private func scheduleNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceId

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func normalizedPlatform(_ p: String?) -> String? {
        guard let p, !p.isEmpty, p != "—" else { return nil }
        return p.trimmingCharacters(in: .whitespaces)
    }

    private func isClockTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        return parts.count == 2 && Int(parts[0]) != nil && Int(parts[1]) != nil
    }
}
