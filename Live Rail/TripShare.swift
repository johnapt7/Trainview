import Foundation

/// Composes the plain-text trip summary behind the journey screen's share
/// button. Pure string logic, kept off the view so the copy variants are
/// checkable in isolation.
enum TripShareText {
    static func compose(
        originName: String,
        platform: String?,
        destName: String,
        departTime: String,
        arrivalTime: String?,
        status: TrainStatus,
        delayMinutes: Int?,
        operatorName: String
    ) -> String {
        let route = "\(departTime) \(operatorName) train from \(originName)\(platformSuffix(platform)) to \(destName)"

        switch status {
        case .cancelled:
            return "My \(departTime) train from \(originName) to \(destName) has been cancelled. Sent from Live Rail."
        case .delayed:
            if let arrivalTime {
                let lateness = delayMinutes.flatMap { $0 > 0 ? "running \($0) min late" : nil } ?? "running late"
                return "I'm on the \(route) — arriving \(arrivalTime), \(lateness). Sent from Live Rail."
            }
            return "I'm on the \(route) — currently delayed, no arrival estimate yet. Sent from Live Rail."
        case .onTime:
            if let arrivalTime {
                return "I'm on the \(route) — arriving \(arrivalTime), on time. Sent from Live Rail."
            }
            return "I'm on the \(route). Sent from Live Rail."
        }
    }

    /// Best-known clock time at a stop: actual, else live expected, else
    /// scheduled — the `Stop` twin of `TransferPlanner.bestTime`. Darwin's
    /// "On time"/"Delayed" strings parse to nil and fall through.
    static func bestTime(for stop: Stop) -> String? {
        if let actual = stop.actualTime, TimeFormat.parseClockTime(actual) != nil { return actual }
        if let expected = stop.expectedTime, let live = TimeFormat.parseClockTime(expected) { return live }
        return TimeFormat.parseClockTime(stop.time)
    }

    private static func platformSuffix(_ platform: String?) -> String {
        guard let platform, !platform.isEmpty, platform != "—" else { return "" }
        return " (platform \(platform))"
    }
}
