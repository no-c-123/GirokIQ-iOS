import XCTest
@testable import GirokIQ_ios

/// The learner reviews the generated questions before studying and may rewrite
/// or delete them. These are the rules of that edit, kept as pure functions so
/// they can be verified without a view model.
final class FlashcardsQuestionEditorTests: XCTestCase {

    private func question(_ text: String, id: UUID = UUID()) -> FlashcardsQuestion {
        FlashcardsQuestion(
            id: id,
            kind: .multipleChoice,
            question: text,
            options: ["a", "b", "c", "d"],
            correctIndex: 0,
            expectedAnswer: nil,
            explanation: "because",
            sourcePageId: UUID(),
            sourcePageTitle: "Page 1",
            sourceQuote: nil
        )
    }

    // MARK: - Editing

    func testEditingRewritesOnlyTheTargetQuestion() {
        let target = UUID()
        let questions = [question("first"), question("second", id: target), question("third")]

        let edited = FlashcardsQuestionEditor.edit(questions, id: target, newText: "rewritten")

        XCTAssertEqual(edited.map(\.question), ["first", "rewritten", "third"])
    }

    func testEditingTrimsSurroundingWhitespace() {
        let target = UUID()
        let edited = FlashcardsQuestionEditor.edit(
            [question("old", id: target)], id: target, newText: "  tidy  \n"
        )
        XCTAssertEqual(edited.first?.question, "tidy")
    }

    func testBlankTextLeavesTheQuestionUntouched() {
        // Clearing the field must not produce an unanswerable card, and must
        // not be read as a request to delete it either.
        let target = UUID()
        let original = [question("keep me", id: target)]

        for blank in ["", "   ", "\n\t "] {
            let edited = FlashcardsQuestionEditor.edit(original, id: target, newText: blank)
            XCTAssertEqual(edited.first?.question, "keep me", "\"\(blank)\" should be rejected")
            XCTAssertEqual(edited.count, 1)
        }
    }

    func testEditingAnUnknownIdChangesNothing() {
        let questions = [question("first"), question("second")]
        let edited = FlashcardsQuestionEditor.edit(questions, id: UUID(), newText: "ignored")
        XCTAssertEqual(edited.map(\.question), ["first", "second"])
    }

    func testEditingPreservesTheAnswerAndAttribution() {
        // Review shows the question only; the answer must survive the edit
        // untouched or the quiz would grade against nothing.
        let target = UUID()
        let original = question("old", id: target)
        let edited = FlashcardsQuestionEditor.edit([original], id: target, newText: "new")

        XCTAssertEqual(edited.first?.options, original.options)
        XCTAssertEqual(edited.first?.correctIndex, original.correctIndex)
        XCTAssertEqual(edited.first?.explanation, original.explanation)
        XCTAssertEqual(edited.first?.sourcePageId, original.sourcePageId)
        XCTAssertEqual(edited.first?.id, target)
    }

    // MARK: - Deleting

    func testDeletingRemovesOnlyThatQuestion() {
        let target = UUID()
        let questions = [question("first"), question("second", id: target), question("third")]

        let remaining = FlashcardsQuestionEditor.delete(questions, id: target)

        XCTAssertEqual(remaining.map(\.question), ["first", "third"])
    }

    func testDeletingAnUnknownIdChangesNothing() {
        let questions = [question("first"), question("second")]
        XCTAssertEqual(FlashcardsQuestionEditor.delete(questions, id: UUID()).count, 2)
    }

    func testDeletingEveryQuestionYieldsAnEmptySet() {
        var questions = [question("first"), question("second")]
        for q in questions { questions = FlashcardsQuestionEditor.delete(questions, id: q.id) }
        XCTAssertTrue(questions.isEmpty)
    }

    // MARK: - Study guard

    func testAnEmptySetCannotBeStudied() {
        XCTAssertFalse(FlashcardsQuestionEditor.canStudy([]))
    }

    func testASetWithOneQuestionCanBeStudied() {
        XCTAssertTrue(FlashcardsQuestionEditor.canStudy([question("only one")]))
    }
}

/// Free-text guidance the learner writes before generating.
final class FlashcardsCustomInstructionsTests: XCTestCase {

    func testEmptyByDefault() {
        let config = FlashcardsSessionConfig()
        XCTAssertEqual(config.customInstructions, "")
        XCTAssertFalse(config.hasCustomInstructions)
        XCTAssertEqual(config.normalizedCustomInstructions, "")
    }

    func testWhitespaceOnlyCountsAsAbsent() {
        // Otherwise a stray space would add an empty preferences block to the
        // prompt and spend tokens saying nothing.
        var config = FlashcardsSessionConfig()
        config.customInstructions = "   \n\t "
        XCTAssertFalse(config.hasCustomInstructions)
        XCTAssertEqual(config.normalizedCustomInstructions, "")
    }

    func testInstructionsAreTrimmed() {
        var config = FlashcardsSessionConfig()
        config.customInstructions = "  Ask in English  "
        XCTAssertEqual(config.normalizedCustomInstructions, "Ask in English")
        XCTAssertTrue(config.hasCustomInstructions)
    }

