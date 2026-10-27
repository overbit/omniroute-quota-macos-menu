#if os(macOS)
import QuotaCore
import SwiftUI

/// One semantic palette drives both the usage list and the settings controls.
/// Only the popover is themed; the macOS status-bar template follows the system.
struct TrayPalette {
    let background: Color
    let raised: Color
    let border: Color
    let text: Color
    let muted: Color
    let faint: Color
    let good: Color
    let warning: Color
    let bad: Color
    let accent: Color

    init(_ tokens: QuotaThemeTokens) {
        background = Color(rgb: tokens.background)
        raised = Color(rgb: tokens.raised)
        border = Color(rgb: tokens.border)
        text = Color(rgb: tokens.text)
        muted = Color(rgb: tokens.muted)
        faint = Color(rgb: tokens.faint)
        good = Color(rgb: tokens.good)
        warning = Color(rgb: tokens.warning)
        bad = Color(rgb: tokens.bad)
        accent = Color(rgb: tokens.accent)
    }

    func quotaColor(_ remaining: Double) -> Color {
        remaining < 20 ? bad : remaining < 50 ? warning : good
    }
}

extension QuotaTheme {
    var palette: TrayPalette { TrayPalette(tokens) }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct TrayPaletteKey: EnvironmentKey {
    static let defaultValue = QuotaTheme.graphite.palette
}

extension EnvironmentValues {
    var trayPalette: TrayPalette {
        get { self[TrayPaletteKey.self] }
        set { self[TrayPaletteKey.self] = newValue }
    }
}
#endif
