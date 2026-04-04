import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Remote Stroke (matches Supabase `strokes` table)

struct RemoteStroke: Codable, Identifiable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    var color: String
    var width: Double
    var points: Data            // bytea
    let createdAt: Date
    var updatedAt: Date
    var deleted: Bool
    var deviceId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case userId = "user_id"
        case color, width, points
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deleted
        case deviceId = "device_id"
    }
}

// MARK: - Local Stroke (in-memory drawing state for Core Graphics canvas)

/// In-memory representation of a stroke being drawn or displayed on the canvas.
/// This is a canvas-layer rendering model — it uses `Color` and `CGFloat` because
/// it's consumed exclusively by canvas drawing code (DrawingCanvasView, CanvasViewModel).
/// Not used for persistence; `RemoteStroke` is the sync/persistence model.
class Stroke: Identifiable {
    var id: UUID = UUID()
    var points: [StrokePoint] = []
    var color: Color
    var width: CGFloat
    var opacity: Double
    var style: StrokeStyle
    var tool: DrawingTool
    var isErased: Bool = false

    init(color: Color, width: CGFloat, opacity: Double, style: StrokeStyle, tool: DrawingTool) {
        self.color = color
        self.width = width
        self.opacity = opacity
        self.style = style
        self.tool = tool
    }

    /// Bounding box for lasso selection
    var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.location.x }
        let ys = points.map { $0.location.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Stroke Point

struct StrokePoint {
    var location: CGPoint
    var force: CGFloat
    var azimuth: CGFloat
    var altitude: CGFloat
    var timestamp: TimeInterval
}

// MARK: - Drawing Tool

enum DrawingTool: String, CaseIterable, Codable {
    case pen
    case pencil
    case marker
    case eraser
    case lasso
    case selection

    var icon: String {
        switch self {
        case .pen:       return "pencil.tip"
        case .pencil:    return "pencil"
        case .marker:    return "highlighter"
        case .eraser:    return "eraser"
        case .lasso:     return "lasso"
        case .selection: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var label: String {
        switch self {
        case .pen:       return "Pen"
        case .pencil:    return "Pencil"
        case .marker:    return "Marker"
        case .eraser:    return "Eraser"
        case .lasso:     return "Lasso"
        case .selection: return "Select"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen:       return 2.0
        case .pencil:    return 1.5
        case .marker:    return 8.0
        case .eraser:    return 20.0
        case .lasso:     return 1.0
        case .selection: return 1.0
        }
    }

    var defaultOpacity: Double {
        switch self {
        case .marker:  return 0.4
        default:       return 1.0
        }
    }
}

// MARK: - Stroke Style

enum StrokeStyle: String, CaseIterable {
    case solid, dashed, dotted

    var dashPattern: [CGFloat] {
        switch self {
        case .solid:  return []
        case .dashed: return [10, 5]
        case .dotted: return [2, 6]
        }
    }

    var icon: String {
        switch self {
        case .solid:  return "line.horizontal.3"
        case .dashed: return "line.3.horizontal.decrease"
        case .dotted: return "ellipsis"
        }
    }
}

// MARK: - Stroke Preset Colors

extension Color {
    static let strokePresets: [Color] = [
        Color(hex: "#FFFFFE"), // Off-white (prevents PencilKit auto-inversion)
        Color(hex: "#A78BFA"),
        Color(hex: "#60A5FA"),
        Color(hex: "#34D399"),
        Color(hex: "#FBBF24"),
        Color(hex: "#F87171"),
        Color(hex: "#FB923C"),
        Color(hex: "#22D3EE"),
        Color(hex: "#F472B6"),
        Color(hex: "#000001")  // Off-black (prevents PencilKit auto-inversion)
    ]
}
