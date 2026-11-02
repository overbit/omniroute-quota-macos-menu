#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import Vision
import ImageIO
@testable import OmniRouteQuota
@testable import QuotaCore

/// Design-only alternatives. Nothing in the shipping popover selects these views.
/// QUOTA_ROW_PREVIEW_DIR=/path swift test --filter QuotaRowAlternativesTests
final class QuotaRowAlternativesTests: XCTestCase {
    @MainActor
    func testAlternativesKeepEveryWindowAndFitTheirContent() throws {
        for style in RowConcept.allCases {
            for theme in QuotaTheme.allCases {
                for showUsed in [false, true] {
                    for accounts in [RowFixtures.standard, RowFixtures.sparse, RowFixtures.extremes] {
                        let view = RowConceptPopover(style: style, accounts: accounts, warning: nil,
                                                     showUsed: showUsed)
                        let image = try render(view, theme: theme)
                        XCTAssertEqual(image.width, 620)
                        XCTAssertEqual(image.height, Int(view.height * 2))
                        XCTAssertLessThanOrEqual(view.height, PopoverLayout.maximumHeight)
                        XCTAssertEqual(style.rows(accounts).map(\.window), accounts.flatMap(\.windows))
                    }
                }
            }
        }
    }

    /// Dimensions alone cannot detect a native scroll view missing from the bitmap.
    @MainActor
    func testRenderedPixelsContainEveryQuotaPercentage() throws {
        for style in RowConcept.allCases {
            for theme in [QuotaTheme.oled, .paper] {
                for showUsed in [false, true] {
                    let view = RowConceptPopover(style: style, accounts: RowFixtures.standard,
                                                 warning: nil, showUsed: showUsed)
                    try assertQuotaPercentages(in: render(view, theme: theme), showUsed: showUsed,
                                               context: "\(style.rawValue), \(theme.displayName), used=\(showUsed)")
                }
            }
        }
    }

    @MainActor
    func testSparsePopoversDoNotReserveTheMaximumHeight() throws {
        for style in RowConcept.allCases {
            let sparse = RowConceptPopover(style: style, accounts: RowFixtures.sparse, warning: nil,
                                           showUsed: false)
            XCTAssertLessThan(sparse.height, 210)
            XCTAssertEqual(try render(sparse).height, Int(sparse.height * 2))
            let crowded = RowConceptPopover(style: style, accounts: RowFixtures.crowded,
                                            warning: "Showing last known quotas", showUsed: false)
            XCTAssertEqual(crowded.height, 425)
            XCTAssertEqual(try render(crowded).height, 850)
        }
    }

