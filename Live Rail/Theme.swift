import SwiftUI
import UIKit

/// All palette colours are adaptive: the first value is light mode, the
/// second dark mode. Views use `Theme.x` unchanged and the system resolves
/// the right variant. Surfaces that must stay bright in dark mode (heroes,
/// status chips) opt out with `.environment(\.colorScheme, .light)`.
enum Theme {
    // Backgrounds
    static let cream = adaptive(0xF0EAD8, 0x0C2127)
    static let creamDeep = adaptive(0xE5DCC4, 0x081A20)
    static let card = adaptive(0xFBF8EE, 0x15343F)
    /// Search field when focused — one notch brighter than `card`.
    static let searchField = adaptive(0xFFFDF5, 0x1B3B47)

    // "Ink" doubles as text-on-background and dark fill; in dark mode it
    // flips to cream so ink-filled tags naturally become light-on-dark.
    static let ink = adaptive(0x0E2D38, 0xECE5D3)
    static let inkSoft = adaptive(0x2A4754, 0xBECBD1)
    static let inkMute = adaptive(0x6E8893, 0x8AA1AB)

    /// Sky-blue teal, a shade darker than the original for better contrast.
    /// Operator chips render in a single neutral (see OperatorBrand), so the
    /// accent never competes with brand colours despite being blue.
    /// Darker teal in dark mode so cream text stays legible on accent chips.
    static let accent = adaptive(0x5CA3B9, 0x316D7E)

    // Chip colours used only inside always-light contexts (StatusPill).
    static let onTimeBg = Color(hex: 0xC9E265)
    static let warn = Color(hex: 0xF7D06B)
    static let bad = adaptive(0xE8C1B8, 0x5E3129)

    static let line = adaptive(0x0E2D38, 0xECE5D3, lightAlpha: 0.12, darkAlpha: 0.14)
    static let lineStrong = adaptive(0x0E2D38, 0xECE5D3, lightAlpha: 0.22, darkAlpha: 0.26)

    static let delayedText = adaptive(0xB56A00, 0xE5A54E)
    static let cancelledText = adaptive(0xA32718, 0xE07862)
    static let perfGood = adaptive(0x2A5A1E, 0x8CC57A)
    static let perfBad = adaptive(0xA32718, 0xE07862)
    static let onTimeSub = adaptive(0x4A7A3A, 0x90BD80)

    // Already dark pills with fixed light foregrounds — work on both schemes.
    static let trackPillDelayedBg = Color(hex: 0x3B2A05)
    static let trackPillDelayedFg = Color(hex: 0xF7D06B)
    static let trackPillCancelledBg = Color(hex: 0xA32718)
    static let trackPillCancelledFg = Color(hex: 0xFBEEEB)

    private static func adaptive(
        _ light: UInt, _ dark: UInt,
        lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
    ) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
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

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension Font {
    /// Scales a design size with the user's Dynamic Type setting, capped at
    /// +35% so the fixed-size layout (tags, ribbons, tiles) degrades
    /// gracefully instead of breaking at accessibility sizes.
    private static func scaled(_ size: CGFloat) -> CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.35)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: .default)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: scaled(size), weight: weight, design: .monospaced)
    }
}
