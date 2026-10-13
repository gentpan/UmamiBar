import SwiftUI

/// The official Umami mark (umami.svg), drawn as vectors so it stays crisp at
/// any size and inherits the surrounding foreground style like a template
/// image: black on a light menu bar, white on a dark one.
///
/// Geometry follows the original 20×20 viewBox:
/// a circle outline centered on (10, 9.4) and a filled bowl below y = 7.2.
struct UmamiMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let scale = side / 20
            let transform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: (proxy.size.width - 20 * scale) / 2,
                ty: (proxy.size.height - 20 * scale) / 2
            )
            ZStack {
                ring.applying(transform)
                    .stroke(lineWidth: 0.9346 * scale)
                bowl.applying(transform)
                    .fill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Circle outline, centered on (10, 9.4) with r = 8.
    private var ring: Path {
        Path(ellipseIn: CGRect(x: 2, y: 1.4, width: 16, height: 16))
    }

    /// Filled bowl shape beneath the horizontal bar.
    private var bowl: Path {
        var path = Path()
        path.move(to: CGPoint(x: 19.3, y: 7.2))
        path.addLine(to: CGPoint(x: 0.7, y: 7.2))
        path.addCurve(to: CGPoint(x: 0, y: 7.9),
                      control1: CGPoint(x: 0.3, y: 7.2),
                      control2: CGPoint(x: 0, y: 7.5))
        path.addLine(to: CGPoint(x: 0, y: 9.1))
        path.addCurve(to: CGPoint(x: 10, y: 19.1),
                      control1: CGPoint(x: 0, y: 14.6),
                      control2: CGPoint(x: 4.5, y: 19.1))
        path.addCurve(to: CGPoint(x: 20, y: 9.3),
                      control1: CGPoint(x: 15.4, y: 19.1),
                      control2: CGPoint(x: 19.9, y: 14.8))
        path.addLine(to: CGPoint(x: 20, y: 7.9))
        path.addCurve(to: CGPoint(x: 19.3, y: 7.2),
                      control1: CGPoint(x: 20, y: 7.5),
                      control2: CGPoint(x: 19.7, y: 7.2))
        path.closeSubpath()
        return path
    }
}
