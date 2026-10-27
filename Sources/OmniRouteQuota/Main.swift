#if os(macOS)
import AppKit
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

/// MenuBarExtra can keep its SwiftUI content mounted while its window is
/// hidden. Observe the actual host window instead of relying on onDisappear.
struct PopoverVisibilityReader: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }

    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var visibility: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            visibility = nil
            if let window {
                visibility = window.observe(\.isVisible, options: [.new]) { [weak self] window, _ in
                    DispatchQueue.main.async { [weak self, weak window] in
                        self?.changed?(window?.isVisible == true)
                    }
                }
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                        guard let self else { return }
                        if notification.name == NSWindow.willCloseNotification || notification.name == NSWindow.didResignKeyNotification {
                            self.changed?(false)
                        } else {
                            self.changed?(self.window?.isVisible == true)
                        }
                    })
                }
            }
            // Do not publish ObservableObject changes during SwiftUI layout.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.changed?(self.window?.isVisible == true)
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
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
