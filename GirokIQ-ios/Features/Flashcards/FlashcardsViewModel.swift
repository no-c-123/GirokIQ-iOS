import Foundation
import SwiftUI
import Combine

@MainActor
final class FlashcardsViewModel: ObservableObject {
    enum Screen: Equatable {
        case selectContent
        case configure
        /// Between generation and studying: the learner reads the questions,
        /// fixes the wording of any that came out badly and drops the ones that
        /// are not worth answering. Answers are deliberately not shown here.
        case reviewQuestions
        case quiz
        case focus
        case results(FlashcardsSessionResult)
        case reviewMistakes(FlashcardsSessionResult)
        case error(title: String, message: String)
    }

    enum PreparationState: Equatable {
        case idle
        case generating
        case ready
        case failed(String)
    }

    // MARK: - Published

    @Published var screen: Screen = .selectContent
    @Published var pages: [FlashcardsPageItem] = []
    @Published var isLoadingPages: Bool = false

    @Published var config = FlashcardsSessionConfig()
    @Published var preparationState: PreparationState = .idle

    @Published var questions: [FlashcardsQuestion] = []
    @Published var currentQuestionIndex: Int = 0

    // Quiz UI state
    @Published var selectedOptionIndex: Int? = nil
    @Published var hasSubmittedAnswer: Bool = false
    @Published var openEndedAnswerText: String = ""
    @Published var openEndedFeedback: String? = nil
    @Published var isGradingOpenEnded: Bool = false

    // Focus UI state
    @Published var focusRevealed: Bool = false

    /// Most recently deleted question during review, for a single-step undo.
    @Published var lastDeleted: (question: FlashcardsQuestion, index: Int)? = nil

    /// Per-question outcome, mirrored from `answered` so the navigator strip and
    /// the results pips can observe it.
    @Published private(set) var outcomes: [UUID: Bool] = [:]

    // MARK: - Dependencies

    private let notebook: Notebook
    private let userId: UUID?
    private let localDatabase: LocalDatabase
    private let generator: FlashcardsGenerator

    // MARK: - Session

    private var answered: [FlashcardsAnsweredQuestion] = []
    private var sessionRecordID: UUID?
    private var sessionCreatedAt: Date?
    private var studyStartedAt: Date?

    init(
        notebook: Notebook,
        userId: UUID?,
        localDatabase: LocalDatabase? = nil,
        generator: FlashcardsGenerator? = nil
    ) {
        self.notebook = notebook
        self.userId = userId
        self.localDatabase = localDatabase ?? .shared
        self.generator = generator ?? FlashcardsGenerator()
    }

    var notebookName: String { notebook.name }

    var currentQuestion: FlashcardsQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    var canContinueFromSelection: Bool {
        config.canContinueFromSelection
    }

    // MARK: - Lifecycle

    func load() async {
        await loadPages()
        await resumeIfPossible()
    }

    func loadPages() async {
        isLoadingPages = true
        defer { isLoadingPages = false }

        do {
            let tuples = try await localDatabase.fetchPages(notebookId: notebook.id)
            let items: [FlashcardsPageItem] = tuples.enumerated().map { idx, tuple in
                let elements = tuple.page.settings?.elements
                let extracted = FlashcardsGenerator.extractReadableText(fromPageElements: elements)
                let hasInk = (tuple.drawingData?.isEmpty == false)
                let hasImageElements = (elements ?? []).contains(where: { $0.type == "image" })
                return FlashcardsPageItem(
                    id: tuple.page.id,
                    title: tuple.page.title.isEmpty ? "Page \(tuple.page.pageIndex + 1)" : tuple.page.title,
                    index: tuple.page.pageIndex,
                    hasReadableText: !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasInk || hasImageElements
                )
            }
            pages = items

            // Default selection: all pages (but allow user to deselect).
            if config.selectedPageIds.isEmpty {
                config.selectedPageIds = Set(items.map(\.id))
            }
        } catch {
            screen = .error(
                title: "Couldn’t Load Pages",
                message: "Flashcards couldn’t read this notebook’s pages. Try again."
            )
        }
    }

