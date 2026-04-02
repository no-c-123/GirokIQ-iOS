import Foundation

// MARK: - AI Service

/// Calls the Anthropic Messages API (or OpenAI-compatible endpoint) via direct URLSession.
/// API key is stored in Keychain — never hardcoded.
final class AIService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"
    private let keychain = KeychainService.shared
    private let keychainKey = "anthropic_api_key"

    // MARK: - API Key Management

    var hasAPIKey: Bool {
        keychain.get(keychainKey) != nil
    }

    func setAPIKey(_ key: String) {
        keychain.set(key, forKey: keychainKey)
    }

    func removeAPIKey() {
        keychain.delete(keychainKey)
    }

    // MARK: - Chat Completion

    /// Send a message to Claude and receive a response.
    /// Supports optional image data for vision tasks (page screenshots).
    func complete(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data? = nil
    ) async throws -> String {
        guard let apiKey = keychain.get(keychainKey) else {
            throw AIError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = buildRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            imageData: imageData
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
        messages: [AIMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let apiKey = self.keychain.get(self.keychainKey) else {
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
                    imageData: nil
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
        imageData: Data?
    ) -> [String: Any] {
        var apiMessages: [[String: Any]] = messages.map { msg in
            if let data = msg.imageData ?? (msg.role == .user ? imageData : nil) {
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
            return "No API key configured. Add your Anthropic API key in Settings."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .apiError(let code, let message):
            return "AI error (\(code)): \(message)"
        }
    }
}
