import SwiftUI
import UIKit

// MARK: - TiledBackgroundView (SwiftUI wrapper)

/// Renders the infinite canvas background pattern using CATiledLayer
/// for performant rendering at all zoom levels.
struct TiledBackgroundView: UIViewRepresentable {
    let pattern: BackgroundPattern

    func makeUIView(context: Context) -> TiledBackgroundUIView {
        let view = TiledBackgroundUIView()
        view.pattern = pattern
        return view
    }

    func updateUIView(_ uiView: TiledBackgroundUIView, context: Context) {
        if uiView.pattern != pattern {
            uiView.pattern = pattern
            uiView.setNeedsDisplay()
        }
    }
}

// MARK: - TiledBackgroundUIView

final class TiledBackgroundUIView: UIView {
    var pattern: BackgroundPattern = .grid {
        didSet { setNeedsDisplay() }
    }

    override class var layerClass: AnyClass { CATiledLayer.self }

    private var tiledLayer: CATiledLayer { layer as! CATiledLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTiledLayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTiledLayer() {
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 2
        backgroundColor = .gBackground
        isOpaque = true
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Fill background
        ctx.setFillColor(UIColor.gBackground.cgColor)
        ctx.fill(rect)

        let spacing: CGFloat = 28

        switch pattern {
        case .blank:
            break

        case .grid:
            ctx.setStrokeColor(UIColor.gGridLine.cgColor)
            ctx.setLineWidth(0.5)

            // Snap to grid so tiles align
            let startX = (rect.minX / spacing).rounded(.down) * spacing
            let startY = (rect.minY / spacing).rounded(.down) * spacing

            var x = startX
            while x <= rect.maxX {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }
            var y = startY
            while y <= rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            ctx.strokePath()

        case .dots:
            ctx.setFillColor(UIColor.gDot.cgColor)
            let startX = (rect.minX / spacing).rounded(.down) * spacing + spacing
            let startY = (rect.minY / spacing).rounded(.down) * spacing + spacing

            var x = startX
            while x < rect.maxX {
                var y = startY
                while y < rect.maxY {
                    ctx.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                    y += spacing
                }
                x += spacing
            }

        case .lines:
            ctx.setStrokeColor(UIColor.gGridLine.cgColor)
            ctx.setLineWidth(0.5)
            let startY = (rect.minY / spacing).rounded(.down) * spacing

            var y = startY
            while y <= rect.maxY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            ctx.strokePath()

        case .isometric:
            ctx.setStrokeColor(UIColor.gGridLine.cgColor)
            ctx.setLineWidth(0.5)
            let h = spacing * 0.866
            let startY = (rect.minY / h).rounded(.down) * h - rect.height

            var y = startY
            while y <= rect.maxY + rect.height {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y + rect.width * 0.577))
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y - rect.width * 0.577))
                y += h
            }
            ctx.strokePath()
        }
    }
}
