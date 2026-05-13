import Foundation

// MARK: - AI Service

/// Calls the Anthropic Messages API via direct URLSession.
/// API key is sourced from Configuration (xcconfig → Info.plist).
final class AIService {
    private static let endpointURL: URL = {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            preconditionFailure("Invalid static API endpoint URL")
        }
        return url
    }()
    private var endpoint: URL { Self.endpointURL }
    private let defaultModel = "claude-sonnet-4-20250514"

    private var resolvedAPIKey: String { Configuration.anthropicAPIKey }

    // MARK: - API Key Management

    var hasAPIKey: Bool {
        !resolvedAPIKey.isEmpty
    }

    func setAPIKey(_ key: String) {
    }

    func removeAPIKey() {
    }

    // MARK: - Chat Completion

    /// Send a message to Claude and receive a response.
    /// Supports optional image data for vision tasks (page screenshots).
    func complete(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data? = nil,
        model: String? = nil
    ) async throws -> String {
        let apiKey = resolvedAPIKey
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = buildRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            imageData: imageData,
            model: model ?? defaultModel
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return try parseResponse(data)
    }

    // MARK: - Streaming Completion

    /// Stream a response from Claude for real-time display in the AI panel.
    func stream(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data? = nil,
        model: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let apiKey = self.resolvedAPIKey
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: AIError.noAPIKey)
                    return
                }

                var request = URLRequest(url: self.endpoint)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                var body = self.buildRequestBody(
                    systemPrompt: systemPrompt,
                    messages: messages,
                    imageData: imageData,
                    model: model ?? self.defaultModel
                )
                body["stream"] = true
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let jsonData = jsonString.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        if type == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func buildRequestBody(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data?,
        model: String
    ) -> [String: Any] {
        let lastUserIndex = messages.indices.last(where: { messages[$0].role == .user })
        var apiMessages: [[String: Any]] = messages.enumerated().map { index, msg in
            let isLastUser = index == lastUserIndex
            let attachedImage = isLastUser ? (msg.imageData ?? imageData) : msg.imageData
            if let data = attachedImage {
                return [
                    "role": msg.role.rawValue,
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": data.base64EncodedString()
                            ]
                        ],
                        [
                            "type": "text",
                            "text": msg.content
                        ]
                    ]
                ]
            }
            return [
                "role": msg.role.rawValue,
                "content": msg.content
            ]
        }

        if apiMessages.isEmpty {
            apiMessages = [["role": "user", "content": "Hello"]]
        }

        return [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": apiMessages
        ]
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text
    }
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI service is not configured (missing ANTHROPIC_API_KEY). Please rebuild the app or contact support."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .apiError(let code, let message):
            return "AI error (\(code)): \(message)"
        }
    }
}