    // MARK: - Navigation

    func goToConfigure() {
        guard canContinueFromSelection else { return }
        screen = .configure
    }

    func goBackToSelection() {
        screen = .selectContent
    }

    // MARK: - Generation

    func startSession() async {
        guard let userId else {
            screen = .error(
                title: "Not Signed In",
                message: "Flashcards needs an authenticated session to generate questions."
            )
            return
        }

        preparationState = .generating
        answered = []
        outcomes = [:]
        questions = []
        currentQuestionIndex = 0
        resetPerQuestionUIState()

        do {
            let tuples = try await localDatabase.fetchPages(notebookId: notebook.id)
            let selectedTuples = tuples.filter { config.selectedPageIds.contains($0.page.id) }
            let selected = try await buildStudyMaterials(from: selectedTuples)

            let readableCount = selected.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            guard readableCount > 0 else {
                preparationState = .failed("The selected pages don’t contain readable notes yet. Add more legible content, then try again.")
                return
            }

            let generated = try await generator.generateQuestions(
                notebookName: notebook.name,
                pages: selected,
                config: config
            )

            guard !generated.isEmpty else {
                preparationState = .failed("Flashcards couldn’t find enough study material on the selected pages. Try pages with clearer handwriting or more visible notes.")
                return
            }

            questions = generated
            currentQuestionIndex = 0
            resetPerQuestionUIState()
            let session = FlashcardsSessionRecord(
                userId: userId,
                notebookId: notebook.id,
                status: .active,
                config: config,
                questions: generated,
                answers: answered,
                currentQuestionIndex: currentQuestionIndex
            )
            sessionRecordID = session.id
            sessionCreatedAt = session.createdAt
            try? await localDatabase.saveFlashcardsSession(session)
            preparationState = .ready
        } catch {
            preparationState = .failed(Self.describe(error))
        }
    }

    /// The generic "try again" message hid timeouts, expired sessions, rate
    /// limits and truncated replies behind identical copy. Say which it was.
    static func describe(_ error: Error) -> String {
        if AIError.isTimeout(error) {
            return "The request timed out while reading your notes. Pages with a lot of handwriting take longer — try selecting fewer pages, or ask for fewer questions."
        }
        if let aiError = error as? AIError {
            switch aiError {
            case .unauthorized:
                return "Your session expired. Sign out and back in, then try again."
            case .apiError(let code, let message) where code == 429:
                return message.isEmpty ? "The AI service is rate limited right now. Wait a moment and try again." : message
            case .apiError(let code, let message):
                return "The AI service returned an error (\(code)). \(message)"
            case .invalidResponse:
                return "The AI service sent a response Flashcards couldn’t read."
            case .noAPIKey:
                return "The AI service isn’t configured."
            }
        }
        if let generatorError = error as? FlashcardsGeneratorError {
            return generatorError.errorDescription ?? "Flashcards couldn’t build questions from this reply."
        }
        if let urlError = error as? URLError {
            return "Network problem while reading your notes (\(urlError.code.rawValue)). Check your connection and try again."
        }
        return "Flashcards couldn’t create questions right now. \(error.localizedDescription)"
    }

    /// Generation finished: show the questions for review instead of dropping
    /// the learner straight into the first one.
    func beginQuestionReview() {
        preparationState = .idle
        screen = .reviewQuestions
    }

    func beginPreparedSession() {
        preparationState = .idle
        guard FlashcardsQuestionEditor.canStudy(questions) else {
            // Everything was deleted during review; there is nothing to study.
            screen = .configure
            return
        }
        // The clock starts when studying starts, not when the questions were
        // generated, so time spent reviewing does not count against the learner.
        studyStartedAt = Date()
        currentQuestionIndex = 0
        resetPerQuestionUIState()
        if config.mode == .focus {
            screen = .focus
        } else {
            screen = .quiz
        }
    }

