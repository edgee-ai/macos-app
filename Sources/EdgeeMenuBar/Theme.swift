import AppKit
import SwiftUI

/// Palette + type helpers for the menubar panel, lifted from the Claude Design
/// "Edgee Menubar" mock — the roomier light (5b) and dark (5c) variants. Colors
/// are adaptive: each resolves to its light or dark value from the surrounding
/// `colorScheme`, which the panel drives from the user's appearance choice.
enum Theme {
    // Brand constants (identical across modes).
    static let brand = Color(hex: 0x9400D3)
    static let indigo = Color(hex: 0x3D2EB3)

    // Text ramp.
    static let ink = Color.adaptive(light: 0x0F0715, dark: 0xF4F1FA)
    static let bodyText = Color.adaptive(light: 0x374151, dark: 0xE6E1F0)
    static let labelMuted = Color.adaptive(light: 0xA0A0B8, dark: 0x7E7890)
    static let secondaryText = Color.adaptive(light: 0xB0A8C0, dark: 0x6F6980)

    // Surfaces.
    static let panelTop = Color.adaptive(light: 0xF4F2FB, dark: 0x221B2C)
    static let panelBottom = Color.adaptive(light: 0xECEBF5, dark: 0x171220)
    static let cardFill = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.045)
    static let cardBorder = Color.adaptive(light: 0xE8E8F0, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let tileBg = Color.adaptive(light: 0xFBFAFF, dark: 0xFFFFFF, darkAlpha: 0.04)
    static let tileBorder = Color.adaptive(light: 0xE8E8F0, dark: 0xFFFFFF, darkAlpha: 0.09)
    static let divider = Color.adaptive(light: 0xF2F0F8, dark: 0xFFFFFF, darkAlpha: 0.08)

    // Account pill.
    static let pillBg = Color.adaptive(
        light: 0xFFFFFF, lightAlpha: 0.8, dark: 0xFFFFFF, darkAlpha: 0.07)
    static let pillBorder = Color.adaptive(
        light: 0xE2E0EE, dark: 0xFFFFFF, darkAlpha: 0.11)

    // Token split accents (in = brand, out = indigo).
    static let tokenInBg = Color.adaptive(light: 0xF4F0FB, dark: 0x9400D3, darkAlpha: 0.20)
    static let tokenInTint = Color.adaptive(light: 0x9400D3, dark: 0xD8B4FE)
    static let tokenInSub = Color.adaptive(light: 0x7C3AED, dark: 0xC084FC)
    static let tokenOutBg = Color.adaptive(light: 0xF0F1FB, dark: 0x3D2EB3, darkAlpha: 0.30)
    static let tokenOutTint = Color.adaptive(light: 0x3D2EB3, dark: 0xA5B4FC)

    // Status green for "running / active" dots.
    static let running = Color.adaptive(light: 0x16A34A, dark: 0x22C55E)

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

/// The panel's appearance choice, cycled by the header button and persisted.
enum Appearance: String, CaseIterable {
    case system, light, dark

    /// nil → follow the OS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Next state in the click cycle: system → light → dark → system.
    var next: Appearance {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
}

extension Color {
    /// 0xRRGGBB literal → Color.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha)
    }

    /// A color that resolves to its light or dark value from the current
    /// appearance — so a single `Theme.x` reference tracks the panel's mode.
    static func adaptive(
        light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            let a = isDark ? darkAlpha : lightAlpha
            return NSColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: a)
        })
    }
}
