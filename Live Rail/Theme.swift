import SwiftUI

enum Theme {
    static let cream = Color(hex: 0xF0EAD8)
    static let creamDeep = Color(hex: 0xE5DCC4)
    static let card = Color(hex: 0xFBF8EE)
    static let ink = Color(hex: 0x0E2D38)
    static let inkSoft = Color(hex: 0x2A4754)
    static let inkMute = Color(hex: 0x6E8893)
    static let accent = Color(hex: 0x6FB8CC)
    static let onTimeBg = Color(hex: 0xC9E265)
    static let warn = Color(hex: 0xF7D06B)
    static let bad = Color(hex: 0xE8C1B8)
    static let line = Color(hex: 0x0E2D38).opacity(0.12)
    static let lineStrong = Color(hex: 0x0E2D38).opacity(0.22)

    static let delayedText = Color(hex: 0xB56A00)
    static let cancelledText = Color(hex: 0xA32718)
    static let perfGood = Color(hex: 0x2A5A1E)
    static let perfBad = Color(hex: 0xA32718)
    static let onTimeSub = Color(hex: 0x4A7A3A)

    static let trackPillDelayedBg = Color(hex: 0x3B2A05)
    static let trackPillDelayedFg = Color(hex: 0xF7D06B)
    static let trackPillCancelledBg = Color(hex: 0xA32718)
    static let trackPillCancelledFg = Color(hex: 0xFBEEEB)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
