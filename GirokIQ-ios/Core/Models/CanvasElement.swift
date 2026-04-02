import Foundation

// MARK: - Canvas Element (matches Supabase `canvas_elements` table)

struct CanvasElement: Codable, Identifiable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    var type: String            // "text" | "image" | "shape" | "sticky"
    var content: String?        // rich text / markdown
    var positionX: Double
    var positionY: Double
    var width: Double?
    var height: Double?
    var rotation: Double
    var zIndex: Int
    var style: ElementStyle?    // jsonb
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case userId = "user_id"
        case type, content
        case positionX = "position_x"
        case positionY = "position_y"
        case width, height, rotation
        case zIndex = "z_index"
        case style
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        pageId: UUID,
        userId: UUID,
        type: String = "text",
        content: String? = nil,
        positionX: Double = 0,
        positionY: Double = 0,
        width: Double? = nil,
        height: Double? = nil,
        rotation: Double = 0,
        zIndex: Int = 0,
        style: ElementStyle? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pageId = pageId
        self.userId = userId
        self.type = type
        self.content = content
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
        self.style = style
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Element Style (jsonb column)

struct ElementStyle: Codable, Hashable {
    var backgroundColor: String?
    var borderColor: String?
    var borderWidth: Double?
    var fontSize: Double?
    var fontWeight: String?
    var textColor: String?
    var cornerRadius: Double?
    var opacity: Double?
}