    // MARK: - Review editing

    var canStartStudying: Bool { FlashcardsQuestionEditor.canStudy(questions) }

    /// Rewrites a question as the learner types. Blank text is rejected, so
    /// clearing the field leaves the original wording rather than producing an
    /// unanswerable card.
    ///
    /// In memory only: persisting on every keystroke would mean a database
    /// write per character. `commitReviewEdits()` stores the result.
    func updateQuestionText(id: UUID, to newText: String) {
        questions = FlashcardsQuestionEditor.edit(questions, id: id, newText: newText)
    }

    /// Writes the reviewed set to storage. Called when a field loses focus and
    /// when leaving the review screen.
    func commitReviewEdits() {
        persistReviewedQuestions()
    }

    func deleteQuestion(id: UUID) {
        guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
        // Kept so a mistaken tap can be undone; deleting a question the model
        // took thirty seconds to write is not worth losing to a slip.
        lastDeleted = (question: questions[index], index: index)
        questions = FlashcardsQuestionEditor.delete(questions, id: id)
        persistReviewedQuestions()
    }

    func undoDelete() {
        guard let pending = lastDeleted else { return }
        var restored = questions
        restored.insert(pending.question, at: min(pending.index, restored.count))
        questions = restored
        lastDeleted = nil
        persistReviewedQuestions()
    }

    func discardUndo() { lastDeleted = nil }

    /// Keeps the stored session in step with the edits, so a learner who leaves
    /// mid-review comes back to the set they curated, not the generated one.
    private func persistReviewedQuestions() {
        guard let userId, let sessionRecordID else { return }
        let record = FlashcardsSessionRecord(
            id: sessionRecordID,
            userId: userId,
            notebookId: notebook.id,
            status: .active,
            config: config,
            questions: questions,
            answers: answered,
            currentQuestionIndex: 0,
            createdAt: sessionCreatedAt ?? Date(),
            updatedAt: Date()
        )
        Task { [localDatabase] in
            try? await localDatabase.saveFlashcardsSession(record)
        }
    }

    func dismissPreparationModal() {
        preparationState = .idle
    }

    // MARK: - Quiz actions

    func submitMultipleChoice(optionIndex: Int) {
        guard let q = currentQuestion, q.kind == .multipleChoice else { return }
        guard !hasSubmittedAnswer else { return }

        selectedOptionIndex = optionIndex
        hasSubmittedAnswer = true

        let isCorrect = optionIndex == q.correctIndex
        record(FlashcardsAnsweredQuestion(
            id: q.id,
            question: q,
            isCorrect: isCorrect,
            userAnswer: q.options?[safe: optionIndex],
            feedback: nil
        ))
        Task { await persistProgressIfNeeded() }
    }

    func submitOpenEnded() async {
        guard let q = currentQuestion, q.kind == .openEnded else { return }
        let trimmed = openEndedAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !hasSubmittedAnswer else { return }

        hasSubmittedAnswer = true
        isGradingOpenEnded = true
        openEndedFeedback = nil
        defer { isGradingOpenEnded = false }

        do {
            let result = try await generator.gradeOpenEnded(question: q, userAnswer: trimmed)
            openEndedFeedback = result.feedback
            record(FlashcardsAnsweredQuestion(
                id: q.id,
                question: q,
                isCorrect: result.isCorrect,
                userAnswer: trimmed,
                feedback: result.feedback
            ))
        } catch {
            openEndedFeedback = "Couldn’t grade this answer right now."
            record(FlashcardsAnsweredQuestion(
                id: q.id,
                question: q,
                isCorrect: false,
                userAnswer: trimmed,
                feedback: openEndedFeedback
            ))
        }
        await persistProgressIfNeeded()
    }

