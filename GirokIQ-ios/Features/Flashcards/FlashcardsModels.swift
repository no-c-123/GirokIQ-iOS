import Foundation

// MARK: - Flashcards Session

enum FlashcardsMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case quiz
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiz: return "Quiz"
        case .focus: return "Focus"
        }
    }
}

enum FlashcardsQuestionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case multipleChoice = "multiple_choice"
    case openEnded = "open_ended"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .openEnded: return "Open Ended"
        }
    }
}

enum FlashcardsDifficulty: String, CaseIterable, Identifiable, Codable, Sendable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .easy: return "Direct recall of terms and definitions from your notes."
        case .medium: return "Questions that require understanding a concept, not just recalling it."
        case .hard: return "Applying and comparing ideas across several pages."
        }
    }
}

/// The single choice the learner actually makes on the configure screen.
/// `mode` + `questionType` are the persisted representation; this is the flat
/// three-way form the UI presents.
enum FlashcardsStudyMode: String, CaseIterable, Identifiable, Sendable {
    case multipleChoice
    case openEnded
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice: return "Multiple choice"
        case .openEnded: return "Open ended"
        case .focus: return "Focus"
        }
    }

    var blurb: String {
        switch self {
        case .multipleChoice: return "Four options per question, graded instantly."
        case .openEnded: return "Write the answer in your own words; graded on meaning."
        case .focus: return "Question on one side, answer on the other. You rate yourself."
        }
    }
}

struct FlashcardsSessionConfig: Hashable, Codable, Sendable {
    var mode: FlashcardsMode = .quiz
    var questionType: FlashcardsQuestionType = .multipleChoice
    var questionCount: Int = 10
    var difficulty: FlashcardsDifficulty = .medium
    var selectedPageIds: Set<UUID> = []

    /// Free-text preferences the learner writes before generating, e.g. "ask in
    /// English even though the notes are in Korean".
    var customInstructions: String = ""

    /// Upper bound on what is sent to the model. The instruction shares a token
    /// budget with the notes themselves, so an essay here would crowd out the
    /// material the questions are supposed to come from.
    static let customInstructionsLimit = 400

    /// The instruction as it should be sent: trimmed, capped, and empty when it
    /// carries nothing.
    var normalizedCustomInstructions: String {
        let trimmed = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(Self.customInstructionsLimit))
    }

    var hasCustomInstructions: Bool { !normalizedCustomInstructions.isEmpty }

    var canContinueFromSelection: Bool { !selectedPageIds.isEmpty }

    /// Flattens `mode` + `questionType` into the three-way UI choice.
    var studyMode: FlashcardsStudyMode {
        get {
            switch (mode, questionType) {
            case (.focus, _): return .focus
            case (.quiz, .multipleChoice): return .multipleChoice
            case (.quiz, .openEnded): return .openEnded
            }
        }
        set {
            switch newValue {
            case .multipleChoice:
                mode = .quiz
                questionType = .multipleChoice
            case .openEnded:
                mode = .quiz
                questionType = .openEnded
            case .focus:
                mode = .focus
            }
        }
    }

    init() {}

    /// Written by hand because Swift's synthesized decoder ignores a property's
    /// default value and throws `keyNotFound` instead. Sessions stored before
    /// `customInstructions` existed would fail to decode, and the caller's
    /// fallback would quietly reset the learner's mode and difficulty on resume.
    /// Every field is optional here so adding the next one cannot break the old
    /// rows either.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(FlashcardsMode.self, forKey: .mode) ?? .quiz
        questionType = try container.decodeIfPresent(FlashcardsQuestionType.self, forKey: .questionType) ?? .multipleChoice
        questionCount = try container.decodeIfPresent(Int.self, forKey: .questionCount) ?? 10
        difficulty = try container.decodeIfPresent(FlashcardsDifficulty.self, forKey: .difficulty) ?? .medium
        selectedPageIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedPageIds) ?? []
        customInstructions = try container.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
    }

    /// Rough minutes the session should take, for the setup summary line.
    var estimatedMinutes: Int {
        let perQuestion: Double
        switch studyMode {
        case .multipleChoice: perQuestion = 0.4
        case .openEnded: perQuestion = 1.1
        case .focus: perQuestion = 0.5
        }
        return max(1, Int((Double(questionCount) * perQuestion).rounded()))
    }
}

