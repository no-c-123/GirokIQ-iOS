import Foundation

// MARK: - Chat (matches Supabase `chats` table)

struct Chat: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var notebookId: UUID?
    var title: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case notebookId = "notebook_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        notebookId: UUID? = nil,
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.notebookId = notebookId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
