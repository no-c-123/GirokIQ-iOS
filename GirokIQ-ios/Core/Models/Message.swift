import Foundation

// MARK: - Message (matches Supabase `messages` table)

struct Message: Codable, Identifiable {
    let id: UUID
    let chatId: UUID
    var role: Role
    var content: String
    var tokenCount: Int?
    let createdAt: Date

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case role, content
        case tokenCount = "token_count"
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        chatId: UUID,
        role: Role,
        content: String,
        tokenCount: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.content = content
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }
}
