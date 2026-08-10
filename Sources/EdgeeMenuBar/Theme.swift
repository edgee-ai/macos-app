import SwiftUI

/// Palette + type helpers for the menubar panel, lifted from the Claude Design
/// "Edgee Menubar" roomier (5b) mock so the native app matches the comp.
enum Theme {
    /// Edgee brand purple (#9400D3) — matches the app icon gradient's top stop.
    static let brand = Color(hex: 0x9400D3)
    /// Deep indigo, the gradient's bottom stop.
    static let indigo = Color(hex: 0x3D2EB3)
    /// Near-black used for headings and stat numerals (#0f0715).
    static let ink = Color(hex: 0x0F0715)

    /// Panel background gradient (lilac, top → bottom).
    static let panelTop = Color(hex: 0xF4F2FB)
    static let panelBottom = Color(hex: 0xECEBF5)

    /// Card surfaces float on the panel with a hairline border.
    static let cardBorder = Color(hex: 0xE8E8F0)
    static let tileBg = Color(hex: 0xFBFAFF)
    static let divider = Color(hex: 0xF2F0F8)

    /// Text ramp.
    static let bodyText = Color(hex: 0x374151)
    static let labelMuted = Color(hex: 0xA0A0B8)
    static let secondaryText = Color(hex: 0xB0A8C0)

    /// Status green for "running / active" dots.
    static let running = Color(hex: 0x16A34A)

    /// The brand → indigo gradient used on the logo mark and primary CTA.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Serif face standing in for the mock's "Sentient" — used for the wordmark
    /// and the big tabular stat numerals.
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }
}

extension Color {
    /// 0xRRGGBB literal → Color.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
