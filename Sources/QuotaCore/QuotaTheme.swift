import Foundation

/// Three custom palettes and two native macOS appearances. Legacy stored
/// choices continue to resolve without resetting other @AppStorage preferences.
public enum QuotaTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case oled = "graphite" // Existing installs migrate in place, without resetting settings.
    case macOSLight = "macos-light"
    case macOSDark = "macos-dark"
    case forest
    case paper

    public init?(rawValue: String) {
        switch rawValue {
        case "graphite": self = .oled
        case "macos-light": self = .macOSLight
        case "macos-dark", "midnight", "dusk": self = .macOSDark
        case "forest": self = .forest
        case "paper": self = .paper
        default: return nil
        }
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oled: return "OLED"
        case .macOSLight: return "macOS Light"
        case .macOSDark: return "macOS Dark"
        case .forest: return "Forest"
        case .paper: return "Paper"
        }
    }

    public var isLight: Bool { self == .macOSLight || self == .paper }

    /// Semantic colors are shared by the usage list, settings, warnings, and
    /// native controls. Native themes resolve semantic AppKit colors in the UI
    /// layer, rather than approximating the system palette with fixed hex values.
    /// The menu-bar glyph always follows macOS itself.
    public var tokens: QuotaThemeTokens? {
        switch self {
        case .oled:
            // Real black keeps background OLED pixels switched off. Use only
            // subtle elevation; stronger outlines/status hues remain legible.
            return .init(background: 0x000000, raised: 0x101014, border: 0x626270,
                         text: 0xF6F7FA, muted: 0xB5B8C2, faint: 0x989CA7,
                         good: 0x45D49C, warning: 0xFABB5D, bad: 0xFF6F7C,
                         accent: 0xA9CAFF)
        case .macOSLight, .macOSDark:
            return nil
        case .forest:
            return .init(background: 0x101D19, raised: 0x1A2E25, border: 0x2C4437,
                         text: 0xEAF6EC, muted: 0xB7D0BE, faint: 0x9BB7A7,
                         good: 0x62D69A, warning: 0xF0C46F, bad: 0xFF867A,
                         accent: 0x80DBB1)
        case .paper:
            // A crisp neutral light surface keeps the compact meters distinct
            // without the muddy beige-on-ivory cast of the earlier palette.
            return .init(background: 0xF5F7FA, raised: 0xFFFFFF, border: 0xD5DDE8,
                         text: 0x202938, muted: 0x4B5665, faint: 0x626C7A,
                         good: 0x176B45, warning: 0x875000, bad: 0xA92532,
                         accent: 0x315C96)
        }
    }
}

public struct QuotaThemeTokens: Equatable, Sendable {
    public let background: UInt32
    public let raised: UInt32
    public let border: UInt32
    public let text: UInt32
    public let muted: UInt32
    public let faint: UInt32
    public let good: UInt32
    public let warning: UInt32
    public let bad: UInt32
    public let accent: UInt32
}
