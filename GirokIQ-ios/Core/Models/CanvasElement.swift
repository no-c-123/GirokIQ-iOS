import Foundation

// MARK: - Canvas Element (matches Supabase `canvas_elements` table)

struct CanvasElement: Codable, Identifiable, Hashable, Equatable {
    let id: UUID
    let pageId: UUID
    let userId: UUID
    var type: String            // "image" | "shape" | "sticky"
    var content: String?        // rich text / markdown
    var positionX: Double
    var positionY: Double
    var width: Double?
    var height: Double?
    var rotation: Double
    var zIndex: Int
    var style: ElementStyle?    // jsonb
    var userResized: Bool
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
        case userResized = "user_resized"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pageId = try container.decode(UUID.self, forKey: .pageId)
        userId = try container.decode(UUID.self, forKey: .userId)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        positionX = try container.decode(Double.self, forKey: .positionX)
        positionY = try container.decode(Double.self, forKey: .positionY)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        style = try container.decodeIfPresent(ElementStyle.self, forKey: .style)
        userResized = try container.decodeIfPresent(Bool.self, forKey: .userResized) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pageId, forKey: .pageId)
        try container.encode(userId, forKey: .userId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encode(userResized, forKey: .userResized)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(
        id: UUID = UUID(),
        pageId: UUID,
        userId: UUID,
        type: String = "image",
        content: String? = nil,
        positionX: Double = 0,
        positionY: Double = 0,
        width: Double? = nil,
        height: Double? = nil,
        rotation: Double = 0,
        zIndex: Int = 0,
        style: ElementStyle? = nil,
        userResized: Bool = false,
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
        self.userResized = userResized
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
    var fontName: String?        // nil = system font
    var textColor: String?
    var lineSpacing: Double?     // extra line spacing in points; nil = default
    var textAlignment: String?   // "left" | "center" | "right" | "justified"
    var isBold: Bool?
    var isItalic: Bool?
    var isUnderline: Bool?
    var isStrikethrough: Bool?
    var cornerRadius: Double?
    var opacity: Double?
}
