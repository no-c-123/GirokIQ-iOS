import Foundation

// MARK: - AI Message

struct AIMessage: Codable, Identifiable {
    let id: UUID
    let role: Role
    let content: String
    var imageData: Data?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, imageData: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.imageData = imageData
    }
}
