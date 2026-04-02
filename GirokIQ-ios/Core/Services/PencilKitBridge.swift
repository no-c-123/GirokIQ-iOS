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
        width: CGFloat
    ) -> PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(.pen, color: color, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: color, width: width)
        case .marker:
            return PKInkingTool(.marker, color: color, width: width)
        case .eraser:
            return PKEraserTool(.bitmap)
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
}
