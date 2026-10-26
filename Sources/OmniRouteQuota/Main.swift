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

/// The official OmniRoute mark has eight outer dots and a detailed central
/// symbol. At 10pt the central raster detail merges into a dark blur, so use a
/// clean vector rendering of the eight-dot ring at native display scale.
private struct OmniRouteMenuMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let orbit = side * 0.34
        let diameter = side * 0.18
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var dots = Path()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4 - .pi / 2
            let x = center.x + CGFloat(cos(angle)) * orbit
            let y = center.y + CGFloat(sin(angle)) * orbit
            dots.addEllipse(in: CGRect(
                x: x - diameter / 2,
                y: y - diameter / 2,
                width: diameter,
                height: diameter
            ))
        }
        return dots
    }
}

/// A tiny branded mark at rest, plus an unambiguous percentage when any active
/// account is low. No bitmap scaling or redundant alert icon is necessary.
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
            OmniRouteMenuMark()
                .fill(tint)
                .frame(width: 10, height: 10)
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
