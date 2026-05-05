import UIKit

// MARK: - BackgroundPatternView

/// CATiledLayer-backed UIView that renders the canvas background pattern.
///
/// **Critical:** The frame must be set exactly once at init and never changed.
/// Any frame mutation triggers CATiledLayer tile invalidation, causing visual
/// pumping artifacts. Zoom/pan is handled by the parent UIScrollView.
final class BackgroundPatternView: UIView {

    var pattern: BackgroundPattern = .grid {
        didSet {
            guard oldValue != pattern else { return }
            layer.setNeedsDisplay()
        }
    }

    var pageBackgroundColor: UIColor = .gBackground {
        didSet {
            guard oldValue != pageBackgroundColor else { return }
            layer.setNeedsDisplay()
        }
    }

    override class var layerClass: AnyClass { CATiledLayer.self }

    // Safe: layerClass is CATiledLayer.self, so this cast always succeeds
    private var tiledLayer: CATiledLayer { layer as! CATiledLayer } // swiftlint:disable:this force_cast

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false

        tiledLayer.levelsOfDetail = 6
        tiledLayer.levelsOfDetailBias = 3
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Fill tile background
        ctx.setFillColor(pageBackgroundColor.cgColor)
        ctx.fill(rect)

        let spacing: CGFloat = 28

        switch pattern {
        case .blank:
            break
        case .grid:
            drawGrid(in: rect, context: ctx, spacing: spacing)
        case .dots:
            drawDots(in: rect, context: ctx, spacing: spacing)
        case .lines:
            drawLines(in: rect, context: ctx, spacing: spacing)
        case .isometric:
            drawIsometric(in: rect, context: ctx, spacing: spacing)
        }
    }

    // MARK: - Pattern Renderers

    private func drawGrid(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
        ctx.setStrokeColor(UIColor.gGridLine.cgColor)
        ctx.setLineWidth(0.5)

        let startX = floor(rect.minX / spacing) * spacing
        let startY = floor(rect.minY / spacing) * spacing

        var x = startX
        while x <= rect.maxX + spacing {
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = startY
        while y <= rect.maxY + spacing {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        ctx.strokePath()
    }

    private func drawDots(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
        ctx.setFillColor(UIColor.gDot.cgColor)
        let startX = floor(rect.minX / spacing) * spacing
        let startY = floor(rect.minY / spacing) * spacing

        var x = startX
        while x <= rect.maxX + spacing {
            var y = startY
            while y <= rect.maxY + spacing {
                ctx.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                y += spacing
            }
            x += spacing
        }
    }

    private func drawLines(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
        ctx.setStrokeColor(UIColor.gGridLine.cgColor)
        ctx.setLineWidth(0.5)
        let startY = floor(rect.minY / spacing) * spacing

        var y = startY
        while y <= rect.maxY + spacing {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        ctx.strokePath()
    }

    private func drawIsometric(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
        ctx.setStrokeColor(UIColor.gGridLine.cgColor)
        ctx.setLineWidth(0.5)
        let h = spacing * 0.866
        let startY = floor(rect.minY / h) * h - rect.height

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
