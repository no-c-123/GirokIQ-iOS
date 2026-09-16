import XCTest
@testable import GirokIQ_ios

/// The generator parses text coming back from a language model, which is
/// untrusted input: it can be wrapped in prose, fenced in Markdown, truncated
/// or simply wrong. These tests pin down what the parser accepts and rejects.
final class FlashcardsGeneratorParsingTests: XCTestCase {

    // MARK: - extractJSONData

    func testAcceptsACleanJSONObject() throws {
        let data = try FlashcardsGenerator.extractJSONData(from: #"{"questions":[]}"#)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["questions"])
    }

    func testAcceptsACleanJSONArray() throws {
        let data = try FlashcardsGenerator.extractJSONData(from: #"[{"id":1}]"#)
        let array = try JSONSerialization.jsonObject(with: data) as? [Any]
        XCTAssertEqual(array?.count, 1)
    }

    func testIgnoresSurroundingWhitespaceAndNewlines() throws {
        let data = try FlashcardsGenerator.extractJSONData(from: "\n\n  {\"questions\":[]}  \n")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testUnwrapsAMarkdownFencedCodeBlock() throws {
        let reply = """
        ```json
        {"questions":[{"question":"What is a mitochondrion?"}]}
        ```
        """
        let data = try FlashcardsGenerator.extractJSONData(from: reply)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let questions = object?["questions"] as? [[String: Any]]
        XCTAssertEqual(questions?.count, 1)
    }

    func testStripsConversationalProseAroundTheJSON() throws {
        let reply = """
        Sure! Here are the questions you asked for:
        {"questions":[{"question":"Define osmosis."}]}
        Let me know if you'd like more.
        """
        let data = try FlashcardsGenerator.extractJSONData(from: reply)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["questions"])
    }

    func testThrowsWhenThereIsNoJSONAtAll() {
        XCTAssertThrowsError(try FlashcardsGenerator.extractJSONData(from: "I can't help with that."))
    }

    func testThrowsOnEmptyInput() {
        XCTAssertThrowsError(try FlashcardsGenerator.extractJSONData(from: "   \n  "))
    }

    func testThrowsWhenTheClosingBraceIsMissing() {
        // A reply cut short by the token limit has an opening brace and no close.
        XCTAssertThrowsError(try FlashcardsGenerator.extractJSONData(from: #"Here: {"questions":[ "#))
    }

    // MARK: - sanitizeExtractedStudyText

    func testKeepsRealStudyText() {
        let text = "Osmosis is the movement of water across a semipermeable membrane."
        XCTAssertEqual(FlashcardsGenerator.sanitizeExtractedStudyText(text), text)
    }

    func testPreservesOriginalCasingAndPunctuationOfKeptText() {
        // Normalisation is only used for matching; the returned text is the
        // trimmed original, not the lowercased form.
        let text = "ATP  →  ADP + Pi"
        XCTAssertEqual(FlashcardsGenerator.sanitizeExtractedStudyText("  \(text)  "), text)
    }

    func testTreatsEmptyInputAsEmpty() {
        XCTAssertEqual(FlashcardsGenerator.sanitizeExtractedStudyText(""), "")
        XCTAssertEqual(FlashcardsGenerator.sanitizeExtractedStudyText("   \n  "), "")
    }

    func testDropsModelApologiesThatMeanThePageWasBlank() {
        let refusals = [
            "No readable text",
            "no legible text",
            "There is no visible text in this image.",
            "Nothing readable here",
            "nothing legible",
            "I am unable to read this page",
            "I can't read the handwriting",
            "cannot read",
            "The handwriting is illegible",
            "The image is too blurry",
            "too unclear",
            "empty response"
        ]
        for refusal in refusals {
            XCTAssertEqual(
                FlashcardsGenerator.sanitizeExtractedStudyText(refusal), "",
                "expected \"\(refusal)\" to be treated as no text"
            )
        }
    }

    func testDoesNotDropTextThatMerelyMentionsReading() {
        // "readable" appears, but this is genuine page content.
        let text = "Reading comprehension improves with spaced repetition."
        XCTAssertEqual(FlashcardsGenerator.sanitizeExtractedStudyText(text), text)
    }

    // MARK: - extractReadableText

    func testReadableTextIsEmptyWithoutElements() {
        XCTAssertEqual(FlashcardsGenerator.extractReadableText(fromPageElements: nil), "")
        XCTAssertEqual(FlashcardsGenerator.extractReadableText(fromPageElements: []), "")
    }

    func testReadableTextJoinsElementsWithABlankLine() {
        let elements = [
            Self.element(content: "First block"),
            Self.element(content: "Second block")
        ]
        XCTAssertEqual(
            FlashcardsGenerator.extractReadableText(fromPageElements: elements),
            "First block\n\nSecond block"
        )
    }

    func testReadableTextSkipsEmptyAndWhitespaceOnlyElements() {
        let elements = [
            Self.element(content: "Kept"),
            Self.element(content: "   "),
            Self.element(content: nil),
            Self.element(content: "\n\n"),
            Self.element(content: "  Also kept  ")
        ]
        XCTAssertEqual(
            FlashcardsGenerator.extractReadableText(fromPageElements: elements),
            "Kept\n\nAlso kept"
        )
    }

    // MARK: - Helpers

    private static func element(content: String?) -> CanvasElement {
        CanvasElement(
            pageId: UUID(),
            userId: UUID(),
            type: "text",
            content: content
        )
    }
}
