import Foundation
import PencilKit

// MARK: - PencilKit Bridge

/// Handles conversion between PKDrawing and serialized data for persistence.
/// PKDrawing data is stored as `Data` (blob) in both GRDB and Supabase.
enum PencilKitBridge {

    // MARK: - Serialization

    /// Convert a PKDrawing to Data for storage
    static func serialize(_ drawing: PKDrawing) -> Data {
        drawing.dataRepresentation()
    }

    /// Restore a PKDrawing from stored Data
    static func deserialize(_ data: Data) -> PKDrawing? {
        try? PKDrawing(data: data)
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
        let image = renderImage(from: drawing, size: size)
        return image.pngData()
    }

    // MARK: - Tool Mapping

    /// Map GirokIQ DrawingTool enum to PencilKit PKInkingTool
    static func pkTool(
        for tool: DrawingTool,
        color: UIColor,
        width: CGFloat,
        penStyle: PKInkingTool.InkType = .pen,
        eraserType: PKEraserTool.EraserType = .bitmap
    ) -> PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(penStyle, color: color, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: color, width: width)
        case .marker:
            return PKInkingTool(.marker, color: color, width: width)
        case .eraser:
            return PKEraserTool(eraserType)
        case .lasso:
            return PKLassoTool()
        case .selection:
            return PKLassoTool()
        }
    }

    // MARK: - Empty Drawing

    /// A blank PKDrawing for new pages
    static var empty: PKDrawing {
        PKDrawing()
    }

    // MARK: - Web Stroke Conversion

    /// Convert an array of web-format strokes (JSON from `strokes_web` table)
    /// into a PKDrawing. Used when iOS fetches a page that has no `drawing_data`
    /// but has web strokes available.
    static func convertWebStrokes(_ webStrokes: [WebStroke]) -> PKDrawing {
        var pkStrokes: [PKStroke] = []

        for ws in webStrokes {
            guard ws.points.count >= 2 else { continue }

            let ink = PKInk(
                .pen,
                color: UIColor(hex: ws.color).withAlphaComponent(CGFloat(ws.opacity))
            )

            var controlPoints: [PKStrokePoint] = []
            for point in ws.points {
                let sp = PKStrokePoint(
                    location: CGPoint(x: point.x, y: point.y),
                    timeOffset: point.timeOffset,
                    size: CGSize(width: CGFloat(ws.width), height: CGFloat(ws.width)),
                    opacity: CGFloat(ws.opacity),
                    force: CGFloat(point.pressure),
                    azimuth: 0,
                    altitude: .pi / 2
                )
                controlPoints.append(sp)
            }

            let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
            let stroke = PKStroke(ink: ink, path: path)
            pkStrokes.append(stroke)
        }

        return PKDrawing(strokes: pkStrokes)
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
}

// MARK: - Web Stroke Models

/// Represents a stroke from the web app's `strokes_web` table.
/// The web app stores strokes as JSON arrays of points rather than PKDrawing binary.
struct WebStroke: Codable, Identifiable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    var color: String           // hex color e.g. "#6366F1"
    var width: Double
    var opacity: Double
    var tool: String            // "pen", "pencil", "marker"
    var points: [WebStrokePoint]
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case userId = "user_id"
        case color, width, opacity, tool, points
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A single point in a web stroke, with position, pressure, and time offset.
struct WebStrokePoint: Codable {
    var x: Double
    var y: Double
    var pressure: Double
    var timeOffset: TimeInterval
}