    func nextQuestionOrFinish() {
        guard currentQuestionIndex < questions.count else { return }

        if currentQuestionIndex == questions.count - 1 {
            finishSession()
            return
        }

        currentQuestionIndex += 1
        // `restore` rather than `reset`: the learner may have stepped back
        // through the navigator, so the next question can already be answered.
        restoreQuestionUIState()
        Task { await persistProgressIfNeeded() }
    }

    // MARK: - Focus actions

    func focusReveal() {
        focusRevealed = true
    }

    func focusRateAndAdvance(_ rating: FlashcardsSelfRating) {
        // For v1: capture rating as part of the session, and move on.
        _ = rating
        if focusRevealed == false {
            focusRevealed = true
            return
        }

        guard let q = currentQuestion else { return }
        record(FlashcardsAnsweredQuestion(
            id: q.id,
            question: q,
            isCorrect: rating.rawValue >= FlashcardsSelfRating.good.rawValue,
            userAnswer: nil,
            feedback: rating.title
        ))

        if currentQuestionIndex == questions.count - 1 {
            finishSession()
        } else {
            currentQuestionIndex += 1
            focusRevealed = false
            Task { await persistProgressIfNeeded() }
        }
    }

    // MARK: - Results

    func finishSession() {
        let total = questions.count
        let correct = answered.filter(\.isCorrect).count
        let result = FlashcardsSessionResult(
            total: total,
            correct: correct,
            answered: answered,
            elapsed: Date().timeIntervalSince(studyStartedAt ?? Date()),
            config: config
        )
        studyStartedAt = nil
        screen = .results(result)
        Task { await markSessionCompleted() }
    }

    func showMistakes(from result: FlashcardsSessionResult) {
        screen = .reviewMistakes(result)
    }

    func restartCurrentSession() {
        guard !questions.isEmpty else {
            screen = .configure
            return
        }

        answered = []
        outcomes = [:]
        currentQuestionIndex = 0
        studyStartedAt = Date()
        resetPerQuestionUIState()

        if config.mode == .focus {
            screen = .focus
        } else {
            screen = .quiz
        }

        Task { await persistProgressIfNeeded() }
    }

    func retryFromError() {
        screen = .selectContent
        preparationState = .idle
    }

    // MARK: - Session map

    /// Outcome of every question in the session, in order — drives the
    /// navigator strip under the quiz and the pips on the results screen.
    var questionPips: [FQuestionNavigator.Pip] {
        questions.enumerated().map { index, question -> FQuestionNavigator.Pip in
            if let correct = outcomes[question.id] {
                return correct ? .correct : .incorrect
            }
            return index == currentQuestionIndex ? .current : .upcoming
        }
    }

    var answeredCount: Int { outcomes.count }

    /// Jumps back to a question that has already been answered, restoring the
    /// revealed state. Forward jumps are refused so questions stay in order.
    func goToQuestion(_ index: Int) {
        guard questions.indices.contains(index) else { return }
        guard index != currentQuestionIndex else { return }
        guard outcomes[questions[index].id] != nil else { return }
        currentQuestionIndex = index
        restoreQuestionUIState()
    }

    // MARK: - Focus browsing

    var canFocusGoBack: Bool { currentQuestionIndex > 0 }
    var canFocusGoForward: Bool { currentQuestionIndex < questions.count - 1 }

    func focusGoBack() {
        guard canFocusGoBack else { return }
        currentQuestionIndex -= 1
        focusRevealed = false
        Task { await persistProgressIfNeeded() }
    }

    func focusGoForward() {
        guard canFocusGoForward else { return }
        currentQuestionIndex += 1
        focusRevealed = false
        Task { await persistProgressIfNeeded() }
    }

    // MARK: - Post-session actions