    @MainActor
    func testExportNativeConceptsWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_ROW_PREVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var measurements: [String: CGFloat] = [:]
        for style in RowConcept.allCases {
            let view = RowConceptPopover(style: style, accounts: RowFixtures.standard, warning: nil,
                                         showUsed: false)
            measurements[style.rawValue] = view.height
            for theme in [QuotaTheme.oled, .paper] {
                try save(render(view, theme: theme), to: directory.appendingPathComponent("\(style.rawValue)-\(theme.displayName.lowercased()).png"))
            }
        }
        for theme in [QuotaTheme.oled, .paper] {
            let url = directory.appendingPathComponent("comparison-\(theme.displayName.lowercased()).png")
            try save(render(RowComparisonBoard(theme: theme), width: 1034, theme: theme), to: url)
            // Verify the exported PNG, not just source data or the frame dimensions.
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            try assertQuotaPercentages(in: image, showUsed: false, copies: 3, context: url.lastPathComponent)
        }
        try save(render(RowStateBoard(), width: 1034),
                 to: directory.appendingPathComponent("sparse-and-edge-states.png"))
        let json = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appendingPathComponent("heights-in-points.json"))
        print("Native quota concepts exported to \(directory.path): \(measurements)")
    }

    @MainActor
    private func render<Content: View>(_ view: Content, width: CGFloat = 310,
                                       theme: QuotaTheme = .oled) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width)
            .environment(\.trayPalette, theme.palette)
            .preferredColorScheme(theme.isLight ? .light : .dark))
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func assertQuotaPercentages(in image: CGImage, showUsed: Bool,
                                         copies: Int = 1, context: String) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let pattern = try NSRegularExpression(pattern: #"(?<![0-9])([0-9]{1,3})\s*%"#)
        let nsText = text as NSString
        let actual = pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .compactMap { Int(nsText.substring(with: $0.range(at: 1))) }.sorted()
        let expected = Array(repeating: RowFixtures.standard.flatMap(\.windows).map {
            $0.displayedRoundedPercent(showUsed: showUsed)
        }, count: copies).flatMap { $0 }.sorted()
        XCTAssertEqual(actual, expected, "Missing quota pixels in \(context). OCR read:\n\(text)")
    }

    private func save(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

private enum RowConcept: String, CaseIterable {
    case meters = "full-width-rows"
    case inline = "inline-accounts"
    case ledger = "quota-ledger"

    var title: String {
        switch self {
        case .meters: return "A · Full-width rows"
        case .inline: return "B · Inline accounts"
        case .ledger: return "C · Quota ledger"
        }
    }
    var description: String {
        switch self {
        case .meters: return "Account heading, then one long meter per quota."
        case .inline: return "Identity and the first quota share a line."
        case .ledger: return "Every row is self-contained. Numbers, no bars."
        }
    }
    var tradeoff: String {
        switch self {
        case .meters: return "Clearest meters · more vertical space"
        case .inline: return "Best density with meters · shorter labels"
        case .ledger: return "No empty identity cells · less visual comparison"
        }
    }
    var rowHeight: CGFloat { self == .meters ? 16 : 22 }
    var accountGap: CGFloat { self == .meters ? 5 : (self == .inline ? 6 : 0) }

    func rows(_ accounts: [QuotaAccount]) -> [(account: QuotaAccount, window: QuotaWindow)] {
        accounts.flatMap { account in account.windows.map { (account, $0) } }
    }
    func listHeight(_ accounts: [QuotaAccount]) -> CGFloat {
        accounts.reduce(CGFloat(0)) { result, account in
            result + (self == .meters ? 18 : 0)
                + CGFloat(max(1, account.windows.count)) * rowHeight
        } + CGFloat(max(0, accounts.count - 1)) * accountGap + 8
    }
}

private enum RowFixtures {
    static let now = Date(timeIntervalSince1970: 1_793_617_200)
    static func window(_ label: String, _ value: Double, _ minutes: Double?, unlimited: Bool = false) -> QuotaWindow {
        QuotaWindow(id: label, label: label, remainingPercent: value,
                    resetAt: minutes.map { now.addingTimeInterval($0 * 60) }, unlimited: unlimited)
    }
    static let standard = [
        QuotaAccount(id: "claude-personal", name: "Claude Personal", provider: "claude", active: true,
                     windows: [window("5h", 76, 135), window("7d", 48, 5_880)], isStale: false),
        QuotaAccount(id: "claude-work", name: "Claude Work", provider: "claude", active: true,
                     windows: [window("5h", 92, 108), window("7d", 62, 7_620)], isStale: false),
        QuotaAccount(id: "codex", name: "Codex", provider: "codex", active: true,
                     windows: [window("5h", 14, 372), window("7d", 71, 4_860)], isStale: false),
        QuotaAccount(id: "kimi", name: "Kimi Coding", provider: "kimi", active: true,
                     windows: [window("5h", 53, 201), window("7d", 24, 2_940), window("mo", 81, 17_520)], isStale: false),
        QuotaAccount(id: "copilot", name: "Copilot", provider: "github-copilot", active: true,
                     windows: [window("mo", 87, 26_280)], isStale: false)
    ]
    static let sparse = [standard[0]]
    static let extremes = [
        QuotaAccount(id: "long", name: "Production account with a very long name", provider: "claude", active: true,
                     windows: [window("Long window label", 0, 0), window("7d", 100, nil, unlimited: true),
                               window("mo", 100, 43_199)], isStale: true),
        QuotaAccount(id: "disabled", name: "Claude Work", provider: "claude", active: false,
                     windows: [window("5h", 19, 138), window("7d", 42, nil)], isStale: true),
        QuotaAccount(id: "unavailable", name: "OpenCode", provider: "opencode", active: false,
                     windows: [], isStale: false)
    ]
    static let crowded = standard + extremes + standard
}

private struct RowConceptPopover: View {
    @Environment(\.trayPalette) private var palette
    let style: RowConcept
    let accounts: [QuotaAccount]
    let warning: String?
    let showUsed: Bool
    private let chromeHeight: CGFloat = 138
    var height: CGFloat { min(425, chromeHeight + style.listHeight(accounts) + (warning == nil ? 0 : 24)) }
    private var providerCount: Int { Set(accounts.map(\.provider)).count }
    private var activeProviderCount: Int { Set(accounts.filter(\.active).map(\.provider)).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(palette.good).frame(width: 9, height: 9)
                Text("OmniRoute").font(.system(size: 15, weight: .bold))
                Text("Running").font(.system(size: 11)).foregroundStyle(palette.muted)
                Spacer(minLength: 0)
            }.padding(.horizontal, 13).frame(height: 38)
            line
            HStack(spacing: 0) {
                Text("Usage").fontWeight(.semibold).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.border.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                Text("Timeline").foregroundStyle(palette.muted).frame(maxWidth: .infinity)
            }
            .font(.system(size: 11)).padding(2).frame(height: 22)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 13).frame(height: 36)
            HStack {
                Text("\(activeProviderCount)/\(providerCount) providers · \(accounts.count) accounts")
                Spacer(minLength: 4)
                Text(showUsed ? "% used" : "% left").fontWeight(.medium)
                    .frame(width: 58, height: 22)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.system(size: 10.5)).foregroundStyle(palette.muted)
            .padding(.horizontal, 13).frame(height: 28)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13).frame(height: 24)
            }
            // ImageRenderer omits macOS ScrollView's native content. These are
            // static, design-only snapshots, so eagerly render the exact rows
            // and clip crowded fixtures to their first viewport instead.
            VStack(spacing: style.accountGap) {
                ForEach(Array(accounts.enumerated()), id: \.offset) { _, account in
                    ConceptAccount(style: style, account: account, showUsed: showUsed)
                }
            }
            .padding(.horizontal, 13).padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: height - chromeHeight - (warning == nil ? 0 : 24), alignment: .top)
            .clipped()
            line
            HStack(spacing: 6) {
                Text("Checked 10:42").font(.system(size: 10.5)).foregroundStyle(palette.faint)
                Text(":20128").font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
                Spacer(minLength: 0)
                ForEach(["arrow.clockwise", "arrow.up.right.square", "gearshape"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
                }
            }.foregroundStyle(palette.muted).padding(.horizontal, 13).frame(height: 34)
        }
        .frame(width: 310, height: height, alignment: .top)
        .background(palette.background).foregroundStyle(palette.text)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var line: some View { palette.border.opacity(0.5).frame(height: 1) }
}

