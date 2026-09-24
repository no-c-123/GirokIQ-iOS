import Foundation
import PencilKit

// MARK: - Page (matches Supabase `pages` table)

struct Page: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let notebookId: UUID
    var title: String
    var pageIndex: Int
    var type: String            // "canvas" | "note"
    var settings: PageSettings?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case notebookId = "notebook_id"
        case title
        case pageIndex = "page_index"
        case type
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        notebookId: UUID,
        title: String = "Page",
        pageIndex: Int = 0,
        type: String = "canvas",
        settings: PageSettings? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.notebookId = notebookId
        self.title = title
        self.pageIndex = pageIndex
        self.type = type
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Restore a PKDrawing from stored settings data
    var pkDrawing: PKDrawing {
        guard let base64 = settings?.drawingData,
              let data = Data(base64Encoded: base64) else {
            return PKDrawing()
        }
        return PencilKitBridge.deserialize(data) ?? PKDrawing()
    }
}

// MARK: - Page Settings (jsonb column)

nonisolated struct PageSettings: Codable, Hashable {
    var backgroundPattern: String?   // "grid" | "dots" | "lines" | "blank" | "isometric"
    var zoomScale: Double?
    var drawingData: String?         // base64-encoded PKDrawing (iOS only)
    var elements: [CanvasElement]?   // Optional array of non-ink elements
}

// MARK: - Background Pattern (UI helper, not persisted directly)

enum BackgroundPattern: String, CaseIterable, Codable {
    case blank, grid, dots, lines, isometric

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .blank:     return "square"
        case .grid:      return "grid"
        case .dots:      return "circle.grid.3x3"
        case .lines:     return "line.horizontal.3"
        case .isometric: return "view.3d"
        }
    }
}

// MARK: - DrawingPage (local-only canvas representation)
// Used by CanvasViewModel for in-memory drawing state.
// Synced to/from `Page` + `PageSettings` for persistence.

struct DrawingPage: Identifiable {
    var id: UUID = UUID()
    var title: String = "Page"
    var strokes: [Stroke] = []
    var drawingData: Data?
    var backgroundPattern: BackgroundPattern = .grid
    var order: Int = 0
    var elements: [CanvasElement] = []

    var pkDrawing: PKDrawing {
        if let data = drawingData {
            return PencilKitBridge.deserialize(data) ?? PKDrawing()
        }
        return PKDrawing()
    }
}