// MARK: - Page Preview

struct FlashcardsPageItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let index: Int
    let hasReadableText: Bool
}

// MARK: - Questions

enum FlashcardsQuestionKind: String, Codable, Sendable {
    case multipleChoice = "multiple_choice"
    case openEnded = "open_ended"
}

struct FlashcardsQuestion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var kind: FlashcardsQuestionKind
    var question: String

    // Multiple-choice
    var options: [String]?
    var correctIndex: Int?

    // Open-ended
    var expectedAnswer: String?

    // Explanation + attribution
    var explanation: String?
    var sourcePageId: UUID?
    var sourcePageTitle: String?
    var sourceQuote: String?
}

// MARK: - Editing

/// Edition of a generated set, kept as free functions over an array so the
/// rules can be tested without standing up a view model.
///
/// The learner reviews the questions before studying, and may fix a badly
/// worded one or drop it. Both operations happen on the question text only:
/// answers are never shown at review time, so they are never edited here.
enum FlashcardsQuestionEditor {

    /// Replaces a question's wording.
    ///
    /// Returns the array unchanged when the id is unknown or the new text is
    /// blank. Blank is rejected rather than accepted because a question with no
    /// text is unanswerable, and silently deleting it would not be what
    /// somebody clearing a field meant to do.
    static func edit(
        _ questions: [FlashcardsQuestion],
        id: UUID,
        newText: String
    ) -> [FlashcardsQuestion] {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = questions.firstIndex(where: { $0.id == id }) else {
            return questions
        }
        var updated = questions
        updated[index].question = trimmed
        return updated
    }

    /// Removes a question. Unknown ids are a no-op.
    static func delete(_ questions: [FlashcardsQuestion], id: UUID) -> [FlashcardsQuestion] {
        questions.filter { $0.id != id }
    }

    /// Whether a set can still be studied. An empty set cannot.
    static func canStudy(_ questions: [FlashcardsQuestion]) -> Bool {
        !questions.isEmpty
    }
}

// MARK: - Results

struct FlashcardsAnsweredQuestion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let question: FlashcardsQuestion
    let isCorrect: Bool
    let userAnswer: String?
    let feedback: String?
}

struct FlashcardsSessionResult: Hashable, Sendable {
    let total: Int
    let correct: Int
    let answered: [FlashcardsAnsweredQuestion]
    /// Wall-clock time the learner spent in the session.
    var elapsed: TimeInterval = 0
    var config: FlashcardsSessionConfig = FlashcardsSessionConfig()

    var scorePercent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(correct) / Double(total)) * 100.0)
    }

    var missed: [FlashcardsAnsweredQuestion] {
        answered.filter { !$0.isCorrect }
    }

    var incorrect: Int { max(total - correct, 0) }

    /// "6:41" — minutes and seconds, matching the results stat tile.
    var elapsedText: String {
        let total = max(Int(elapsed.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Distinct source pages behind the missed questions, for "Topics to review".
    var reviewTopics: [String] {
        var seen = Set<String>()
        var topics: [String] = []
        for item in missed {
            guard let title = item.question.sourcePageTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, !seen.contains(title) else { continue }
            seen.insert(title)
            topics.append(title)
        }
        return topics
    }
}

// MARK: - Focus Rating (SM-2 signal)

enum FlashcardsSelfRating: Int, CaseIterable, Identifiable, Sendable {
    // SM-2 quality scale is 0..5. We map to four UI buttons.
    case again = 1
    case hard = 3
    case good = 4
    case easy = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}
