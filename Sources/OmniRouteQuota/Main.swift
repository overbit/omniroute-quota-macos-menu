#if os(macOS)
import SwiftUI

@main
struct OmniRouteQuotaApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            ZStack(alignment: .bottomTrailing) {
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

                if store.lowestRemaining.map({ $0 < 20 }) == true {
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                        .offset(x: 1, y: 1)
                }
            }
            .frame(width: 15, height: 15)
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
