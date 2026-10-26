// Compile this against the actual SwiftUI Shape used by MenuBarExtra, rather
// than checking an unused bitmap in the packaged app.
import CoreGraphics
import Foundation
import SwiftUI

@main
struct VerifyMenuBarMark {
    static func main() {
        let size = OmniRouteMenuMark.pointSize
        guard size == 10 else { fatalError("Menu-bar glyph must stay compact") }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let path = OmniRouteMenuMark().path(in: rect).cgPath
        let bounds = path.boundingBoxOfPath
        var dots = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { dots += 1 }
        }

        guard dots == 8 else {
            fatalError("Expected eight separate dots; got \(dots)")
        }
        guard !bounds.isEmpty && bounds.minX > 0.5 && bounds.minY > 0.5
              && bounds.maxX < size - 0.5 && bounds.maxY < size - 0.5 else {
            fatalError("Menu-bar mark overflows its \(size)pt icon slot: \(bounds)")
        }
        print("Verified eight-dot OmniRoute menu glyph within \(size)pt bounds")
    }
}
