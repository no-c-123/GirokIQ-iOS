import Foundation

// MARK: - Notebook

struct Notebook: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var folderId: UUID?
    var name: String
    var canvasType: String          // "infinite" | "fixed" — default "infinite"
    var pageDimensions: PageDimensions?  // only set when canvasType == "fixed"
    var backgroundPattern: String       // "blank" | "grid" | "dots" | "lines" | "isometric" — default "blank"
    var backgroundColorHex: String      // hex string — default "#0F0F0E"

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case folderId = "folder_id"
        case name
        case canvasType = "canvas_type"
        case pageDimensions = "page_dimensions"
        case backgroundPattern = "background_pattern"
        case backgroundColorHex = "background_color_hex"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        folderId: UUID? = nil,
        name: String = "Untitled",
        canvasType: String = "infinite",
        pageDimensions: PageDimensions? = nil,
        backgroundPattern: String = "blank",
        backgroundColorHex: String = "#0F0F0E",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.folderId = folderId
        self.name = name
        self.canvasType = canvasType
        self.pageDimensions = pageDimensions
        self.backgroundPattern = backgroundPattern
        self.backgroundColorHex = backgroundColorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Page Dimensions

struct PageDimensions: Codable, Hashable {
    var widthPt: Double    // points (1pt = 1/72 inch)
    var heightPt: Double

    // A4 in points at 72dpi
    static let a4 = PageDimensions(widthPt: 595, heightPt: 842)
    // US Letter
    static let letter = PageDimensions(widthPt: 612, heightPt: 792)
    // A5
    static let a5 = PageDimensions(widthPt: 420, heightPt: 595)

    /// Pixel size at a given scale factor (e.g. 2.0 for Retina)
    func pixelSize(scale: CGFloat = 2) -> CGSize {
        CGSize(width: widthPt * scale, height: heightPt * scale)
    }
}

// MARK: - Folder

struct Folder: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var parentId: UUID?
    var name: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case parentId = "parent_id"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        parentId: UUID? = nil,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.parentId = parentId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
