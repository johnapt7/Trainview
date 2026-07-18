import SwiftUI
import UIKit

struct OperatorBrand {
    let bg: Color
    let fg: Color

    /// Brand colour used as text (e.g. the operator name next to the code
    /// chip). Most brand colours are dark and vanish on dark cards, so in
    /// dark mode this falls back to the standard light text colour.
    var label: Color {
        let brand = UIColor(bg)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: 0xECE5D3) : brand
        })
    }

    /// Every operator renders in the same neutral ink-on-cream chip. The
    /// two-letter code carries the identity; a single consistent neutral
    /// keeps the palette calm and can never clash with the app accent.
    static func brand(for _: String) -> OperatorBrand {
        OperatorBrand(bg: Theme.ink, fg: Theme.cream)
    }
}
