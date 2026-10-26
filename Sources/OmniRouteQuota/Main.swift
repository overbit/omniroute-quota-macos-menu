#if os(macOS)
import QuotaCore
import SwiftUI

@main
struct OmniRouteQuotaApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarQuotaIndicator(status: store.menuBarStatus)
                // The menu-bar item exists before its popover is opened.
                .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Stays icon-only when quotas are healthy; expands just enough to show the
/// lowest remaining percentage as soon as any active account runs low.
private struct MenuBarQuotaIndicator: View {
    let status: QuotaMenuStatus

    private var tint: Color {
        switch status.severity {
        case .critical: return .red
        case .low: return .orange
        case .checking, .unknown: return .secondary
        case .healthy: return .primary
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Group {
                if let icon = OmniRouteArtwork.statusBar {
                    // NSImage already has its 11 pt intrinsic size. Do not
                    // rescale the 22 px artwork and blur its fine silhouette.
                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .interpolation(.none)
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 11))
                }
            }
            .frame(width: 11, height: 11)
            .foregroundStyle(tint)

            if status.isLow {
                // The percentage *is* the warning. An extra triangle makes
                // the status item large and harder to read at menu-bar scale.
                Text("\(status.lowestPercent ?? 0)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            } else if status.connectionUnavailable {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            } else if status.severity == .unknown {
                Image(systemName: "questionmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 12)
        .fixedSize(horizontal: true, vertical: false)
        .help(status.description)
        .accessibilityLabel(status.description)
    }

}
#else
@main
struct PlatformNotice {
    static func main() { print("OmniRouteQuota runs on macOS 14 or later.") }
}
#endif
