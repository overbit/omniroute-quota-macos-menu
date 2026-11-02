#if os(macOS)
import AppKit
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

    /// Resolve in the chosen appearance, not the host window's appearance, so
    /// Light/Dark stay explicit and both miniature previews are accurate.
    init(systemAppearance name: NSAppearance.Name) {
        let appearance = NSAppearance(named: name) ?? NSAppearance.currentDrawing()
        func resolve(_ source: NSColor) -> NSColor {
            var resolved = source
            appearance.performAsCurrentDrawingAppearance {
                resolved = source.usingColorSpace(.sRGB) ?? source
            }
            return resolved
        }
        let canvas = resolve(.windowBackgroundColor)
        let control = resolve(.controlBackgroundColor)
        let label = resolve(.labelColor)
        func readable(_ source: NSColor) -> Color {
            Color(nsColor: resolve(source).readable(on: [canvas, control], toward: label))
        }
        background = Color(nsColor: canvas)
        raised = Color(nsColor: control)
        border = Color(nsColor: resolve(.separatorColor))
        text = Color(nsColor: label)
        muted = readable(.secondaryLabelColor)
        faint = readable(.tertiaryLabelColor)
        good = readable(.systemGreen)
        warning = readable(.systemOrange)
        bad = readable(.systemRed)
        accent = Color(nsColor: resolve(.controlAccentColor))
    }

    func quotaColor(_ remaining: Double) -> Color {
        remaining < 20 ? bad : remaining < 50 ? warning : good
    }
}

extension QuotaTheme {
    var palette: TrayPalette {
        if let tokens { return TrayPalette(tokens) }
        return TrayPalette(systemAppearance: isLight ? .aqua : .darkAqua)
    }
}

private extension NSColor {
    /// System status hues and translucent secondary labels are also used as
    /// small text here. Blend only as needed to meet 4.5:1 on both native surfaces.
    func readable(on surfaces: [NSColor], toward label: NSColor) -> NSColor {
        for step in 0...20 {
            let candidate = blended(withFraction: CGFloat(step) / 20, of: label) ?? label
            if surfaces.allSatisfy({ candidate.contrast(on: $0) >= 4.5 }) { return candidate }
        }
        return label
    }

    func contrast(on surface: NSColor) -> CGFloat {
        let foreground = luminance(over: surface)
        let background = surface.luminance(over: surface)
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }

    func luminance(over surface: NSColor) -> CGFloat {
        let color = usingColorSpace(.sRGB) ?? self
        func linear(_ value: CGFloat, over background: CGFloat) -> CGFloat {
            let component = value * color.alphaComponent + background * (1 - color.alphaComponent)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent, over: surface.redComponent)
            + 0.7152 * linear(color.greenComponent, over: surface.greenComponent)
            + 0.0722 * linear(color.blueComponent, over: surface.blueComponent)
    }
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
    static let defaultValue = QuotaTheme.oled.palette
}

extension EnvironmentValues {
    var trayPalette: TrayPalette {
        get { self[TrayPaletteKey.self] }
        set { self[TrayPaletteKey.self] = newValue }
    }
}
#endif
