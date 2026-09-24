import UIKit
import PencilKit

/// Renders a single "composite" representation of a page/region:
/// background pattern + PencilKit ink + canvas elements (text/images).
///
/// This is used for:
/// - PDF export (so PDFs include text + images, not just ink)
/// - Lasso "Screenshot" + "Ask AI" (so screenshots include selected blocks)
enum CanvasCompositeRenderer {
    struct RenderRequest {
        var drawing: PKDrawing
        var elements: [CanvasElement]
        /// Canvas-space rect to render (same coordinate space as element.positionX/Y).
        var canvasRect: CGRect
        var backgroundPattern: BackgroundPattern
        var backgroundColor: UIColor
        var includeBackgroundPattern: Bool = true
        var scale: CGFloat
        var padding: CGFloat
    }

    static func renderImage(_ request: RenderRequest) -> UIImage {
        let rect = request.canvasRect
        let paddedSize = CGSize(
            width: rect.width + request.padding * 2,
            height: rect.height + request.padding * 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        format.opaque = request.backgroundColor.cgColor.alpha >= 0.999

        let renderer = UIGraphicsImageRenderer(size: paddedSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Fill background (resolved dynamic color for correct dark/light appearance)
            let resolvedBackground = request.backgroundColor.resolvedColor(with: UITraitCollection.current)
            if resolvedBackground.cgColor.alpha > 0.001 {
                cg.setFillColor(resolvedBackground.cgColor)
                cg.fill(CGRect(origin: .zero, size: paddedSize))
            }

            // Translate so we can draw in canvas coordinates directly.
            // After this, the canvasRect's origin maps to (padding, padding) in image space.
            cg.saveGState()
            cg.translateBy(x: request.padding - rect.minX, y: request.padding - rect.minY)

            // Background pattern aligned to the global canvas coordinate system.
            if request.includeBackgroundPattern {
                drawPattern(
                    pattern: request.backgroundPattern,
                    in: rect,
                    backgroundColor: resolvedBackground,
                    context: cg
                )
            }

            // Ink (PencilKit)
            if !request.drawing.strokes.isEmpty {
                let inkImage = request.drawing.image(from: rect, scale: request.scale)
                inkImage.draw(in: rect)
            }

            // Elements
            let sortedElements = request.elements.sorted(by: { $0.zIndex < $1.zIndex })
            for element in sortedElements {
                drawElement(element, in: cg)
            }

            cg.restoreGState()
        }
    }

    // MARK: - Pattern

    private static func drawPattern(
        pattern: BackgroundPattern,
        in rect: CGRect,
        backgroundColor: UIColor,
        context ctx: CGContext
    ) {
        // Fill tile background
        ctx.setFillColor(backgroundColor.cgColor)
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

    private static func drawGrid(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
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

    private static func drawDots(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
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

    private static func drawLines(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
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

    private static func drawIsometric(in rect: CGRect, context ctx: CGContext, spacing: CGFloat) {
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

    // MARK: - Elements

    private static func drawElement(_ element: CanvasElement, in ctx: CGContext) {
        let w = CGFloat(element.width ?? 200)
        let h = CGFloat(element.height ?? 200)
        let rect = CGRect(x: element.positionX, y: element.positionY, width: w, height: h)

        ctx.saveGState()
        if element.rotation != 0 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: CGFloat(element.rotation))
            ctx.translateBy(x: -center.x, y: -center.y)
        }

        switch element.type {
        case "image":
            drawImageElement(element, rect: rect, in: ctx)
        case "text":
            drawTextElement(element, rect: rect, in: ctx)
        default:
            break
        }

        ctx.restoreGState()
    }

    private static func drawImageElement(_ element: CanvasElement, rect: CGRect, in ctx: CGContext) {
        guard let fileName = element.content, !fileName.isEmpty else { return }

        let image: UIImage?
        if let cached = ImageCache.shared.retrieve(for: fileName) {
            image = cached
        } else {
            let url = NotebookTransferSupport.localImageURL(for: fileName)
            image = UIImage(contentsOfFile: url.path)
            if let image { ImageCache.shared.store(image, for: fileName) }
        }

        guard let image else { return }

        // Match in-app behavior: aspect-fill + clip to element rect.
        ctx.saveGState()
        ctx.addRect(rect)
        ctx.clip()

        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return }

        let scale = max(rect.width / iw, rect.height / ih)
        let drawSize = CGSize(width: iw * scale, height: ih * scale)
        let drawOrigin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )
        image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        ctx.restoreGState()
    }

    private static func drawTextElement(_ element: CanvasElement, rect: CGRect, in ctx: CGContext) {
        guard let raw = element.content, !raw.isEmpty, raw != "\u{200B}" else { return }

        // Use the same insets as the on-canvas editor so PDF/screenshot matches the visible layout.
        let insets = TextElementMetrics.editorInsets
        let textRect = rect.inset(by: insets)

        let style = element.style
        let fontSize = CGFloat(style?.fontSize ?? 16)
        let textColor = UIColor(hex: style?.textColor) ?? UIColor.gTextPrimary

        var font: UIFont = .systemFont(ofSize: fontSize)
        if let name = style?.fontName, let namedFont = UIFont(name: name, size: fontSize) {
            font = namedFont
        } else {
            let weight: UIFont.Weight = (style?.isBold == true) ? .semibold : .regular
            font = .systemFont(ofSize: fontSize, weight: weight)
        }

        // Apply italic if requested
        if style?.isItalic == true {
            if let descriptor = font.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                font = UIFont(descriptor: descriptor, size: fontSize)
            }
        }

        let para = NSMutableParagraphStyle()
        para.lineSpacing = CGFloat(style?.lineSpacing ?? 0)
        switch style?.textAlignment {
        case "center": para.alignment = .center
        case "right": para.alignment = .right
        case "justified": para.alignment = .justified
        default: para.alignment = .left
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: para
        ]
        if style?.isUnderline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style?.isStrikethrough == true { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }

        let attributed = NSAttributedString(string: raw, attributes: attrs)

        // UIKit text drawing expects a flipped coordinate system; UIGraphicsImageRenderer is already correct.
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
}

private extension UIColor {
    convenience init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        if hex.count == 8 {
            a = CGFloat((value & 0xFF000000) >> 24) / 255.0
            r = CGFloat((value & 0x00FF0000) >> 16) / 255.0
            g = CGFloat((value & 0x0000FF00) >> 8) / 255.0
            b = CGFloat(value & 0x000000FF) / 255.0
        } else {
            a = 1.0
            r = CGFloat((value & 0xFF0000) >> 16) / 255.0
            g = CGFloat((value & 0x00FF00) >> 8) / 255.0
            b = CGFloat(value & 0x0000FF) / 255.0
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
