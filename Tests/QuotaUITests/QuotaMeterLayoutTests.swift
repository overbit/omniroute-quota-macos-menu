#if os(macOS)
import AppKit
import SwiftUI
import Vision
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

    @MainActor
    func testFullWidthMetersKeepEveryWindowOnItsOwnRowInOrder() throws {
        for count in 0...6 {
            let original = windows(count)
            let meters = QuotaWindowMeters(windows: original, showUsed: false, inactive: false)
            XCTAssertEqual(meters.windows, original)
            // Empty accounts render an explicit unavailable state in AccountQuotaRows,
            // not a zero-height meter bitmap (which ImageRenderer cannot create).
            guard count > 0 else { continue }
            let image = try render(meters, width: 284)
            XCTAssertEqual(image.width, 284)
            XCTAssertEqual(image.height, count * 16)
        }
    }

    @MainActor
    func testAccountHeightMatchesBothNativeLayoutsInEveryThemeAndPercentageMode() throws {
        for mode in QuotaLayoutMode.allCases {
            for theme in QuotaTheme.allCases {
                for showUsed in [false, true] {
                    for count in 0...6 {
                        let account = QuotaAccount(id: "fixture", name: "A very long account name for truncation coverage",
                                                   provider: "claude", active: false, windows: windows(count), isStale: true)
                        let image = try render(AccountQuotaRows(account: account, server: "", showUsed: showUsed, mode: mode),
                                               width: 284, theme: theme)
                        XCTAssertEqual(image.width, 284)
                        XCTAssertEqual(image.height, Int(QuotaMeterLayout.accountHeight(windowCount: count, mode: mode)),
                                       "\(mode), \(theme.displayName), \(count) windows, showUsed=\(showUsed)")
                    }
                }
            }
        }
    }

    func testUsageFitsItsContentWhileTimelineAndSettingsKeepThe425PointCap() {
        XCTAssertEqual(PopoverLayout.chromeHeight + PopoverLayout.contentHeight, 425)
        XCTAssertEqual(PopoverLayout.headerHeight + PopoverLayout.separatorHeight + PopoverLayout.settingsHeight, 425)
        let account = QuotaAccount(id: "sparse", name: "Production", provider: "claude", active: true,
                                   windows: windows(2), isStale: false)
        let groups = QuotaProviderGroup.grouped([account])
        for mode in QuotaLayoutMode.allCases {
            let height = PopoverLayout.usageContentHeight(groups: groups, mode: mode, showsWarning: false)
            XCTAssertEqual(height, PopoverLayout.statusBandHeight + PopoverLayout.usageBottomPadding
                           + QuotaMeterLayout.accountHeight(windowCount: 2, mode: mode))
            XCTAssertLessThan(height, 130, "Sparse rows must not reserve a fixed-height empty tail")
            XCTAssertEqual(PopoverLayout.usageContentHeight(groups: groups, mode: mode, showsWarning: true), height + 21)

            let crowded = (0..<20).map { index in
                QuotaAccount(id: "many-\(index)", name: "Account \(index)", provider: "claude", active: true,
                             windows: windows(6), isStale: false)
            }
            XCTAssertEqual(PopoverLayout.usageContentHeight(groups: QuotaProviderGroup.grouped(crowded),
                                                           mode: mode, showsWarning: true), PopoverLayout.contentHeight)
            XCTAssertEqual(PopoverLayout.usageContentHeight(groups: [], mode: mode, showsWarning: false), 130)
        }
    }

    func testFiveTwoWindowAccountsFitWithinTheUsageViewportInBothLayouts() {
        for mode in QuotaLayoutMode.allCases {
            let rows = 5 * QuotaMeterLayout.accountHeight(windowCount: 2, mode: mode)
            let providerGaps = 4 * QuotaMeterLayout.providerSpacing(for: mode)
            let fixedContent = PopoverLayout.statusBandHeight + PopoverLayout.usageBottomPadding
            XCTAssertLessThanOrEqual(rows + providerGaps + fixedContent, PopoverLayout.contentHeight)
        }
    }

    @MainActor
    func testListHeightEstimateMatchesActualRowsAcrossProviderAndAccountGroups() throws {
        let groups = QuotaProviderGroup.grouped(representativeAccounts)
        for mode in QuotaLayoutMode.allCases {
            let image = try render(QuotaAccountList(groups: groups, server: "", showUsed: false, mode: mode), width: 284)
            let contentHeight = PopoverLayout.usageContentHeight(groups: groups, mode: mode, showsWarning: false)
            XCTAssertEqual(image.height, Int(contentHeight - PopoverLayout.statusBandHeight - PopoverLayout.usageBottomPadding))
        }
    }

    @MainActor
    func testSettingsBindingPersistsBothChoicesAndDefaultsSafely() throws {
        let suite = "quota-layout-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = AppStorage<QuotaLayoutMode>(wrappedValue: .defaultMode, QuotaLayoutMode.storageKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .fullWidthRows)
        let selector = QuotaLayoutSelector(selection: storage.projectedValue)
        for choice in [QuotaLayoutMode.quotaLedger, .fullWidthRows] {
            selector.selection = choice
            XCTAssertEqual(storage.wrappedValue, choice)
            XCTAssertEqual(defaults.string(forKey: QuotaLayoutMode.storageKey), choice.rawValue)
            let reloaded = AppStorage<QuotaLayoutMode>(wrappedValue: .defaultMode, QuotaLayoutMode.storageKey,
                                                       store: try XCTUnwrap(UserDefaults(suiteName: suite)))
            XCTAssertEqual(reloaded.wrappedValue, choice)
        }
        defaults.set("unsupported-layout", forKey: QuotaLayoutMode.storageKey)
        let recovered = AppStorage<QuotaLayoutMode>(wrappedValue: .defaultMode, QuotaLayoutMode.storageKey, store: defaults)
        XCTAssertEqual(recovered.wrappedValue, .fullWidthRows)
    }

    func testQuotaDescriptionsKeepUnavailableUnlimitedAndZeroDistinct() {
        let zero = QuotaWindow(id: "zero", label: "5h", remainingPercent: 0, resetAt: nil)
        XCTAssertTrue(zero.quotaAccessibilityLabel(showUsed: false).contains("0 percent remaining"))
        XCTAssertTrue(zero.quotaAccessibilityLabel(showUsed: true).contains("100 percent used"))
        XCTAssertTrue(zero.quotaAccessibilityLabel(showUsed: false).contains("reset time unavailable"))
        let unlimited = QuotaWindow(id: "infinite", label: "7d", remainingPercent: 100, resetAt: nil, unlimited: true)
        XCTAssertTrue(unlimited.quotaAccessibilityLabel(showUsed: true).contains("unlimited"))
        XCTAssertFalse(unlimited.quotaAccessibilityLabel(showUsed: true).contains("0 percent"))
    }

    /// Read the rendered pixels, not just the model, to catch missing native content.
    @MainActor
    func testBothProductionLayoutsRenderAllQuotaValuesInEveryThemeAndPercentageMode() throws {
        let groups = QuotaProviderGroup.grouped(representativeAccounts)
        for mode in QuotaLayoutMode.allCases {
            for theme in QuotaTheme.allCases {
                for showUsed in [false, true] {
                    let view = QuotaAccountList(groups: groups, server: "", showUsed: showUsed, mode: mode)
                        .padding(13)
                    let image = try render(view, width: 310, theme: theme, scale: 2)
                    try assertQuotaPercentages(in: image, showUsed: showUsed,
                                               context: "\(mode), \(theme), used=\(showUsed)")
                }
            }
        }
    }

    /// Export the actual shipping components without ImageRenderer's native ScrollView limitation.
    @MainActor
    func testRenderRepresentativeStatesForVisualReview() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_UI_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in QuotaLayoutMode.allCases {
            for theme in QuotaTheme.allCases {
                for showUsed in [false, true] {
                    let preview = QuotaAccountList(groups: QuotaProviderGroup.grouped(representativeAccounts), server: "",
                                                   showUsed: showUsed, mode: mode).padding(13)
                    let image = try render(preview, width: 310, theme: theme, scale: 2)
                    try assertQuotaPercentages(in: image, showUsed: showUsed, context: "export \(mode), \(theme)")
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let filename = "quota-\(mode.rawValue)-\(theme.displayName.lowercased())-\(showUsed ? "used" : "left").png"
                    try png.write(to: directory.appendingPathComponent(filename))
                }
            }
        }
    }

    private var representativeAccounts: [QuotaAccount] {
        [
            QuotaAccount(id: "pair", name: "Production", provider: "claude", active: true,
                         windows: [QuotaWindow(id: "session", label: "5h", remainingPercent: 76,
                                               resetAt: Date().addingTimeInterval(8_100)),
                                   QuotaWindow(id: "weekly", label: "7d", remainingPercent: 48,
                                               resetAt: Date().addingTimeInterval(352_800))], isStale: false),
            QuotaAccount(id: "single", name: "Single window", provider: "codex", active: true,
                         windows: [QuotaWindow(id: "one", label: "5h", remainingPercent: 92, resetAt: nil)], isStale: false),
            QuotaAccount(id: "overflow", name: "More windows", provider: "claude", active: true,
                         windows: windows(4), isStale: false),
            QuotaAccount(id: "disabled", name: "Long account name that needs middle truncation", provider: "github-copilot",
                         active: false, windows: windows(2), isStale: true),
            QuotaAccount(id: "unavailable", name: "No cached quota", provider: "opencode", active: false,
                         windows: [], isStale: false)
        ]
    }

    private func assertQuotaPercentages(in image: CGImage, showUsed: Bool, context: String) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let pattern = try NSRegularExpression(pattern: #"(?<![0-9])([0-9]{1,3})\s*%"#)
        let nsText = text as NSString
        let actual = pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .compactMap { Int(nsText.substring(with: $0.range(at: 1))) }.sorted()
        let expected = representativeAccounts.flatMap(\.windows).filter { !$0.unlimited }
            .map { $0.displayedRoundedPercent(showUsed: showUsed) }.sorted()
        XCTAssertEqual(actual, expected, "\(context), OCR read:\n\(text)")
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
