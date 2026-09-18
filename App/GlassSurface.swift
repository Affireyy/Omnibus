import SwiftUI

/// A restrained "glass panel" look: the real Liquid Glass material on
/// macOS 26 (Tahoe) and later, falling back to a plain translucent
/// Material + hairline border on older macOS so the app still looks
/// intentional rather than broken.
///
/// NOTE: Liquid Glass (`.glassEffect`) is a brand-new SwiftUI API as of
/// Xcode 26. If its exact signature has shifted since this was written,
/// this is the one place to fix -- everything else just calls `.glassSurface()`.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

/// Quiet, low-saturation backdrop for the dashboard window -- a hint of
/// the accent color rather than a loud gradient, so the glass panels read
/// as the focus instead of the background competing with them.
struct DashboardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.05),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
