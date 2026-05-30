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

    func configure(train: Train, boardingStation: Station) {
        serviceId = train.serviceId
        trainDescription = "Your \(train.time) to \(train.destination)"
        lastSnapshot = nil
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
                body: "\(trainDescription) has been cancelled"
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "\(serviceId)-cancelled",
                "\(serviceId)-platform",
                "\(serviceId)-delay"
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
