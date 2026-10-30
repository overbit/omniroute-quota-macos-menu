import Foundation

/// Five UI themes. OLED replaces the old Graphite palette. Its stored raw
/// value stays "graphite" to preserve existing @AppStorage preferences.
public enum QuotaTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case oled = "graphite" // Existing installs migrate in place, without resetting settings.
    case midnight
    case forest
    case dusk
    case paper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oled: return "OLED"
        case .midnight: return "Midnight"
        case .forest: return "Forest"
        case .dusk: return "Dusk"
        case .paper: return "Paper"
        }
    }

    public var isLight: Bool { self == .paper }

    /// Semantic colors are shared by the usage list, settings, warnings, and
    /// native controls. The menu-bar glyph always follows macOS itself.
    public var tokens: QuotaThemeTokens {
        switch self {
        case .oled:
            // Real black keeps background OLED pixels switched off. Use only
            // subtle elevation; stronger outlines/status hues remain legible.
            return .init(background: 0x000000, raised: 0x101014, border: 0x626270,
                         text: 0xF6F7FA, muted: 0xB5B8C2, faint: 0x989CA7,
                         good: 0x45D49C, warning: 0xFABB5D, bad: 0xFF6F7C,
                         accent: 0xA9CAFF)
        case .midnight:
            return .init(background: 0x0E1726, raised: 0x17273B, border: 0x28384D,
                         text: 0xEAF3FF, muted: 0xB4C5D9, faint: 0x9AAEC7,
                         good: 0x45D49C, warning: 0xFFBD63, bad: 0xFF707A,
                         accent: 0x82B7FF)
        case .forest:
            return .init(background: 0x101D19, raised: 0x1A2E25, border: 0x2C4437,
                         text: 0xEAF6EC, muted: 0xB7D0BE, faint: 0x9BB7A7,
                         good: 0x62D69A, warning: 0xF0C46F, bad: 0xFF867A,
                         accent: 0x80DBB1)
        case .dusk:
            return .init(background: 0x1B1424, raised: 0x30243B, border: 0x4A3654,
                         text: 0xF6EEFA, muted: 0xD0BFD8, faint: 0xB9A5C5,
                         good: 0x69DBA7, warning: 0xF4C178, bad: 0xFF7C92,
                         accent: 0xC4A1FF)
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
