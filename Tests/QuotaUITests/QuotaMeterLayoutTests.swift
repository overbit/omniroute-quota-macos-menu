#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import OmniRouteQuota
@testable import QuotaCore

final class QuotaMeterLayoutTests: XCTestCase {
    private func windows(_ count: Int) -> [QuotaWindow] {
        (0..<count).map { index in
            QuotaWindow(id: "window-\(index)", label: ["5h", "7d", "mo", "day", "extra", "last"][index],
                        remainingPercent: [0, 100, 42, 19, 75, 63][index],
                        resetAt: index == 2 ? nil : Date().addingTimeInterval(Double(index + 1) * 7_200),
                        unlimited: index == 1)
        }
    }

    func testFirstTwoWindowsArePairedWithoutDroppingOrReorderingAdditionalWindows() {
        for count in 0...6 {
            let original = windows(count)
            let meters = QuotaWindowMeters(windows: original, showUsed: false, inactive: false)
            XCTAssertEqual(meters.primaryWindows.count, min(2, count))
            XCTAssertEqual(meters.additionalWindows.count, max(0, count - 2))
            XCTAssertEqual(Array(meters.primaryWindows) + Array(meters.additionalWindows), original)
        }
    }

    @MainActor
    func testSingleWindowsStayCompactAndPairedWindowsAddFullWidthOverflowRows() throws {
        for count in 1...6 {
            let meters = QuotaWindowMeters(windows: windows(count), showUsed: false, inactive: false)
            let image = try render(meters, width: 262)
            XCTAssertEqual(image.width, 262)
            XCTAssertEqual(image.height, count == 1 ? 15 : 29 + max(0, count - 2) * 18)
        }
    }

    @MainActor
    func testAccountHeightEstimateMatchesNativeRenderingInEveryThemeAndPercentageMode() throws {
        for theme in QuotaTheme.allCases {
            for showUsed in [false, true] {
                for count in 0...6 {
                    let account = QuotaAccount(id: "fixture", name: "A very long account name for truncation coverage",
                                               provider: "claude", active: false, windows: windows(count), isStale: true)
                    let image = try render(AccountQuotaRows(account: account, server: "", showUsed: showUsed),
                                           width: 284, theme: theme)
                    XCTAssertEqual(image.width, 284, "\(theme.displayName), \(count) windows")
                    XCTAssertEqual(image.height, Int(QuotaMeterLayout.accountHeight(windowCount: count)),
                                   "\(theme.displayName), \(count) windows, showUsed=\(showUsed)")
                }
            }
        }
    }

    func testPopoverKeepsTheSameHeightWhileSwitchingBetweenUsageAndSettings() {
        let usageHeight = PopoverLayout.headerHeight
            + 2 * PopoverLayout.separatorHeight
            + PopoverLayout.pickerHeight
            + PopoverLayout.contentHeight
            + PopoverLayout.footerHeight
        let settingsHeight = PopoverLayout.headerHeight
            + PopoverLayout.separatorHeight
            + PopoverLayout.settingsHeight

        XCTAssertEqual(usageHeight, PopoverLayout.maximumHeight)
        XCTAssertEqual(settingsHeight, PopoverLayout.maximumHeight)
    }

    func testFiveTwoWindowAccountsFitWithinTheExistingUsageViewport() {
        let accountRows = 5 * QuotaMeterLayout.accountHeight(windowCount: 2)
        let worstCaseProviderGaps: CGFloat = 4 * 8
        let fixedContent = PopoverLayout.statusBandHeight + PopoverLayout.usageBottomPadding
        XCTAssertLessThanOrEqual(accountRows + worstCaseProviderGaps + fixedContent, PopoverLayout.contentHeight)
    }

    /// Optional native snapshots cover the actual account component, not an HTML facsimile.
    /// Enable with QUOTA_UI_SNAPSHOT_DIR=/path/to/output swift test --filter QuotaMeterLayoutTests.
    @MainActor
    func testRenderRepresentativeStatesForVisualReview() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_UI_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accounts = [
            QuotaAccount(id: "pair", name: "Production", provider: "claude", active: true,
                         windows: [QuotaWindow(id: "session", label: "5h", remainingPercent: 76,
                                               resetAt: Date().addingTimeInterval(8_100)),
                                   QuotaWindow(id: "weekly", label: "7d", remainingPercent: 48,
                                               resetAt: Date().addingTimeInterval(352_800))], isStale: false),
            QuotaAccount(id: "single", name: "Single window, full-width meter", provider: "codex", active: true,
                         windows: [QuotaWindow(id: "one", label: "5h", remainingPercent: 92, resetAt: nil)], isStale: false),
            QuotaAccount(id: "overflow", name: "Extra windows stay visible", provider: "kimi", active: true,
                         windows: windows(4), isStale: false),
            QuotaAccount(id: "disabled", name: "Long account name that needs middle truncation", provider: "github-copilot",
                         active: false, windows: windows(2), isStale: true),
            QuotaAccount(id: "unavailable", name: "No cached quota", provider: "opencode", active: false,
                         windows: [], isStale: false)
        ]
        for theme in QuotaTheme.allCases {
            for showUsed in [false, true] {
                let preview = VStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts) { account in
                        AccountQuotaRows(account: account, server: "", showUsed: showUsed)
                    }
                }
                .padding(13)
                let image = try render(preview, width: 310, theme: theme, scale: 2)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let filename = "quota-meters-\(theme.displayName.lowercased())-\(showUsed ? "used" : "left").png"
                try png.write(to: directory.appendingPathComponent(filename))
            }
        }
    }

    @MainActor
    private func render<Content: View>(_ content: Content, width: CGFloat, theme: QuotaTheme = .oled,
                                       scale: CGFloat = 1) throws -> CGImage {
        let renderer = ImageRenderer(content: content
            .frame(width: width)
            .background(theme.palette.background)
            .environment(\.trayPalette, theme.palette)
            .preferredColorScheme(theme.isLight ? .light : .dark))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage, "SwiftUI could not render the native quota view")
    }
}
#endif