private struct ConceptAccount: View {
    @Environment(\.trayPalette) private var palette
    let style: RowConcept
    let account: QuotaAccount
    let showUsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if style == .meters {
                identity.frame(height: 16).padding(.bottom, 2)
            }
            if account.windows.isEmpty {
                HStack(spacing: 6) {
                    if style != .meters { identity.frame(width: identityWidth) }
                    Text(account.active ? "Quota unavailable" : "No cached quota")
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                    Spacer(minLength: 0)
                }.frame(height: style.rowHeight)
            } else {
                ForEach(Array(account.windows.enumerated()), id: \.offset) { index, window in
                    HStack(spacing: style == .meters ? 7 : 5) {
                        if style == .inline {
                            if index == 0 { identity.frame(width: identityWidth) }
                            else { Color.clear.frame(width: identityWidth, height: 1).accessibilityHidden(true) }
                        } else if style == .ledger {
                            identity.frame(width: identityWidth)
                        }
                        Text(window.label).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.muted).lineLimit(1).truncationMode(.tail)
                            .frame(width: style == .meters ? 36 : 24, alignment: .leading).help(window.label)
                        if style != .ledger { meter(window) }
                        Text(window.unlimited ? "∞" : "\(window.displayedRoundedPercent(showUsed: showUsed))%")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(quotaColor(window)).frame(width: 34, alignment: .trailing)
                        if style == .ledger { Spacer(minLength: 0) }
                        Text(window.countdown(from: RowFixtures.now))
                            .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(palette.faint)
                            .frame(width: 49, alignment: .trailing)
                    }
                    .frame(height: style.rowHeight)
                    .overlay(alignment: .bottom) {
                        if style == .ledger { palette.border.opacity(0.2).frame(height: 0.5) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(account.name), \(window.label), \(window.unlimited ? "unlimited" : "\(window.displayedRoundedPercent(showUsed: showUsed)) percent \(showUsed ? "used" : "left")"), reset \(window.countdown(from: RowFixtures.now)), \(account.active ? "active" : "disabled")\(account.isStale ? ", stale" : "")")
                }
            }
        }
    }

    private var identityWidth: CGFloat { style == .ledger ? 147 : 104 }
    private var identity: some View {
        HStack(spacing: 5) {
            ConceptProviderMark(provider: account.provider)
            Text(account.name).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(account.active ? palette.text : palette.muted)
                .lineLimit(1).truncationMode(.middle).help(account.name)
            if !account.active {
                Text("OFF").font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.faint)
            }
            if account.isStale {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    .foregroundStyle(palette.warning).help("Stale cached quota")
            }
            if style == .meters { Spacer(minLength: 0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func quotaColor(_ window: QuotaWindow) -> Color {
        account.active ? palette.quotaColor(window.remainingPercent) : palette.muted
    }
    private func meter(_ window: QuotaWindow) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border.opacity(0.35))
                if window.unlimited {
                    Capsule().fill(palette.muted)
                } else {
                    Capsule().fill(quotaColor(window))
                        .frame(width: geometry.size.width * window.displayedPercent(showUsed: showUsed) / 100)
                }
            }
        }.frame(height: 4).accessibilityHidden(true)
    }
}

