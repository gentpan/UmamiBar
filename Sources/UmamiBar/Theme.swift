import AppKit
import SwiftUI

// Shared design tokens for the liquid-glass restyle.
enum Theme {
    /// Flat brand blue — deliberately solid, no gradients.
    static let brand = Color(.sRGB, red: 38 / 255, green: 128 / 255, blue: 235 / 255)
    // Match the original Umami chart legend: visitors 80%, views 60%.
    static let visitorsBlue = brand.opacity(0.8)
    static let pageviewsBlue = brand.opacity(0.6)
    // Opaque blue fills avoid picking up the macOS accent color or glass backdrop.
    static let softBlue = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.10, green: 0.20, blue: 0.35, alpha: 1)
        }
        return NSColor(srgbRed: 225 / 255, green: 237 / 255, blue: 252 / 255, alpha: 1)
    }))

    /// Solid brand fill kept as a one-stop gradient so existing call sites
    /// (chart stroke, bar tracks) render flat blue.
    static let brandGradient = LinearGradient(
        colors: [brand],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Translucent fill for chart areas.
    static let brandFill = LinearGradient(
        colors: [brand.opacity(0.30)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let popoverWidth: CGFloat = 392
    static let cardCorner: CGFloat = 14
    static let rowCorner: CGFloat = 10

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

extension View {
    func insetCard(cornerRadius: CGFloat = 10) -> some View {
        background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            }
    }

    /// Rounded liquid-glass plate.
    func glassCard(cornerRadius: CGFloat = Theme.cardCorner) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// App-icon-style gradient badge carrying the Umami mark, used in headers
/// and empty states.
struct BrandBadge: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 8

    var body: some View {
        UmamiMark()
            .foregroundStyle(.white)
            .frame(width: size * 0.6, height: size * 0.6)
            .frame(width: size, height: size)
            .background(
                Theme.brandGradient,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: Theme.brand.opacity(0.4), radius: 8, y: 3)
    }
}

/// A static status indicator keeps an idle dashboard from continuously redrawing.
struct LiveDot: View {
    var body: some View {
        Circle().fill(.green).frame(width: 6, height: 6)
    }
}
