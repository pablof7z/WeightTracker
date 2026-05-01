import SwiftUI

/// Liquid Glass helper that applies the iOS 26 `.glassEffect(...)` modifier
/// when available, and falls back to `.regularMaterial` on earlier OSes.
///
/// Usage:
///     .glass(in: RoundedRectangle(cornerRadius: 16))
///     .glass(in: Capsule(), tint: .accentColor)
extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26+ so child glass views
/// render with proper inter-element refraction. On older OSes, returns content
/// directly.
struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
