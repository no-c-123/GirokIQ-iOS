import Foundation
import Combine
import SwiftUI
import PencilKit

// MARK: - AI Chat ViewModel

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var streamingText: String = ""
    @Published var errorMessage: String?

    /// The persisted Chat row for this session
    @Published var chat: Chat?

    private let aiService = AIService()
    private let supabaseService = SupabaseService.shared
    private var streamTask: Task<Void, Never>?

    var notebookId: UUID?
    var userId: UUID?

    private let systemPrompt = """
    You are GirokIQ Assistant, an AI helper embedded in an infinite-canvas thinking workspace. \
    You help users brainstorm, organize ideas, summarize notes, and answer questions about their canvas content. \
    Keep responses concise and actionable. Use markdown formatting when helpful.
    """

    var hasAPIKey: Bool { true }

    // MARK: - Session Management

    func startSession(userId: UUID, notebookId: UUID?) async {
        self.userId = userId
        self.notebookId = notebookId

        // Create a new chat row
        let newChat = Chat(
            id: UUID(),
            userId: userId,
            notebookId: notebookId,
            title: "New Chat",
            createdAt: Date(),
            updatedAt: Date()
        )
        do {
            chat = try await supabaseService.createChat(newChat)
        } catch {
            print("[AIChatVM] Failed to create chat remotely, using offline fallback: \(error)")
            chat = newChat
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil

        // Add user message
        let userMessage = AIMessage(role: .user, content: text)
        messages.append(userMessage)
        await persistMessage(userMessage)

        // Stream assistant response
        isStreaming = true
        streamingText = ""

        streamTask = Task {
            do {
                let stream = aiService.stream(
                    systemPrompt: systemPrompt,
                    messages: messages
                )
                for try await chunk in stream {
                    streamingText += chunk
                }
                // Finalize assistant message
                let assistantMessage = AIMessage(role: .assistant, content: streamingText)
                messages.append(assistantMessage)
                await persistMessage(assistantMessage)
                streamingText = ""
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isStreaming = false
        }
    }

    // MARK: - Send with Vision (canvas screenshot)

    func sendWithVision(text: String, drawing: PKDrawing) async {
        guard !isStreaming else { return }

        let imageData = PencilKitBridge.renderPNGData(from: drawing)
        let content = text.isEmpty ? "What do you see on this canvas page?" : text
        inputText = ""
        errorMessage = nil

        let userMessage = AIMessage(role: .user, content: content, imageData: imageData)
        messages.append(userMessage)
        await persistMessage(userMessage)

        isStreaming = true
        streamingText = ""

        do {
            let response = try await aiService.complete(
                systemPrompt: systemPrompt,
                messages: messages,
                imageData: imageData
            )
            let assistantMessage = AIMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
            await persistMessage(assistantMessage)
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }

    // MARK: - Cancel

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if !streamingText.isEmpty {
            let partial = AIMessage(role: .assistant, content: streamingText + " [cancelled]")
            messages.append(partial)
        }
        streamingText = ""
        isStreaming = false
    }

    // MARK: - Persistence

    private func persistMessage(_ aiMessage: AIMessage) async {
        guard let chatId = chat?.id else { return }
        let message = Message(
            id: aiMessage.id,
            chatId: chatId,
            role: Message.Role(rawValue: aiMessage.role.rawValue) ?? .user,
            content: aiMessage.content,
            tokenCount: nil,
            createdAt: Date()
        )
        do {
            _ = try await supabaseService.insertMessage(message)
        } catch {
            print("[AIChatVM] Failed to persist message, SyncEngine will retry: \(error)")
        }
    }
}
