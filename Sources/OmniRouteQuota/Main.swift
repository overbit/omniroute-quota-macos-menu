#if os(macOS)
import SwiftUI

@main
struct OmniRouteQuotaApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(systemName: store.lowestRemaining.map { $0 < 20 } == true
                  ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                .accessibilityLabel("OmniRoute quotas")
        }
        .menuBarExtraStyle(.window)
    }
}
#else
@main
struct PlatformNotice {
    static func main() { print("OmniRouteQuota runs on macOS 14 or later.") }
}
#endif
