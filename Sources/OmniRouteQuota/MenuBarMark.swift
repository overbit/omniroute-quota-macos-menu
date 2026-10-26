#if os(macOS)
import SwiftUI

/// The official OmniRoute mark has eight outer dots and a detailed central
/// symbol. At 10pt the central raster detail merges into a dark blur, so use a
/// clean vector rendering of the eight-dot ring at native display scale.
struct OmniRouteMenuMark: Shape {
    static let pointSize: CGFloat = 10
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

#endif
