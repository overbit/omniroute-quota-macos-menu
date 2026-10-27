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

/// A native template mark in Static mode; in Dynamic mode, the percentage
/// reports the lowest remaining quota among the chosen providers/accounts.
private struct MenuBarQuotaIndicator: View {
    let status: QuotaMenuStatus

    private var tint: Color {
        switch status.severity {
        case .critical: return .red
        case .low: return .orange
        case .checking, .unknown: return .secondary
        case .staticIcon, .healthy: return .primary
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: OmniRouteMenuMark.image)
                .renderingMode(.template)
                .foregroundStyle(tint)
                .frame(width: OmniRouteMenuMark.pointSize, height: OmniRouteMenuMark.pointSize)
                .accessibilityHidden(true)

            if status.isLow {
                Text("\(status.lowestPercent ?? 0)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            } else if status.connectionUnavailable {
                Text("!")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            } else if status.severity == .unknown {
                Text("?")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 12)
        .fixedSize(horizontal: true, vertical: false)
        .help(status.description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.description)
    }
}
#else
@main
struct PlatformNotice {
    static func main() { print("OmniRouteQuota runs on macOS 14 or later.") }
}
#endif
