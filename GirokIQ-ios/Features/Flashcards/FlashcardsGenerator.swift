import Foundation
import UIKit
import PencilKit

// MARK: - Flashcards Generator

/// Generates quiz questions from notebook pages using the existing `AIService` (Supabase edge function).
/// IMPORTANT: This module reads page content only. It never writes back to the notebook/canvas.
final class FlashcardsGenerator {
    private let aiService: AIService

    init(aiService: AIService = AIService()) {
        self.aiService = aiService
    }

    // MARK: - Public

    func generateQuestions(
        notebookName: String,
        pages: [(pageId: UUID, title: String, text: String)],
        config: FlashcardsSessionConfig
    ) async throws -> [FlashcardsQuestion] {
        let trimmedPages = pages
            .map { (pageId: $0.pageId, title: $0.title, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let pagePayload = trimmedPages
            .map { page in
                """
                ---
                page_id: \(page.pageId.uuidString)
                title: \(page.title)
                notes:
                \(page.text.isEmpty ? "[NO_READABLE_TEXT]" : page.text)
                """
            }
            .joined(separator: "\n")

        let systemPrompt = """
        You are GirokIQ Flashcards, an AI that generates quizzes from the user's notebook pages.
        Rules:
        - Use ONLY the provided notes. Do not invent facts.
        - If the notes are insufficient, ask fewer questions rather than hallucinating.
        - Prefer broad study coverage across the selected pages and concepts.
        - Do not generate many near-duplicate questions from one sentence or one text block if the page set contains other usable material.
        - When multiple concepts exist on a page, spread questions across them.
        - If the notes only support a smaller set of distinct questions than requested, return fewer questions.
        - Return STRICT JSON only (no markdown, no commentary).
        """

        let userPrompt = """
        Create a flashcards session for the notebook "\(notebookName)".

        SETTINGS:
        - mode: \(config.mode.rawValue)
        - question_type: \(config.questionType.rawValue)
        - difficulty: \(config.difficulty.rawValue)
        - question_count: \(config.questionCount)

        NOTES BY PAGE:
        \(pagePayload)

        Output JSON schema:
        {
          "questions": [
            {
              "id": "<uuid>",
              "kind": "multiple_choice" | "open_ended",
              "question": "<string>",
              "options": ["A","B","C","D"],              // required when kind == multiple_choice
              "correct_index": 0,                       // required when kind == multiple_choice
              "expected_answer": "<string>",            // required when kind == open_ended
              "explanation": "<string>",
              "source_page_id": "<uuid from notes>",
              "source_page_title": "<string>",
              "source_quote": "<short quote from notes>"
            }
          ]
        }

        Constraints:
        - "id" must be a UUID (any valid UUID is fine).
        - "source_page_id" must be one of the provided page_id values.
        - Keep options short and plausible. Exactly 4 options for multiple-choice.
        - Keep explanations calm and brief.
        - Favor one question per distinct concept before creating a second question from the same concept.
        - Use the page attribution carefully so the user can review where each question came from.
        - Never pad the output with repetitive variants of the same fact just to reach the requested count.
        """

        // Each question carries a prompt, four options, an explanation, a quote and
        // two ids — roughly 300 tokens. A flat 4096 truncates the JSON mid-object
        // on larger sessions, and the decode then fails for no visible reason.
        let budget = min(16_000, 1_200 + config.questionCount * 320)

        let response = try await withTimeoutRetry {
            try await self.aiService.complete(
                systemPrompt: systemPrompt,
                messages: [AIMessage(role: .user, content: userPrompt)],
                maxTokens: budget
            )
        }

        let data = try Self.extractJSONData(from: response)
        do {
            let decoded = try JSONDecoder().decode(FlashcardsAIResponse.self, from: data)
            return decoded.questions.map { $0.toDomain() }
        } catch {
            // A truncated reply is the common cause here and reads very
            // differently from "the model refused", so name it.
            throw FlashcardsGeneratorError.malformedQuestions(underlying: error)
        }
    }

    /// Retries once on a network timeout. Generation is a single expensive call;
    /// losing the whole session to one slow response is worth one more attempt.
    private func withTimeoutRetry<T>(_ operation: () async throws -> T) async rethrows -> T {
        do {
            return try await operation()
        } catch {
            guard AIError.isTimeout(error) else { throw error }
            return try await operation()
        }
    }

    func gradeOpenEnded(
        question: FlashcardsQuestion,
        userAnswer: String
    ) async throws -> (isCorrect: Bool, feedback: String) {
        let expected = question.expectedAnswer ?? ""
        let systemPrompt = """
        You are GirokIQ Flashcards Grader.
        Return STRICT JSON only.
        """

        let userPrompt = """
        Grade the user's answer against the expected answer.

        QUESTION:
        \(question.question)

        EXPECTED ANSWER:
        \(expected)

        USER ANSWER:
        \(userAnswer)

        Output JSON schema:
        { "is_correct": true|false, "feedback": "<one short sentence>" }

        Rules:
        - Be strict but fair.
        - Feedback should be calm and helpful (no exclamation points).
        """

        let response = try await aiService.complete(
            systemPrompt: systemPrompt,
            messages: [AIMessage(role: .user, content: userPrompt)]
        )

        let data = try Self.extractJSONData(from: response)
        let decoded = try JSONDecoder().decode(FlashcardsGradeResponse.self, from: data)
        return (decoded.isCorrect, decoded.feedback)
    }

    func extractStudyTextFromPageImage(
        imageData: Data,
        pageTitle: String
    ) async throws -> String {
        let systemPrompt = """
        You read notebook pages and extract study material from handwriting, diagrams, symbols, arrows, formulas, and typed notes.
        Return plain text only.
        Do not invent missing content.
        """

        let userPrompt = """
        Read this notebook page titled "\(pageTitle)".

        Tasks:
        - Treat handwriting and drawn strokes as the PRIMARY source of meaning on the page.
        - Transcribe the most legible handwritten or typed content.
        - Capture labels, arrows, groupings, formulas, numbered steps, and diagram relationships when visible.
        - Preserve key terms, definitions, formulas, and bullet-like structure.
        - If some text is unclear, keep any partial but useful concept instead of dropping the whole idea.
        - If the page contains mostly drawings or diagrams, describe the study-relevant relationships in plain text.
        - Keep the result concise but useful for quiz generation.
        """

        let response = try await aiService.complete(
            systemPrompt: systemPrompt,
            messages: [AIMessage(role: .user, content: userPrompt, imageData: imageData)]
        )

        return Self.sanitizeExtractedStudyText(response)
    }

    func extractFallbackStudySignalsFromPageImage(
        imageData: Data,
        pageTitle: String
    ) async throws -> String {
        let systemPrompt = """
        You read handwritten notebook pages and recover the most useful study signals even when the handwriting is difficult.
        Return plain text only.
        Do not invent facts or wording that is not supported by the image.
        """

        let userPrompt = """
        Inspect this notebook page titled "\(pageTitle)".

        Output a short study outline using only what is visible.

        Tasks:
        - List the clearest concepts, terms, formulas, labels, and relationships visible on the page.
        - Use short bullet-like lines.
        - If a word is partially legible, include the partial concept only when it is still useful.
        - Mention diagram structure, arrows, or grouped regions when they communicate meaning.
        - If almost nothing is readable, return an empty response.
        """

        let response = try await aiService.complete(
            systemPrompt: systemPrompt,
            messages: [AIMessage(role: .user, content: userPrompt, imageData: imageData)]
        )

        return Self.sanitizeExtractedStudyText(response)
    }

    // MARK: - Text extraction helpers

    static func extractReadableText(fromPageElements elements: [CanvasElement]?) -> String {
        guard let elements, !elements.isEmpty else { return "" }

        let chunks = elements
            .compactMap { $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Keep separators stable so the model can infer structure.
        return chunks.joined(separator: "\n\n")
    }

    static func renderCompositePageImageData(
        notebook: Notebook,
        page: Page,
        drawingData: Data?
    ) -> Data? {
        let drawing = drawingData.flatMap(PencilKitBridge.deserialize) ?? PKDrawing()
        let elements = page.settings?.elements ?? []
        let rect = pageRenderRect(notebook: notebook, drawing: drawing, elements: elements)
        let backgroundPattern = BackgroundPattern(rawValue: page.settings?.backgroundPattern ?? notebook.backgroundPattern) ?? .blank

        let request = CanvasCompositeRenderer.RenderRequest(
            drawing: drawing,
            elements: elements,
            canvasRect: rect,
            backgroundPattern: backgroundPattern,
            backgroundColor: UIColor(hex: notebook.backgroundColorHex) ?? .gBackground,
            scale: PencilKitBridge.boundedRenderScale(for: rect.size, maxPixelDimension: 1800),
            padding: notebook.canvasType == "fixed" ? 0 : 36
        )

        let image = CanvasCompositeRenderer.renderImage(request)
        return visionSafeImageData(from: image)
    }

    private static func pageRenderRect(notebook: Notebook, drawing: PKDrawing, elements: [CanvasElement]) -> CGRect {
        if notebook.canvasType == "fixed", let dims = notebook.pageDimensions {
            return CGRect(origin: .zero, size: CGSize(width: dims.widthPt, height: dims.heightPt))
        }

        var content = drawing.bounds
        for element in elements {
            let rect = CGRect(
                x: element.positionX,
                y: element.positionY,
                width: CGFloat(element.width ?? 200),
                height: CGFloat(element.height ?? 200)
            )
            content = (content.isNull || content.isEmpty) ? rect : content.union(rect)
        }

        if content.isNull || content.isEmpty {
            return CGRect(origin: .zero, size: CGSize(width: 612, height: 792))
        }

        return content
    }

    private static func visionSafeImageData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 4096
        let targetByteCount = 3_500_000

        func resizedImage(from source: UIImage, maxDimension: CGFloat) -> UIImage {
            let pixelWidth = CGFloat(source.cgImage?.width ?? Int(source.size.width * source.scale))
            let pixelHeight = CGFloat(source.cgImage?.height ?? Int(source.size.height * source.scale))
            let largestDimension = Swift.max(pixelWidth, pixelHeight)
            guard largestDimension > maxDimension else { return source }

            let scale = maxDimension / largestDimension
            let resizedSize = CGSize(
                width: Swift.max(1, floor(pixelWidth * scale)),
                height: Swift.max(1, floor(pixelHeight * scale))
            )

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: resizedSize, format: format)
            return renderer.image { _ in
                source.draw(in: CGRect(origin: .zero, size: resizedSize))
            }
        }

        var workingImage = resizedImage(from: image, maxDimension: maxDimension)
        var quality: CGFloat = 0.8
        var encoded = workingImage.jpegData(compressionQuality: quality)

        while let data = encoded, data.count > targetByteCount && quality > 0.45 {
            quality -= 0.1
            encoded = workingImage.jpegData(compressionQuality: quality)
        }

        var currentMaxDimension = Swift.max(workingImage.size.width, workingImage.size.height)
        while let data = encoded, data.count > targetByteCount && currentMaxDimension > 1600 {
            currentMaxDimension *= 0.82
            workingImage = resizedImage(from: workingImage, maxDimension: currentMaxDimension)
            encoded = workingImage.jpegData(compressionQuality: quality)
        }

        return encoded
    }

    // MARK: - JSON helpers

    // Internal rather than private so the unit tests can exercise the
    // model-output parsing directly.
    static func extractJSONData(from text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            return data
        }

        // Fallback: pull the first top-level JSON object substring.
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw FlashcardsGeneratorError.invalidJSON
        }
        let jsonSubstring = String(trimmed[start...end])
        guard let data = jsonSubstring.data(using: .utf8) else {
            throw FlashcardsGeneratorError.invalidJSON
        }
        return data
    }

    // Internal rather than private so the unit tests can exercise the
    // model-output parsing directly.
    static func sanitizeExtractedStudyText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let emptyLikePhrases = [
            "no readable text",
            "no legible text",
            "no visible text",
            "nothing readable",
            "nothing legible",
            "unable to read",
            "can't read",
            "cannot read",
            "illegible",
            "too blurry",
            "too unclear",
            "empty response"
        ]

        if emptyLikePhrases.contains(where: { normalized == $0 || normalized.contains($0) }) {
            return ""
        }

        return trimmed
    }
}

