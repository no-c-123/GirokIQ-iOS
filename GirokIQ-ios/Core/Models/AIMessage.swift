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

    init(role: Role, content: String, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.imageData = imageData
    }
}
