import Foundation

/// Clock-time helpers shared by the board's train cards and the fastest-
/// departures tiles. Inputs are "HH:MM" strings; non-clock strings like
/// "On time" / "Delayed" return nil so callers can fall back to scheduled
/// values.
enum TimeFormat {
    static func parseClockTime(_ s: String) -> String? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil else { return nil }
        return s
    }

    static func minutesOfDay(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Returns "Xh Ym" / "Xh" / "Ym" for the wall-clock gap between two
    /// "HH:MM" times, wrapping past midnight. Returns nil if either time
    /// can't be parsed or the gap is zero.
    static func journeyDuration(from depart: String, to arrive: String) -> String? {
        guard let dm = minutesOfDay(depart),
              let am = minutesOfDay(arrive) else { return nil }
        var delta = am - dm
        if delta < 0 { delta += 24 * 60 }
        if delta == 0 { return nil }
        let hours = delta / 60
        let mins = delta % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}
