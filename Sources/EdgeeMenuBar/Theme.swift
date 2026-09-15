import AppKit
import CoreText
import SwiftUI

/// Palette from console globals.css and chart-colors.constants.ts.
enum Theme {
    static let accent = Color.adaptive(light: 0x820ACD, dark: 0xBB26CF)
    static let input = Color(hex: 0x0EA5E9)
    static let cached = Color(hex: 0xFB923C)
    static let cacheWrite = cached
    static let output = Color(hex: 0x2DD4BF)
    static let reasoning = Color(hex: 0xFB7185)

    static let brand = Color(hex: 0x9400D3)
    static let indigo = Color(hex: 0x3D2EB3)

    static let ink = Color.adaptive(light: 0x1C1924, dark: 0xF0F2F5)
    static let bodyText = ink
    static let labelMuted = Color.adaptive(light: 0x9C9AAC, dark: 0x7E7382)
    static let secondaryText = labelMuted

    static let panelTop = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1924)
    static let panelBottom = panelTop
    static let cardFill = panelTop
    static let cardBorder = Color.adaptive(light: 0xE0DFE7, dark: 0x3F3243)
    static let tileBg = cardBorder
    static let tileBorder = cardBorder
    static let divider = cardBorder
    static let pillBg = tileBg
    static let pillBorder = cardBorder

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

    private static let fontName: String = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts/Supreme-Variable.ttf")
        let url = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "Supreme-Variable", withExtension: "ttf", subdirectory: "Fonts")
        guard let url else { return "Supreme-Regular" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first.flatMap {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
        } ?? "Supreme-Regular"
    }()

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(fontName, fixedSize: size).weight(weight)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(size: size, weight: weight).monospacedDigit()
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
