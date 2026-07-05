import Foundation
import PencilKit

// MARK: - PencilKit Bridge

/// Handles conversion between PKDrawing and serialized data for persistence.
/// PKDrawing data is stored as `Data` (blob) in both GRDB and Supabase.
enum PencilKitBridge {
    private static let maxVisionPixels: CGFloat = 1_500

    // MARK: - Serialization

    /// Convert a PKDrawing to Data for storage
    nonisolated static func serialize(_ drawing: PKDrawing) -> Data {
        drawing.dataRepresentation()
    }

    /// Restore a PKDrawing from stored Data
    nonisolated static func deserialize(_ data: Data) -> PKDrawing? {
        try? PKDrawing(data: data)
    }

    /// Compress serialized drawing data before writing it to disk.
    nonisolated static func compressForPersistence(_ data: Data) throws -> Data {
        let compressed = try (data as NSData).compressed(using: .lzfse)
        return compressed as Data
    }

    /// Restore persisted drawing bytes back to the raw PKDrawing payload.
    nonisolated static func decompressForPersistence(_ data: Data) throws -> Data {
        let decompressed = try (data as NSData).decompressed(using: .lzfse)
        return decompressed as Data
    }

    // MARK: - Image Export

    /// Render a PKDrawing to a UIImage (for thumbnails, AI vision, PDF export)
    static func renderImage(
        from drawing: PKDrawing,
        size: CGSize = CGSize(width: 1024, height: 768),
        scale: CGFloat = 2.0
    ) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        return drawing.image(from: bounds, scale: scale)
    }

    /// Render a PKDrawing to PNG Data (for AI vision requests)
    static func renderPNGData(
        from drawing: PKDrawing,
        size: CGSize = CGSize(width: 1024, height: 768)
    ) -> Data? {
        // If drawing has strokes, render their actual bounding box
        // expanded with padding so nothing gets clipped.
        // Fall back to the fixed size only for empty drawings.
        let bounds: CGRect
        if drawing.strokes.isEmpty {
            bounds = CGRect(origin: .zero, size: size)
        } else {
            let strokeBounds = drawing.bounds
            let padding: CGFloat = 40
            bounds = strokeBounds.insetBy(dx: -padding, dy: -padding)
        }

        let image = drawing.image(
            from: bounds,
            scale: boundedRenderScale(for: bounds.size, maxPixelDimension: maxVisionPixels)
        )
        return image.pngData()
    }

    nonisolated static func boundedRenderScale(
        for size: CGSize,
        maxPixelDimension: CGFloat
    ) -> CGFloat {
        let maxDimension = max(size.width, size.height)
        guard maxDimension.isFinite, maxDimension > 0 else { return 1.0 }
        return min(1.0, maxPixelDimension / maxDimension)
    }

    // MARK: - Tool Mapping

    /// Map GirokIQ DrawingTool enum to PencilKit PKInkingTool
    static func pkTool(
        for tool: DrawingTool,
        color: UIColor,
        width: CGFloat,
        penStyle: PKInkingTool.InkType = .pen,
        eraserType: PKEraserTool.EraserType = .fixedWidthBitmap
    ) -> PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(penStyle, color: color, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: color, width: width)
        case .marker:
            return PKInkingTool(.marker, color: color, width: width)
        case .eraser:
            return PKEraserTool(eraserType, width: width)
        case .selection:
            return PKLassoTool()
        case .lasso, .image, .text:
            // Native lasso replaced by custom gesture — return neutral tool
            // so PKCanvasView does not intercept touches when lasso is active
            return PKInkingTool(.pen, color: .clear, width: 1)
        }
    }

    // MARK: - Empty Drawing

    /// A blank PKDrawing for new pages
    static var empty: PKDrawing {
        PKDrawing()
    }

    // MARK: - PDF Export

    /// Render an array of PKDrawings (one per page) to a single PDF Data object.
    /// Each page is rendered at the given size with the drawing centered.
    static func renderPDF(
        from drawings: [PKDrawing],
        pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { pdfContext in
            for drawing in drawings {
                pdfContext.beginPage()

                let drawingBounds = drawing.bounds
                if drawingBounds.isEmpty {
                    // Blank page — just begin and end
                    continue
                }

                // Scale drawing to fit within page with margins
                let margin: CGFloat = 36 // 0.5 inch
                let availableSize = CGSize(
                    width: pageSize.width - margin * 2,
                    height: pageSize.height - margin * 2
                )
                let scaleX = availableSize.width / drawingBounds.width
                let scaleY = availableSize.height / drawingBounds.height
                let scale = min(scaleX, scaleY, 1.0) // Don't scale up

                let scaledWidth = drawingBounds.width * scale
                let scaledHeight = drawingBounds.height * scale
                let offsetX = margin + (availableSize.width - scaledWidth) / 2
                let offsetY = margin + (availableSize.height - scaledHeight) / 2

                let image = drawing.image(from: drawingBounds, scale: 2.0)
                let destRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
                image.draw(in: destRect)
            }
        }
    }

    /// Render an array of UIImages (one per page) to a single PDF Data object.
    /// Used for composite exports where text/images must be included.
    static func renderPDF(
        from images: [UIImage],
        pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { pdfContext in
            for image in images {
                let iw = image.size.width
                let ih = image.size.height
                guard iw > 0, ih > 0 else { continue }

                let pageRect = CGRect(origin: .zero, size: CGSize(width: iw, height: ih))
                pdfContext.beginPage(withBounds: pageRect, pageInfo: [:])
                image.draw(in: pageRect)
            }
        }
    }
}
