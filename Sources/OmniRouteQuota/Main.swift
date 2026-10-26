#if os(macOS)
import SwiftUI

@main
struct OmniRouteQuotaApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            HStack(spacing: 3) {
                if let icon = OmniRouteArtwork.statusBar {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                }
                if store.lowestRemaining.map({ $0 < 20 }) == true {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
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
