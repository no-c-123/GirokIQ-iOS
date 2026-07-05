import SwiftUI

struct GenieTransitionModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let edge: Edge
    let travel: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let inverse = 1 - p
        let bow = sin(p * .pi)
        let anchor = anchorPoint(for: edge)
        let scaleX = horizontalCollapseScale(progress: p, bow: bow)
        let scaleY = verticalCollapseScale(progress: p, bow: bow)
        let offset = travelOffset(inverse: inverse, bow: bow)
        let skew = skewTransform(inverse: inverse, bow: bow)
        let rotation = rotationAngle(inverse: inverse, bow: bow)

        content
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
            .transformEffect(skew)
            .rotationEffect(rotation, anchor: anchor)
            .offset(offset)
            .blur(radius: inverse * 12)
            .opacity(0.12 + 0.88 * p)
    }

    private func anchorPoint(for edge: Edge) -> UnitPoint {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func horizontalCollapseScale(progress: CGFloat, bow: CGFloat) -> CGFloat {
        switch edge {
        case .leading, .trailing:
            return max(0.02, 0.02 + (0.98 * pow(progress, 0.74)))
        case .top, .bottom:
            return 0.72 + (0.28 * progress) + (0.05 * bow)
        }
    }

    private func verticalCollapseScale(progress: CGFloat, bow: CGFloat) -> CGFloat {
        switch edge {
        case .top, .bottom:
            return max(0.02, 0.02 + (0.98 * pow(progress, 0.74)))
        case .leading, .trailing:
            return 0.70 + (0.30 * progress) + (0.06 * bow)
        }
    }

    private func travelOffset(inverse: CGFloat, bow: CGFloat) -> CGSize {
        let primary = travel * pow(inverse, 0.84)
        let cross = travel * 0.24 * bow * inverse
        switch edge {
        case .leading:
            return CGSize(width: -primary, height: -cross)
        case .trailing:
            return CGSize(width: primary, height: -cross)
        case .top:
            return CGSize(width: cross, height: -primary)
        case .bottom:
            return CGSize(width: cross, height: primary)
        }
    }

    private func skewTransform(inverse: CGFloat, bow: CGFloat) -> CGAffineTransform {
        let amount = (0.26 * inverse) + (0.12 * bow * inverse)
        switch edge {
        case .leading:
            return CGAffineTransform(a: 1, b: 0, c: -amount, d: 1, tx: 0, ty: 0)
        case .trailing:
            return CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: 0, ty: 0)
        case .top:
            return CGAffineTransform(a: 1, b: -amount, c: 0, d: 1, tx: 0, ty: 0)
        case .bottom:
            return CGAffineTransform(a: 1, b: amount, c: 0, d: 1, tx: 0, ty: 0)
        }
    }

    private func rotationAngle(inverse: CGFloat, bow: CGFloat) -> Angle {
        let degrees = 8 * inverse * bow
        switch edge {
        case .leading, .top:
            return .degrees(-degrees)
        case .trailing, .bottom:
            return .degrees(degrees)
        }
    }
}

extension AnyTransition {
    static func genie(edge: Edge, travel: CGFloat = 42) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GenieTransitionModifier(progress: 0, edge: edge, travel: travel * 1.1),
                identity: GenieTransitionModifier(progress: 1, edge: edge, travel: travel * 1.1)
            ),
            removal: .modifier(
                active: GenieTransitionModifier(progress: 0, edge: edge, travel: travel * 1.45),
                identity: GenieTransitionModifier(progress: 1, edge: edge, travel: travel * 1.45)
            )
        )
    }
}

extension View {
    func genieTransitionProgress(_ progress: CGFloat, from edge: Edge, travel: CGFloat = 42) -> some View {
        modifier(GenieTransitionModifier(progress: progress, edge: edge, travel: travel))
    }
}
