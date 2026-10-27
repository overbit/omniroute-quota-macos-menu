#if os(macOS)
import AppKit

/// AppKit-backed template artwork for the status item. MenuBarExtra does not
/// reliably host an arbitrary SwiftUI Shape in its label on every macOS build.
/// A real NSImage with 1x/2x bitmap representations always has drawable pixels.
@MainActor
enum OmniRouteMenuMark {
    static let pointSize: CGFloat = 14

    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            let pixels = Int(pointSize) * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
                continue
            }

            let cg = graphics.cgContext
            cg.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            cg.setFillColor(NSColor.black.cgColor)
            cg.setShouldAntialias(true)

            let side = CGFloat(pixels)
            let center = side / 2
            let orbit = side * 0.32
            let diameter = side * 0.215
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4 - .pi / 2
                cg.fillEllipse(in: CGRect(
                    x: center + cos(angle) * orbit - diameter / 2,
                    y: center + sin(angle) * orbit - diameter / 2,
                    width: diameter, height: diameter
                ))
            }
            cg.flush()
            rep.size = NSSize(width: pointSize, height: pointSize)
            image.addRepresentation(rep)
        }
        image.isTemplate = true // Adapts automatically to light/dark menu bars.
        return image
    }()
}
#endif
