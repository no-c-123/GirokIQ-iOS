import Foundation
import Supabase

// MARK: - AI Service

/// Calls the server-side `ai-chat` Supabase Edge Function.
/// The user's auth session is forwarded as a Bearer token; the Anthropic key stays server-side.
final class AIService {
    private var endpoint: URL {
        Configuration.supabaseFunctionsBaseURL.appendingPathComponent("ai-chat")
    }
    private let defaultModel = "claude-sonnet-4-6"

    // MARK: - API Key Management

    var hasAPIKey: Bool {
        true
    }

    func setAPIKey(_ key: String) {
        _ = key
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
        let request = try await authorizedRequest(
            systemPrompt: systemPrompt,
            messages: messages,
            imageData: imageData,
            model: model ?? defaultModel,
            stream: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIError.apiError(
                statusCode: httpResponse.statusCode,
                message: extractErrorBody(from: data)
            )
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
                do {
                    let request = try await self.authorizedRequest(
                        systemPrompt: systemPrompt,
                        messages: messages,
                        imageData: imageData,
                        model: model ?? self.defaultModel,
                        stream: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        let errorBody = try await self.extractErrorBody(from: bytes)
                        continuation.finish(throwing: AIError.apiError(
                            statusCode: httpResponse.statusCode,
                            message: errorBody
                        ))
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

    private func authorizedRequest(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data?,
        model: String,
        stream: Bool
    ) async throws -> URLRequest {
        let session = try await supabase.auth.session
        guard !session.isExpired else {
            throw AIError.unauthorized
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        var body = buildRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            imageData: imageData,
            model: model
        )
        if stream {
            body["stream"] = true
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildRequestBody(
        systemPrompt: String,
        messages: [AIMessage],
        imageData: Data?,
        model: String
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
                                "media_type": detectedMediaType(for: data),
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
    
    private func detectedMediaType(for data: Data) -> String {
        let header = [UInt8](data.prefix(12))
        
        if header.count >= 3,
           header[0] == 0xFF,
           header[1] == 0xD8,
           header[2] == 0xFF {
            return "image/jpeg"
        }
        
        if header.count >= 8,
           header[0] == 0x89,
           header[1] == 0x50,
           header[2] == 0x4E,
           header[3] == 0x47,
           header[4] == 0x0D,
           header[5] == 0x0A,
           header[6] == 0x1A,
           header[7] == 0x0A {
            return "image/png"
        }
        
        return "image/jpeg"
    }


    private func parseResponse(_ data: Data) throws -> String {
        if
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = (json["error"] as? String) ?? (json["message"] as? String)
        {
            throw AIError.apiError(statusCode: 500, message: error)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.invalidResponse
        }
        return text
    }

    private func extractErrorBody(from data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = (json["error"] as? String) ?? (json["message"] as? String),
            !error.isEmpty
        {
            return error
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "Unknown error"
    }

    private func extractErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var errorBody = ""
        for try await line in bytes.lines {
            errorBody += line
        }

        if let data = errorBody.data(using: .utf8) {
            return extractErrorBody(from: data)
        }

        return errorBody.isEmpty ? "Unknown error" : errorBody
    }
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case unauthorized
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI service is not configured."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .apiError(let code, let message):
            if code == 429 {
                return message
            }
            return "AI error (\(code)): \(message)"
        }
    }

    var isOversizedVisionFailure: Bool {
        switch self {
        case .apiError(let statusCode, let message):
            let lowered = message.lowercased()
            return statusCode == 413
                || lowered.contains("image too large")
                || lowered.contains("request too large")
                || lowered.contains("too many bytes")
                || lowered.contains("maximum context length")
                || lowered.contains("payload too large")
                || lowered.contains("dimension")
                || lowered.contains("max allowed size")
                || lowered.contains("8000 pixel")
                || lowered.contains("exceed max allowed size")
                || lowered.contains("too large")
        default:
            return false
        }
    }
}