    /// Re-runs only the questions the learner missed, as a fresh short session.
    func retryMissed(from result: FlashcardsSessionResult) {
        let missedQuestions = result.missed.map(\.question)
        guard !missedQuestions.isEmpty else { return }

        questions = missedQuestions
        answered = []
        outcomes = [:]
        currentQuestionIndex = 0
        studyStartedAt = Date()
        resetPerQuestionUIState()
        screen = config.mode == .focus ? .focus : .quiz
        Task { await persistProgressIfNeeded() }
    }

    /// Returns to setup so a brand-new batch can be generated from the same pages.
    func generateNewQuestions() {
        questions = []
        answered = []
        outcomes = [:]
        currentQuestionIndex = 0
        studyStartedAt = nil
        resetPerQuestionUIState()
        preparationState = .idle
        screen = .configure
    }

    /// Ends the run early and scores whatever was answered.
    func endSessionEarly() {
        guard !answered.isEmpty else { return }
        let correct = answered.filter(\.isCorrect).count
        let result = FlashcardsSessionResult(
            total: answered.count,
            correct: correct,
            answered: answered,
            elapsed: Date().timeIntervalSince(studyStartedAt ?? Date()),
            config: config
        )
        studyStartedAt = nil
        screen = .results(result)
        Task { await markSessionCompleted() }
    }

    // MARK: - Private

    private func record(_ answer: FlashcardsAnsweredQuestion) {
        if let existing = answered.firstIndex(where: { $0.question.id == answer.question.id }) {
            answered[existing] = answer
        } else {
            answered.append(answer)
        }
        outcomes[answer.question.id] = answer.isCorrect
    }

    private func resumeIfPossible() async {
        guard let userId else { return }
        guard let session = try? await localDatabase.fetchActiveFlashcardsSession(userId: userId, notebookId: notebook.id) else { return }
        guard !session.questions.isEmpty else { return }

        sessionRecordID = session.id
        sessionCreatedAt = session.createdAt
        config = session.config
        questions = session.questions
        answered = session.answers
        outcomes = Dictionary(session.answers.map { ($0.question.id, $0.isCorrect) }, uniquingKeysWith: { _, last in last })
        currentQuestionIndex = min(session.currentQuestionIndex, max(session.questions.count - 1, 0))
        studyStartedAt = Date()
        restoreQuestionUIState()

        if config.mode == .focus {
            screen = .focus
        } else {
            screen = .quiz
        }
    }

    private func resetPerQuestionUIState() {
        selectedOptionIndex = nil
        hasSubmittedAnswer = false
        openEndedAnswerText = ""
        openEndedFeedback = nil
        isGradingOpenEnded = false
        focusRevealed = false
    }

    private func restoreQuestionUIState() {
        resetPerQuestionUIState()
        guard let currentQuestion else { return }
        guard let existingAnswer = answered.first(where: { $0.question.id == currentQuestion.id }) else { return }

        hasSubmittedAnswer = true
        openEndedFeedback = existingAnswer.feedback

        if currentQuestion.kind == .multipleChoice {
            selectedOptionIndex = currentQuestion.options?.firstIndex(of: existingAnswer.userAnswer ?? "")
        } else {
            openEndedAnswerText = existingAnswer.userAnswer ?? ""
        }
    }

    /// Reads the selected pages concurrently.
    ///
    /// This used to run one page at a time, and each page costs one or two vision
    /// calls carrying a multi-megabyte image — so a twelve-page notebook spent
    /// several minutes in a serial chain before the real generation call had even
    /// started. Concurrency is capped so a large notebook doesn't open twenty
    /// simultaneous uploads.
    private func buildStudyMaterials(
        from tuples: [(page: Page, drawingData: Data?)]
    ) async throws -> [(pageId: UUID, title: String, text: String)] {
        let ordered = tuples.sorted(by: { $0.page.pageIndex < $1.page.pageIndex })
        let maxConcurrent = 3

        var byIndex: [Int: (pageId: UUID, title: String, text: String)] = [:]

        try await withThrowingTaskGroup(of: (Int, (pageId: UUID, title: String, text: String)).self) { group in
            var next = 0

            func addTask(_ index: Int) {
                let tuple = ordered[index]
                group.addTask { [weak self] in
                    guard let self else {
                        return (index, (pageId: tuple.page.id, title: "", text: ""))
                    }
                    let material = await self.studyMaterial(for: tuple)
                    return (index, material)
                }
            }

            while next < ordered.count && next < maxConcurrent {
                addTask(next)
                next += 1
            }

            while let (index, material) = try await group.next() {
                byIndex[index] = material
                if next < ordered.count {
                    addTask(next)
                    next += 1
                }
            }
        }

        return ordered.indices.compactMap { byIndex[$0] }
    }

