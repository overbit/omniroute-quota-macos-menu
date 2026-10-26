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
        HStack(spacing: 3) {
            Group {
                if let icon = OmniRouteArtwork.statusBar {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 13, height: 13)
            .foregroundStyle(tint)

            if status.isLow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text("\(status.lowestPercent ?? 0)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            if status.connectionUnavailable {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else if status.severity == .checking {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else if status.severity == .unknown {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 15)
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
