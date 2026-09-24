import SwiftUI

// MARK: - Conditional Modifier

extension View {
    /// Applies a modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Applies a modifier conditionally with an else branch
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        then trueTransform: (Self) -> TrueContent,
        else falseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            trueTransform(self)
        } else {
            falseTransform(self)
        }
    }
}

// MARK: - Visibility

extension View {
    /// Hides the view while keeping its layout space
    func hidden(_ isHidden: Bool) -> some View {
        opacity(isHidden ? 0 : 1)
    }
}

// MARK: - Read Size

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    /// Reads the view's size and passes it to a callback
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// MARK: - Frame Helpers

extension View {
    /// Expands the view to fill the maximum available width
    func fillWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    /// Expands the view to fill the maximum available height
    func fillHeight(alignment: Alignment = .center) -> some View {
        frame(maxHeight: .infinity, alignment: alignment)
    }

    /// Expands the view to fill all available space
    func fillFrame(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Accessibility: Reduce Motion Animation Wrapper

private func isMotionReduced() -> Bool {
    UIAccessibility.isReduceMotionEnabled || UserDefaults.standard.bool(forKey: "reducedMotion")
}

extension View {
    /// Performs an animated state change respecting Reduce Motion preference.
    /// When Reduce Motion is enabled, the change is applied instantly.
    func withMotionSafeAnimation<V: Equatable>(
        _ animation: Animation = GAnimation.spring,
        value: V? = nil as Bool?,
        _ body: () -> Void
    ) {
        if isMotionReduced() {
            body()
        } else {
            withAnimation(animation) { body() }
        }
    }
}

/// Wraps `withAnimation` respecting the Reduce Motion accessibility preference.
/// Use in place of `withAnimation(_:)` throughout the app.
func animateMotionSafe(
    _ animation: Animation = GAnimation.spring,
    _ body: () -> Void
) {
    if isMotionReduced() {
        body()
    } else {
        withAnimation(animation) { body() }
    }
}

// MARK: - Accessibility: Minimum Tap Target

extension View {
    /// Ensures a minimum 44×44pt tap target per Apple HIG.
    func minTapTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .onAppear {
                    guard !isMotionReduced() else { return }
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
            )
            .clipped()
    }
}

extension View {
    /// Adds a shimmer loading effect overlay
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
