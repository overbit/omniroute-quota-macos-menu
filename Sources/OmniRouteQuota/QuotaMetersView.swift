#if os(macOS)
import QuotaCore
import SwiftUI

/// Keep the scroll-height estimate in step with the actual compact account rows.
enum QuotaMeterLayout {
    static let accountHeadingHeight: CGFloat = 16
    static let primaryRowHeight: CGFloat = 29
    static let overflowRowHeight: CGFloat = 15
    static let rowSpacing: CGFloat = 3

    static func accountHeight(windowCount: Int) -> CGFloat {
        let metersHeight: CGFloat
        switch windowCount {
        case 0: metersHeight = 20
        case 1: metersHeight = overflowRowHeight
        default: metersHeight = primaryRowHeight + CGFloat(windowCount - 2) * (overflowRowHeight + rowSpacing)
        }
        return accountHeadingHeight + rowSpacing + metersHeight
    }
}

/// The first two windows share a row. Additional windows stay visible below it,
/// in their original order, rather than being truncated or put behind a click.
struct QuotaWindowMeters: View {
    let windows: [QuotaWindow]
    let showUsed: Bool
    let inactive: Bool

    var primaryWindows: ArraySlice<QuotaWindow> { windows.prefix(2) }
    var additionalWindows: ArraySlice<QuotaWindow> { windows.dropFirst(2) }

    var body: some View {
        if windows.count == 1, let window = windows.first {
            // Do not spend two lines on an account with only one quota window.
            QuotaOverflowRow(window: window, showUsed: showUsed, inactive: inactive)
        } else {
            VStack(spacing: QuotaMeterLayout.rowSpacing) {
                HStack(spacing: 6) {
                    ForEach(primaryWindows) { window in
                        QuotaMeterCell(window: window, showUsed: showUsed, inactive: inactive)
                    }
                }
                ForEach(additionalWindows) { window in
                    QuotaOverflowRow(window: window, showUsed: showUsed, inactive: inactive)
                }
            }
        }
    }
}

private struct QuotaMeterCell: View {
    @Environment(\.trayPalette) private var palette
    let window: QuotaWindow
    let showUsed: Bool
    let inactive: Bool

    private var color: Color {
        inactive ? palette.muted : palette.quotaColor(window.remainingPercent)
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(window.label)
                Spacer(minLength: 2)
                QuotaPercentage(window: window, showUsed: showUsed, color: color)
            }
            .frame(height: 12)

            HStack(spacing: 4) {
                QuotaProgressTrack(value: window.displayedPercent(showUsed: showUsed), color: color)
                QuotaResetTime(window: window, fontSize: 9)
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: QuotaMeterLayout.primaryRowHeight)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border.opacity(0.45), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.meterAccessibilityLabel(showUsed: showUsed))
    }
}

private struct QuotaOverflowRow: View {
    @Environment(\.trayPalette) private var palette
    let window: QuotaWindow
    let showUsed: Bool
    let inactive: Bool

    private var color: Color {
        inactive ? palette.muted : palette.quotaColor(window.remainingPercent)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(window.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 28, alignment: .leading)
                .help(window.label)
            QuotaProgressTrack(value: window.displayedPercent(showUsed: showUsed), color: color)
            QuotaPercentage(window: window, showUsed: showUsed, color: color)
                .frame(width: 34, alignment: .trailing)
            QuotaResetTime(window: window, fontSize: 9)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(height: QuotaMeterLayout.overflowRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.meterAccessibilityLabel(showUsed: showUsed))
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
    let fontSize: CGFloat

    var body: some View {
        Text(window.countdown())
            .font(.system(size: fontSize))
            .foregroundStyle(palette.faint)
            .monospacedDigit()
            .fixedSize()
            .help(window.resetAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
                  ?? "Reset time unavailable")
    }
}

private extension QuotaWindow {
    func meterAccessibilityLabel(showUsed: Bool) -> String {
        let quota = unlimited ? "unlimited" : "\(displayedRoundedPercent(showUsed: showUsed)) percent \(showUsed ? "used" : "remaining")"
        let reset = resetAt == nil ? "reset time unavailable" : "resets \(countdown())"
        return "\(label): \(quota), \(reset)"
    }
}
#endif
