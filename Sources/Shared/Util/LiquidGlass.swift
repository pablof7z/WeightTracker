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

// MARK: - Glass button style with bordered fallback

extension View {
    /// Applies `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` on iOS 26+
    /// (and watchOS 26+, macOS 26+). Falls back to `.bordered` / `.borderedProminent`
    /// on earlier OSes. The branches use distinct concrete `ButtonStyle` types,
    /// so this must be `@ViewBuilder` (not a ternary at the modifier site).
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Applies `.buttonBorderShape(.circle)` on iOS 26+ (works with `.glassProminent`),
    /// falls back to `.clipShape(Circle())` on earlier OSes.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonBorderShape(.circle)
        } else {
            self.clipShape(Circle())
        }
    }

    /// Toast/banner capsule shorthand. Applies `.glass(in: Capsule(), tint:)` —
    /// effectively a glass capsule on iOS 26+ and a `.regularMaterial` capsule
    /// on earlier OSes. The caller is responsible for any inner padding.
    func glassToastCapsule(tint: Color? = nil) -> some View {
        self.glass(in: Capsule(), tint: tint)
    }
}

// MARK: - One-shot iOS 26 transformation

extension View {
    /// Applies `transform` to `self` on iOS 26+, returns `self` unchanged below.
    /// Useful for one-off iOS-26 modifiers like `.glassEffectID` or
    /// `.tabViewBottomAccessory` without scattering `if #available` branches.
    @ViewBuilder
    func ifAvailableiOS26<T: View>(_ transform: (Self) -> T) -> some View {
        if #available(iOS 26.0, *) {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Tab bar / navigation iOS-26 wrappers

extension View {
    /// `.tabBarMinimizeBehavior(.onScrollDown)` on iOS 26+, no-op below.
    /// iOS-only API; on watchOS/macOS this is also a no-op.
    @ViewBuilder
    func tabBarMinimizeOnScrollDown() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Pairs with `.zoomNavigationTransition(sourceID:in:)`: marks a source
    /// element for an iOS 26 matched-zoom navigation. No-op on earlier OSes.
    @ViewBuilder
    func matchedZoomSource<ID: Hashable & Sendable>(id: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Applies `.navigationTransition(.zoom(sourceID:in:))` on iOS 26+. No-op below.
    @ViewBuilder
    func zoomNavigationTransition<ID: Hashable & Sendable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Glass effect identity (for morphing)

extension View {
    /// Applies `.glassEffectID(_:in:)` on iOS 26+ inside a `LiquidGlassContainer`,
    /// no-op on earlier OSes. Pre-iOS-26 the helper is a pass-through and the
    /// container is also a pass-through, so morphing is gracefully omitted.
    @ViewBuilder
    func glassMorphID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, watchOS 26.0, macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
