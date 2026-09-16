import Foundation

enum FlashcardsSessionStatus: String, Codable, Sendable {
    case active
    case completed
}

struct FlashcardsSessionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let notebookId: UUID
    var status: FlashcardsSessionStatus
    var config: FlashcardsSessionConfig
    var questions: [FlashcardsQuestion]
    var answers: [FlashcardsAnsweredQuestion]
    var currentQuestionIndex: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        userId: UUID,
        notebookId: UUID,
        status: FlashcardsSessionStatus = .active,
        config: FlashcardsSessionConfig,
        questions: [FlashcardsQuestion],
        answers: [FlashcardsAnsweredQuestion] = [],
        currentQuestionIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.notebookId = notebookId
        self.status = status
        self.config = config
        self.questions = questions
        self.answers = answers
        self.currentQuestionIndex = currentQuestionIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

