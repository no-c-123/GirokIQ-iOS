import Foundation

// MARK: - App State (matches Supabase `app_state` table)

struct AppState: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    var lastNotebookId: UUID?
    var lastPageId: UUID?
    var preferences: UserPreferences?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastNotebookId = "last_notebook_id"
        case lastPageId = "last_page_id"
        case preferences
        case updatedAt = "updated_at"
    }

    init(
        userId: UUID,
        lastNotebookId: UUID? = nil,
        lastPageId: UUID? = nil,
        preferences: UserPreferences? = nil,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.lastNotebookId = lastNotebookId
        self.lastPageId = lastPageId
        self.preferences = preferences
        self.updatedAt = updatedAt
    }
}

// MARK: - User Preferences (jsonb column)

struct UserPreferences: Codable, Hashable {
    var theme: String?
    var defaultPattern: String?
    var fingerDrawing: Bool?
    var palmRejection: Bool?
    var autoSync: Bool?
}
