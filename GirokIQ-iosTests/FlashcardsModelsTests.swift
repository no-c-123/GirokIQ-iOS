import XCTest
@testable import GirokIQ_ios

/// Covers the pure value types behind the flashcards flow: the setup config,
/// the session result and the self-rating scale.
final class FlashcardsModelsTests: XCTestCase {

    // MARK: - FlashcardsSessionConfig.studyMode

    func testStudyModeFlattensModeAndQuestionType() {
        var config = FlashcardsSessionConfig()

        config.mode = .quiz
        config.questionType = .multipleChoice
        XCTAssertEqual(config.studyMode, .multipleChoice)

        config.questionType = .openEnded
        XCTAssertEqual(config.studyMode, .openEnded)

        // Focus wins regardless of the question type left behind.
        config.mode = .focus
        XCTAssertEqual(config.studyMode, .focus)
        config.questionType = .multipleChoice
        XCTAssertEqual(config.studyMode, .focus)
    }

    func testSettingStudyModeWritesBackModeAndQuestionType() {
        var config = FlashcardsSessionConfig()

        config.studyMode = .openEnded
        XCTAssertEqual(config.mode, .quiz)
        XCTAssertEqual(config.questionType, .openEnded)

        config.studyMode = .focus
        XCTAssertEqual(config.mode, .focus)

        config.studyMode = .multipleChoice
        XCTAssertEqual(config.mode, .quiz)
        XCTAssertEqual(config.questionType, .multipleChoice)
    }

    func testStudyModeRoundTripsThroughEveryCase() {
        for mode in FlashcardsStudyMode.allCases {
            var config = FlashcardsSessionConfig()
            config.studyMode = mode
            XCTAssertEqual(config.studyMode, mode, "\(mode) did not survive the round trip")
        }
    }

    // MARK: - Estimates and gating

    func testEstimatedMinutesNeverDropsBelowOne() {
        var config = FlashcardsSessionConfig()
        config.questionCount = 1
        config.studyMode = .multipleChoice
        // 1 * 0.4 rounds to 0, which must still be reported as a minute.
        XCTAssertEqual(config.estimatedMinutes, 1)
    }

    func testEstimatedMinutesScalesWithQuestionCountAndMode() {
        var config = FlashcardsSessionConfig()
        config.questionCount = 10

        config.studyMode = .multipleChoice
        XCTAssertEqual(config.estimatedMinutes, 4)

        config.studyMode = .openEnded
        XCTAssertEqual(config.estimatedMinutes, 11)

        config.studyMode = .focus
        XCTAssertEqual(config.estimatedMinutes, 5)
    }

    func testCanContinueOnlyWithAtLeastOnePageSelected() {
        var config = FlashcardsSessionConfig()
        XCTAssertFalse(config.canContinueFromSelection)

        config.selectedPageIds = [UUID()]
        XCTAssertTrue(config.canContinueFromSelection)

        config.selectedPageIds = []
        XCTAssertFalse(config.canContinueFromSelection)
    }