private struct ConceptProviderMark: View {
    let provider: String
    private var image: NSImage? {
        // Local bundled artwork only; previews must never read a real account or API key.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: root.appendingPathComponent("Assets/ProviderIcons/\(provider).svg"))
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "person.crop.circle").resizable().scaledToFit() }
        }.frame(width: 14, height: 14).accessibilityHidden(true)
    }
}

private struct RowComparisonBoard: View {
    let theme: QuotaTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("One quota. One row.").font(.system(size: 27, weight: .bold))
                Text("Three native layout concepts · 310 pt wide · illustrative data, not live accounts")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 28) {
                ForEach(RowConcept.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(style.title).font(.system(size: 16, weight: .semibold))
                        Text(style.description).font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(height: 28, alignment: .top)
                        RowConceptPopover(style: style, accounts: RowFixtures.standard, warning: nil, showUsed: false)
                            .environment(\.trayPalette, theme.palette)
                        Text("310 × \(Int(RowConceptPopover(style: style, accounts: RowFixtures.standard, warning: nil, showUsed: false).height)) pt")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Text(style.tradeoff).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }.frame(width: 310, alignment: .topLeading)
                }
            }
            Text("All ten quotas shown, in order. Same type scale and semantic colors. Content fits up to 425 pt; crowded fixtures show the first viewport.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(24).background(theme.isLight ? Color(white: 0.9) : Color(white: 0.085))
    }
}

private struct RowStateBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sparse and edge-state checks").font(.system(size: 23, weight: .bold))
            Text("Illustrative fixtures · one account, long names, 0%, unlimited, missing resets, disabled, stale, unavailable")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                ForEach(RowConcept.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(style.title).font(.system(size: 15, weight: .semibold))
                        RowConceptPopover(style: style, accounts: RowFixtures.sparse, warning: nil, showUsed: false)
                        RowConceptPopover(style: style, accounts: RowFixtures.extremes,
                                          warning: "Showing last known quotas", showUsed: true)
                    }.frame(width: 310)
                }
            }
        }.padding(24).background(Color(white: 0.085))
    }
}
#endif