    /// Extracts the study text for a single page. Vision failures degrade to the
    /// typed text rather than failing the whole session.
    private func studyMaterial(
        for tuple: (page: Page, drawingData: Data?)
    ) async -> (pageId: UUID, title: String, text: String) {
        let page = tuple.page
        let title = page.title.isEmpty ? "Page \(page.pageIndex + 1)" : page.title

        let typedText = FlashcardsGenerator
            .extractReadableText(fromPageElements: page.settings?.elements)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let hasInk = tuple.drawingData?.isEmpty == false
        let hasImageElements = (page.settings?.elements ?? []).contains(where: { $0.type == "image" })
        let imageData = FlashcardsGenerator.renderCompositePageImageData(
            notebook: notebook,
            page: page,
            drawingData: tuple.drawingData
        )

        var visionText = ""
        if let imageData {
            visionText = (try? await generator.extractStudyTextFromPageImage(
                imageData: imageData,
                pageTitle: title
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if visionText.isEmpty, hasInk || hasImageElements {
                visionText = (try? await generator.extractFallbackStudySignalsFromPageImage(
                    imageData: imageData,
                    pageTitle: title
                ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }

        return (
            pageId: page.id,
            title: title,
            text: composeStudyMaterial(visionText: visionText, typedText: typedText)
        )
    }

    private func composeStudyMaterial(visionText: String, typedText: String) -> String {
        let normalizedVision = visionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTyped = typedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedVision.isEmpty, normalizedTyped.isEmpty {
            return ""
        }

        if normalizedVision.isEmpty {
            return """
            Page reading:
            \(normalizedTyped)
            """
        }

        if normalizedTyped.isEmpty {
            return """
            Page reading:
            \(normalizedVision)
            """
        }

        if normalizedVision.caseInsensitiveCompare(normalizedTyped) == .orderedSame ||
            normalizedVision.contains(normalizedTyped) {
            return """
            Page reading:
            \(normalizedVision)
            """
        }

        return """
        Page reading:
        \(normalizedVision)

        Canvas text fields:
        \(normalizedTyped)
        """
    }

    private func persistProgressIfNeeded() async {
        guard let userId else { return }
        guard let sessionRecordID else { return }
        guard let sessionCreatedAt else { return }

        let session = FlashcardsSessionRecord(
            id: sessionRecordID,
            userId: userId,
            notebookId: notebook.id,
            status: .active,
            config: config,
            questions: questions,
            answers: answered,
            currentQuestionIndex: currentQuestionIndex,
            createdAt: sessionCreatedAt,
            updatedAt: Date()
        )
        try? await localDatabase.saveFlashcardsSession(session)
    }

    private func markSessionCompleted() async {
        guard let userId else { return }
        guard let sessionRecordID else { return }
        guard let sessionCreatedAt else { return }

        let now = Date()
        let session = FlashcardsSessionRecord(
            id: sessionRecordID,
            userId: userId,
            notebookId: notebook.id,
            status: .completed,
            config: config,
            questions: questions,
            answers: answered,
            currentQuestionIndex: currentQuestionIndex,
            createdAt: sessionCreatedAt,
            updatedAt: now,
            completedAt: now
        )
        try? await localDatabase.saveFlashcardsSession(session)
    }
}

// MARK: - Safe Indexing

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