    func testConfigSurvivesCodableRoundTrip() throws {
        var config = FlashcardsSessionConfig()
        config.studyMode = .openEnded
        config.questionCount = 7
        config.difficulty = .hard
        config.selectedPageIds = [UUID(), UUID()]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FlashcardsSessionConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    // MARK: - FlashcardsSessionResult

    func testScorePercentIsZeroWhenNothingWasAsked() {
        let result = FlashcardsSessionResult(total: 0, correct: 0, answered: [])
        // Guards the divide-by-zero path rather than the arithmetic.
        XCTAssertEqual(result.scorePercent, 0)
    }

    func testScorePercentTruncatesTowardZero() {
        // 2/3 = 66.67% must report 66, not 67.
        let result = FlashcardsSessionResult(total: 3, correct: 2, answered: [])
        XCTAssertEqual(result.scorePercent, 66)

        XCTAssertEqual(FlashcardsSessionResult(total: 4, correct: 4, answered: []).scorePercent, 100)
        XCTAssertEqual(FlashcardsSessionResult(total: 4, correct: 0, answered: []).scorePercent, 0)
    }

    func testIncorrectNeverGoesNegative() {
        // A correct count above the total would otherwise underflow the label.
        let result = FlashcardsSessionResult(total: 2, correct: 5, answered: [])
        XCTAssertEqual(result.incorrect, 0)
    }

    func testMissedReturnsOnlyIncorrectAnswers() {
        let answered = [
            Self.answer(correct: true, pageTitle: "Page 1"),
            Self.answer(correct: false, pageTitle: "Page 2"),
            Self.answer(correct: false, pageTitle: "Page 3")
        ]
        let result = FlashcardsSessionResult(total: 3, correct: 1, answered: answered)

        XCTAssertEqual(result.missed.count, 2)
        XCTAssertTrue(result.missed.allSatisfy { !$0.isCorrect })
    }

    func testElapsedTextFormatsMinutesAndSeconds() {
        func text(_ seconds: TimeInterval) -> String {
            FlashcardsSessionResult(total: 1, correct: 1, answered: [], elapsed: seconds).elapsedText
        }

        XCTAssertEqual(text(0), "0:00")
        XCTAssertEqual(text(9), "0:09")
        XCTAssertEqual(text(60), "1:00")
        XCTAssertEqual(text(401), "6:41")
        // Rounds rather than truncates.
        XCTAssertEqual(text(59.6), "1:00")
        // Negative elapsed time is clamped instead of formatting as "-1:-1".
        XCTAssertEqual(text(-30), "0:00")
    }

    func testReviewTopicsDedupesTrimsAndSkipsBlanks() {
        let answered = [
            Self.answer(correct: false, pageTitle: "Photosynthesis"),
            Self.answer(correct: false, pageTitle: "  Photosynthesis  "),  // same topic, padded
            Self.answer(correct: false, pageTitle: "   "),                 // blank after trimming
            Self.answer(correct: false, pageTitle: nil),                   // no attribution
            Self.answer(correct: false, pageTitle: "Cell Division"),
            Self.answer(correct: true, pageTitle: "Mitosis")               // answered correctly
        ]
        let result = FlashcardsSessionResult(total: 6, correct: 1, answered: answered)

        XCTAssertEqual(result.reviewTopics, ["Photosynthesis", "Cell Division"])
    }

    func testReviewTopicsIsEmptyForAPerfectScore() {
        let answered = [Self.answer(correct: true, pageTitle: "Page 1")]
        let result = FlashcardsSessionResult(total: 1, correct: 1, answered: answered)

        XCTAssertTrue(result.reviewTopics.isEmpty)
    }

    // MARK: - Self rating

    func testSelfRatingMapsOntoTheSM2QualityScale() {
        XCTAssertEqual(FlashcardsSelfRating.again.rawValue, 1)
        XCTAssertEqual(FlashcardsSelfRating.hard.rawValue, 3)
        XCTAssertEqual(FlashcardsSelfRating.good.rawValue, 4)
        XCTAssertEqual(FlashcardsSelfRating.easy.rawValue, 5)
        XCTAssertEqual(FlashcardsSelfRating.allCases.count, 4)
    }

    func testDisplayTitlesAreNonEmpty() {
        for mode in FlashcardsStudyMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.blurb.isEmpty)
        }
        for difficulty in FlashcardsDifficulty.allCases {
            XCTAssertFalse(difficulty.title.isEmpty)
            XCTAssertFalse(difficulty.blurb.isEmpty)
        }
        for rating in FlashcardsSelfRating.allCases {
            XCTAssertFalse(rating.title.isEmpty)
        }
        for mode in FlashcardsMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
        }
        for type in FlashcardsQuestionType.allCases {
            XCTAssertFalse(type.title.isEmpty)
        }
    }

    // MARK: - Helpers

    private static func answer(correct: Bool, pageTitle: String?) -> FlashcardsAnsweredQuestion {
        let question = FlashcardsQuestion(
            id: UUID(),
            kind: .multipleChoice,
            question: "Q",
            options: ["a", "b", "c", "d"],
            correctIndex: 0,
            expectedAnswer: nil,
            explanation: nil,
            sourcePageId: UUID(),
            sourcePageTitle: pageTitle,
            sourceQuote: nil
        )
        return FlashcardsAnsweredQuestion(
            id: UUID(),
            question: question,
            isCorrect: correct,
            userAnswer: "a",
            feedback: nil
        )
    }
}
