// Verify the EXACT AppKit image used by the MenuBarExtra label has visible
// pixels at 1x and Retina 2x. A vector Shape path test misses blank UI labels.
import AppKit

@main
@MainActor
struct VerifyMenuBarMark {
    static func main() {
        let icon = OmniRouteMenuMark.image
        guard icon.isValid, icon.isTemplate,
              icon.size == NSSize(width: 14, height: 14) else {
            fatalError("Status-bar icon must be a valid 14pt template NSImage")
        }

        let bitmaps = icon.representations.compactMap { $0 as? NSBitmapImageRep }
        guard bitmaps.count == 2 else {
            fatalError("Expected 1x and 2x icon representations, got \(bitmaps.count)")
        }

        for scale in [1, 2] {
            let pixels = 14 * scale
            guard let bitmap = bitmaps.first(where: {
                $0.pixelsWide == pixels && $0.pixelsHigh == pixels
            }) else {
                fatalError("Missing \(scale)x representation")
            }

            // A visible icon should have 8 separate, opaque dots, no opaque
            // background, and enough painted pixels to survive menu-bar scale.
            let center = CGFloat(pixels) / 2
            let orbit = CGFloat(pixels) * 0.32
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4 - .pi / 2
                let x = Int((center + cos(angle) * orbit).rounded())
                let y = Int((center + sin(angle) * orbit).rounded())
                guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.6 else {
                    fatalError("Dot \(index) is invisible at \(scale)x")
                }
            }

            var opaqueCount = 0
            for y in 0..<pixels {
                for x in 0..<pixels {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                        opaqueCount += 1
                    }
                }
            }
            guard opaqueCount > 30 * scale * scale,
                  opaqueCount < pixels * pixels / 2 else {
                fatalError("Icon is empty or filled at \(scale)x: \(opaqueCount) pixels")
            }
            guard (bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05,
                  (bitmap.colorAt(x: pixels / 2, y: pixels / 2)?.alphaComponent ?? 1) < 0.05 else {
                fatalError("The icon should have a clear background and center")
            }
            print("Visible OmniRoute glyph at \(scale)x: \(opaqueCount) pixels")
        }
    }
}
