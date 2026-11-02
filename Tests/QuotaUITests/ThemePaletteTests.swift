#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import OmniRouteQuota
@testable import QuotaCore

final class ThemePaletteTests: XCTestCase {
    @MainActor
    func testNativeThemesResolveSystemRolesInTheirOwnAppearance() throws {
        for theme in [QuotaTheme.macOSLight, .macOSDark] {
            let chosen = try XCTUnwrap(NSAppearance(named: theme.isLight ? .aqua : .darkAqua))
            let opposite = try XCTUnwrap(NSAppearance(named: theme.isLight ? .darkAqua : .aqua))
            var palette = theme.palette
            opposite.performAsCurrentDrawingAppearance { palette = theme.palette }
            let roles: [(Color, NSColor)] = [
                (palette.background, .windowBackgroundColor),
                (palette.raised, .controlBackgroundColor),
                (palette.text, .labelColor),
                (palette.border, .separatorColor),
                (palette.accent, .controlAccentColor)
            ]
            for (actual, source) in roles {
                var expected = source
                chosen.performAsCurrentDrawingAppearance {
                    expected = source.usingColorSpace(.sRGB) ?? source
                }
                let converted = try rgb(actual)
                let actualComponents = [converted.redComponent, converted.greenComponent,
                                        converted.blueComponent, converted.alphaComponent]
                let expectedComponents = [expected.redComponent, expected.greenComponent,
                                          expected.blueComponent, expected.alphaComponent]
                for (left, right) in zip(actualComponents, expectedComponents) {
                    XCTAssertEqual(left, right, accuracy: 0.001, "\(theme.displayName): wrong native color")
                }
            }
        }
        let light = try rgb(QuotaTheme.macOSLight.palette.background)
        let dark = try rgb(QuotaTheme.macOSDark.palette.background)
        XCTAssertGreaterThan(light.redComponent, dark.redComponent)
        XCTAssertNotEqual(light, try rgb(QuotaTheme.paper.palette.background))
        XCTAssertNotEqual(dark, try rgb(QuotaTheme.oled.palette.background))
    }

    @MainActor
    func testNativeSmallTextAndQuotaColorsKeepReadableContrast() throws {
        for theme in [QuotaTheme.macOSLight, .macOSDark] {
            let palette = theme.palette
            for surface in [palette.background, palette.raised] {
                let background = try rgb(surface)
                for color in [palette.text, palette.muted, palette.faint, palette.good, palette.warning, palette.bad] {
                    let foreground = try rgb(color)
                    let fg = luminance(foreground, over: background)
                    let bg = luminance(background, over: background)
                    XCTAssertGreaterThanOrEqual((max(fg, bg) + 0.05) / (min(fg, bg) + 0.05), 4.5,
                                                "\(theme.displayName): unreadable small text")
                }
            }
        }
    }

    @MainActor
    func testThemeSelectorPersistsNewChoicesAndRestoresRemovedDarkThemes() throws {
        let suite = "quota-theme-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = AppStorage<QuotaTheme>(wrappedValue: .oled, "quotaTheme", store: defaults)
        XCTAssertEqual(initial.wrappedValue, .oled)
        for legacy in ["midnight", "dusk"] {
            defaults.set(legacy, forKey: "quotaTheme")
            let migrated = AppStorage<QuotaTheme>(wrappedValue: .oled, "quotaTheme", store: defaults)
            XCTAssertEqual(migrated.wrappedValue, .macOSDark)
        }
        let selector = ThemeSelector(selection: initial.projectedValue)
        for theme in QuotaTheme.allCases {
            selector.selection = theme
            XCTAssertEqual(defaults.string(forKey: "quotaTheme"), theme.rawValue)
            let reloaded = AppStorage<QuotaTheme>(wrappedValue: .oled, "quotaTheme", store: defaults)
            XCTAssertEqual(reloaded.wrappedValue, theme)
        }
        defaults.set("unknown", forKey: "quotaTheme")
        XCTAssertEqual(AppStorage<QuotaTheme>(wrappedValue: .oled, "quotaTheme", store: defaults).wrappedValue, .oled)
    }

    /// Render the production selector directly, outside ImageRenderer's native ScrollView limitation.
    @MainActor
    func testNativeThemeSelectorRendersEveryNameWithoutClipping() throws {
        for theme in [QuotaTheme.macOSLight, .macOSDark] {
            let view = ThemeSelector(selection: .constant(theme))
                .padding(16)
                .frame(width: 310)
                .background(theme.palette.background)
                .environment(\.trayPalette, theme.palette)
                .preferredColorScheme(theme.isLight ? .light : .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 620)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").lowercased()
            for name in ["oled", "macos", "light", "dark", "forest", "paper"] {
                XCTAssertTrue(text.contains(name), "Missing \(name) in \(theme.displayName) selector: \(text)")
            }
            XCTAssertFalse(text.contains("midnight"))
            XCTAssertFalse(text.contains("dusk"))
            if let path = ProcessInfo.processInfo.environment["QUOTA_UI_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("theme-selector-\(theme.rawValue).png"))
            }
        }
    }

    private func rgb(_ color: Color) throws -> NSColor {
        try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
    }

    private func luminance(_ color: NSColor, over background: NSColor) -> CGFloat {
        func linear(_ value: CGFloat, over surface: CGFloat) -> CGFloat {
            let channel = value * color.alphaComponent + surface * (1 - color.alphaComponent)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent, over: background.redComponent)
            + 0.7152 * linear(color.greenComponent, over: background.greenComponent)
            + 0.0722 * linear(color.blueComponent, over: background.blueComponent)
    }
}
#endif