    func testInstructionsAreCappedInLength() {
        // The instruction shares a token budget with the notes; an essay here
        // would crowd out the material the questions come from.
        var config = FlashcardsSessionConfig()
        config.customInstructions = String(repeating: "a", count: 1000)

        XCTAssertEqual(
            config.normalizedCustomInstructions.count,
            FlashcardsSessionConfig.customInstructionsLimit
        )
    }

    func testInstructionsSurviveACodableRoundTrip() throws {
        var config = FlashcardsSessionConfig()
        config.customInstructions = "No Korean script in the questions"
        config.difficulty = .hard

        let decoded = try JSONDecoder().decode(
            FlashcardsSessionConfig.self, from: try JSONEncoder().encode(config)
        )

        XCTAssertEqual(decoded.customInstructions, "No Korean script in the questions")
        XCTAssertEqual(decoded.difficulty, .hard)
    }

    func testASessionStoredBeforeThisFieldExistedStillDecodes() throws {
        // Swift's synthesized decoder ignores default values and throws
        // keyNotFound, which would have reset the learner's mode and difficulty
        // on resume. The hand-written decoder is what prevents that.
        let legacy = """
        {
          "mode": "quiz",
          "questionType": "open_ended",
          "questionCount": 20,
          "difficulty": "hard",
          "selectedPageIds": []
        }
        """

        let config = try JSONDecoder().decode(
            FlashcardsSessionConfig.self, from: Data(legacy.utf8)
        )

        XCTAssertEqual(config.questionType, .openEnded)
        XCTAssertEqual(config.questionCount, 20)
        XCTAssertEqual(config.difficulty, .hard)
        XCTAssertEqual(config.customInstructions, "")
    }

    func testACompletelyEmptyObjectDecodesToDefaults() throws {
        let config = try JSONDecoder().decode(
            FlashcardsSessionConfig.self, from: Data("{}".utf8)
        )
        XCTAssertEqual(config.mode, .quiz)
        XCTAssertEqual(config.questionCount, 10)
        XCTAssertEqual(config.difficulty, .medium)
        XCTAssertTrue(config.selectedPageIds.isEmpty)
    }
}

/// Adding questions to a set that is already under review.
final class FlashcardsQuestionAdditionTests: XCTestCase {

    private func question(_ text: String, id: UUID = UUID()) -> FlashcardsQuestion {
        FlashcardsQuestion(
            id: id, kind: .openEnded, question: text,
            options: nil, correctIndex: nil, expectedAnswer: "answer",
            explanation: nil, sourcePageId: nil, sourcePageTitle: nil, sourceQuote: nil
        )
    }

    // MARK: - Count

    func testTheRequestedCountIsClampedToTheSupportedRange() {
        // The UI offers 1 to 3; anything else would be a caller bug, and
        // clamping is cheaper than trusting it.
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(0), 1)
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(-5), 1)
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(1), 1)
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(2), 2)
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(3), 3)
        XCTAssertEqual(FlashcardsQuestionEditor.clampAdditionCount(50), 3)
    }

    // MARK: - Appending

    func testAdditionsGoToTheEndOfTheSet() {
        let existing = [question("first"), question("second")]
        let merged = FlashcardsQuestionEditor.append([question("third")], to: existing)
        XCTAssertEqual(merged.map(\.question), ["first", "second", "third"])
    }

    func testAQuestionWithAnExistingIdIsRejected() {
        // The model is told not to reuse ids. It is told, not forced.
        let shared = UUID()
        let existing = [question("first", id: shared)]
        let merged = FlashcardsQuestionEditor.append([question("different wording", id: shared)], to: existing)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.question, "first")
    }

    func testAQuestionThatRepeatsExistingTextIsRejected() {
        // Being asked the same thing twice in one session is the failure this
        // prevents, and a fresh id would otherwise sail straight past.
        let existing = [question("What is osmosis?")]
        let merged = FlashcardsQuestionEditor.append([question("What is osmosis?")], to: existing)
        XCTAssertEqual(merged.count, 1)
    }

    func testDuplicateDetectionIgnoresCaseAndSurroundingWhitespace() {
        let existing = [question("What is osmosis?")]
        let merged = FlashcardsQuestionEditor.append(
            [question("  what is OSMOSIS?  ")], to: existing
        )
        XCTAssertEqual(merged.count, 1)
    }

    func testDuplicatesWithinTheSameBatchAreCollapsed() {
        let merged = FlashcardsQuestionEditor.append(
            [question("Repeated"), question("Repeated"), question("Unique")],
            to: []
        )
        XCTAssertEqual(merged.map(\.question), ["Repeated", "Unique"])
    }

    func testBlankQuestionsAreNeverAdded() {
        let merged = FlashcardsQuestionEditor.append(
            [question("   "), question(""), question("Real one")],
            to: []
        )
        XCTAssertEqual(merged.map(\.question), ["Real one"])
    }

    func testAppendingNothingLeavesTheSetUnchanged() {
        let existing = [question("first")]
        XCTAssertEqual(FlashcardsQuestionEditor.append([], to: existing).count, 1)
    }

    func testAdditionsPreserveTheirAnswers() {
        // The added question has to be gradeable, which is the whole reason the
        // model is asked to supply an answer even for a verbatim question.
        let addition = question("Added")
        let merged = FlashcardsQuestionEditor.append([addition], to: [])
        XCTAssertEqual(merged.first?.expectedAnswer, "answer")
    }
}
