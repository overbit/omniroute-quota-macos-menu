import Foundation

/// Persistent names for the five popover themes. Existing installations keep
/// Graphite (the original OmniRouteTray dark appearance) by default.
public enum QuotaTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case graphite
    case midnight
    case forest
    case dusk
    case paper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .graphite: return "Graphite"
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
        case .graphite:
            return .init(background: 0x1C1C1E, raised: 0x2C2C2E, border: 0x38383A,
                         text: 0xF5F5F7, muted: 0xA1A1AA, faint: 0x9398A3,
                         good: 0x22C55E, warning: 0xF59E0B, bad: 0xFF6B6B,
                         accent: 0x88B8FF)
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
            return .init(background: 0xFAF8F3, raised: 0xEFEBE2, border: 0xD1CAC0,
                         text: 0x211F1B, muted: 0x5C5851, faint: 0x6C665E,
                         good: 0x126F3B, warning: 0x985200, bad: 0xB3261E,
                         accent: 0x365F9A)
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
