import SwiftUI

struct OperatorBrand {
    let bg: Color
    let fg: Color

    static func brand(for code: String) -> OperatorBrand {
        switch code {
        case "GR": return OperatorBrand(bg: Color(hex: 0xBF0D2B), fg: .white)
        case "XC": return OperatorBrand(bg: Color(hex: 0x6B0036), fg: .white)
        case "GW": return OperatorBrand(bg: Color(hex: 0x0A493E), fg: .white)
        case "VT": return OperatorBrand(bg: Color(hex: 0x004332), fg: .white)
        case "TP": return OperatorBrand(bg: Color(hex: 0x0F1D41), fg: .white)
        case "EM": return OperatorBrand(bg: Color(hex: 0x6B2C91), fg: .white)
        case "NT": return OperatorBrand(bg: Color(hex: 0x262262), fg: .white)
        case "SR": return OperatorBrand(bg: Color(hex: 0x1C4184), fg: .white)
        case "SW": return OperatorBrand(bg: Color(hex: 0x24135F), fg: .white)
        case "SE": return OperatorBrand(bg: Color(hex: 0x007DA6), fg: .white)
        case "SN": return OperatorBrand(bg: Color(hex: 0x5B8C2A), fg: .white)
        case "TL": return OperatorBrand(bg: Color(hex: 0xCC0070), fg: .white)
        case "GN": return OperatorBrand(bg: Color(hex: 0x6B2C91), fg: .white)
        case "LE": return OperatorBrand(bg: Color(hex: 0xD10428), fg: .white)
        case "CC": return OperatorBrand(bg: Color(hex: 0x652D90), fg: .white)
        case "CH": return OperatorBrand(bg: Color(hex: 0x0072BC), fg: .white)
        case "ME": return OperatorBrand(bg: Color(hex: 0xDDB400), fg: Color(hex: 0x1A1A1A))
        case "LO": return OperatorBrand(bg: Color(hex: 0xE07C10), fg: .white)
        case "HT": return OperatorBrand(bg: Color(hex: 0xDE1279), fg: .white)
        case "GC": return OperatorBrand(bg: Color(hex: 0x1D1D1B), fg: .white)
        case "LS": return OperatorBrand(bg: Color(hex: 0x0E54A8), fg: .white)
        case "HX": return OperatorBrand(bg: Color(hex: 0x532D8E), fg: .white)
        case "GX": return OperatorBrand(bg: Color(hex: 0xC30000), fg: .white)
        case "AW": return OperatorBrand(bg: Color(hex: 0xC4002F), fg: .white)
        case "CS": return OperatorBrand(bg: Color(hex: 0x1D6753), fg: .white)
        case "XR": return OperatorBrand(bg: Color(hex: 0x6950A1), fg: .white)
        case "LM": return OperatorBrand(bg: Color(hex: 0x3E1F68), fg: .white)
        case "IL": return OperatorBrand(bg: Color(hex: 0x009FE3), fg: .white)
        case "ES": return OperatorBrand(bg: Color(hex: 0x003399), fg: .white)
        default:   return OperatorBrand(bg: Theme.ink, fg: Theme.cream)
        }
    }
}
