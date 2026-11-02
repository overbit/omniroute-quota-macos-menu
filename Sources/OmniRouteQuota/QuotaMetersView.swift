#if os(macOS)
import QuotaCore
import SwiftUI

/// Shared dimensions keep the popover's content-fit estimate in step with its rows.
enum QuotaMeterLayout {
    static let accountHeadingHeight: CGFloat = 16
    static let headingSpacing: CGFloat = 2
    static let meterRowHeight: CGFloat = 16
    static let ledgerRowHeight: CGFloat = 22
    static let unavailableRowHeight: CGFloat = 20

    static func accountSpacing(for mode: QuotaLayoutMode) -> CGFloat {
        mode == .fullWidthRows ? 4 : 0
    }

    static func providerSpacing(for mode: QuotaLayoutMode) -> CGFloat {
        mode == .fullWidthRows ? 5 : 0
    }

    static func accountHeight(windowCount: Int, mode: QuotaLayoutMode = .defaultMode) -> CGFloat {
        switch mode {
        case .fullWidthRows:
            return accountHeadingHeight + headingSpacing
                + (windowCount == 0 ? unavailableRowHeight : CGFloat(windowCount) * meterRowHeight)
        case .quotaLedger:
            return CGFloat(max(1, windowCount)) * ledgerRowHeight
        }
    }
}

/// Every quota window gets its own full-width row, in the original API order.
struct QuotaWindowMeters: View {
    let windows: [QuotaWindow]
    let showUsed: Bool
    let inactive: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(windows) { window in
                QuotaWindowRow(window: window, showUsed: showUsed, inactive: inactive)
            }
        }
    }
}

/// Shared labels, percentage semantics and countdowns for both supported layouts.
struct QuotaWindowRow: View {
    @Environment(\.trayPalette) private var palette
    let window: QuotaWindow
    let showUsed: Bool
    let inactive: Bool
    var showsMeter = true

    private var color: Color {
        inactive ? palette.muted : palette.quotaColor(window.remainingPercent)
    }

    var body: some View {
        HStack(spacing: showsMeter ? 7 : 5) {
            Text(window.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: showsMeter ? 36 : 24, alignment: .leading)
                .help(window.label)
            if showsMeter {
                QuotaProgressTrack(value: window.unlimited ? 100 : window.displayedPercent(showUsed: showUsed),
                                   color: color)
            }
            QuotaPercentage(window: window, showUsed: showUsed, color: color)
                .frame(width: 34, alignment: .trailing)
            QuotaResetTime(window: window)
                .frame(width: 49, alignment: .trailing)
        }
        .frame(height: showsMeter ? QuotaMeterLayout.meterRowHeight : QuotaMeterLayout.ledgerRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.quotaAccessibilityLabel(showUsed: showUsed))
    }
}

private struct QuotaProgressTrack: View {
    @Environment(\.trayPalette) private var palette
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border.opacity(0.35))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * value / 100)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct QuotaPercentage: View {
    let window: QuotaWindow
    let showUsed: Bool
    let color: Color

    var body: some View {
        Text(window.unlimited ? "∞" : "\(window.displayedRoundedPercent(showUsed: showUsed))%")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .monospacedDigit()
            .fixedSize()
    }
}

private struct QuotaResetTime: View {
    @Environment(\.trayPalette) private var palette
    let window: QuotaWindow

    var body: some View {
        Text(window.countdown())
            .font(.system(size: 9.5))
            .foregroundStyle(palette.faint)
            .monospacedDigit()
            .fixedSize()
            .help(window.resetAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
                  ?? "Reset time unavailable")
    }
}

extension QuotaWindow {
    func quotaAccessibilityLabel(showUsed: Bool) -> String {
        let quota = unlimited ? "unlimited" : "\(displayedRoundedPercent(showUsed: showUsed)) percent \(showUsed ? "used" : "remaining")"
        let reset = resetAt == nil ? "reset time unavailable" : "resets \(countdown())"
        return "\(label): \(quota), \(reset)"
    }
}
#endif