enum FlashcardsGeneratorError: LocalizedError {
    case invalidJSON
    case malformedQuestions(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The model's reply wasn't valid JSON."
        case .malformedQuestions:
            return "The question list came back incomplete — this usually means the reply was cut short."
        }
    }
}

// MARK: - AI DTOs

private struct FlashcardsAIResponse: Codable {
    let questions: [FlashcardsAIQuestion]
}

private struct FlashcardsAIQuestion: Codable {
    let id: UUID
    let kind: FlashcardsQuestionKind
    let question: String
    let options: [String]?
    let correctIndex: Int?
    let expectedAnswer: String?
    let explanation: String?
    let sourcePageId: UUID?
    let sourcePageTitle: String?
    let sourceQuote: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case question
        case options
        case correctIndex = "correct_index"
        case expectedAnswer = "expected_answer"
        case explanation
        case sourcePageId = "source_page_id"
        case sourcePageTitle = "source_page_title"
        case sourceQuote = "source_quote"
    }

    func toDomain() -> FlashcardsQuestion {
        FlashcardsQuestion(
            id: id,
            kind: kind,
            question: question,
            options: options,
            correctIndex: correctIndex,
            expectedAnswer: expectedAnswer,
            explanation: explanation,
            sourcePageId: sourcePageId,
            sourcePageTitle: sourcePageTitle,
            sourceQuote: sourceQuote
        )
    }
}

private struct FlashcardsGradeResponse: Codable {
    let isCorrect: Bool
    let feedback: String

    enum CodingKeys: String, CodingKey {
        case isCorrect = "is_correct"
        case feedback
    }
}
