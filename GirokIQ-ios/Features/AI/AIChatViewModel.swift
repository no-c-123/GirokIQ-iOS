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

    @Published var chat: Chat?
    @Published var chatHistory: [Chat] = []
    @Published var showHistory: Bool = false

    private let aiService = AIService()
    private let supabaseService = SupabaseService.shared
    private var streamTask: Task<Void, Never>?

    var notebookId: UUID?
    var userId: UUID?
    var contextProvider: (() -> String)?

    // MARK: - System Prompt

    private var systemPrompt: String {
        let base = """
        You are GirokIQ Assistant, an AI embedded in a handwritten canvas note-taking app. \
        When an image is attached, it is a screenshot of the user's canvas containing handwritten \
        notes, diagrams, or drawings. Read all visible handwriting carefully and base your answer \
        on it. Keep responses concise and actionable. Use markdown formatting when helpful.
        """
        if let context = contextProvider?(), !context.isEmpty {
            return "\(base)\n\nCurrent Canvas Context:\n\(context)"
        }
        return base
    }

    var hasAPIKey: Bool { true }

    // MARK: - Session Management

    func startSession(userId: UUID, notebookId: UUID?) async {
        self.userId = userId
        self.notebookId = notebookId
        await loadHistory()

        // Resume the most recent chat for this notebook, or start a fresh one
        if let existing = chatHistory.first {
            await selectChat(existing)
        } else {
            await startNewChat()
        }
    }

    func loadHistory() async {
        guard let userId else { return }
        do {
            let all = try await supabaseService.fetchChats(userId: userId)
            if let notebookId {
                chatHistory = all.filter { $0.notebookId == notebookId }
            } else {
                chatHistory = all
            }
        } catch {
            print("[AIChatVM] Failed to load history: \(error)")
        }
    }

    func selectChat(_ chat: Chat) async {
        self.chat = chat
        self.messages = []
        self.showHistory = false
        do {
            let fetched = try await supabaseService.fetchMessages(chatId: chat.id)
            self.messages = fetched.map {
                AIMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
            }
        } catch {
            print("[AIChatVM] Failed to load messages: \(error)")
        }
    }

    func startNewChat() async {
        guard let userId else { return }
        messages = []
        showHistory = false

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
            chatHistory.insert(chat!, at: 0)
        } catch {
            print("[AIChatVM] Failed to create chat remotely, using offline fallback: \(error)")
            chat = newChat
            chatHistory.insert(newChat, at: 0)
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil

        let userMessage = AIMessage(role: .user, content: text)
        messages.append(userMessage)
        await persistMessage(userMessage)

        await streamResponse()
    }

    // MARK: - Send with Vision

    func sendWithVision(text: String, drawing: PKDrawing) async {
        guard !isStreaming else { return }

        let imageData = PencilKitBridge.renderPNGData(from: drawing)
        let content = text.isEmpty ? "What do you see on this canvas page?" : text
        inputText = ""
        errorMessage = nil

        let userMessage = AIMessage(role: .user, content: content, imageData: imageData)
        messages.append(userMessage)
        await persistMessage(userMessage)

        await streamResponse()
    }

    func sendWithVisionData(text: String, imageData: Data) async {
        guard !isStreaming else { return }

        let content = text.isEmpty ? "What do you see in this selected region?" : text
        inputText = ""
        errorMessage = nil

        let userMessage = AIMessage(role: .user, content: content, imageData: imageData)
        messages.append(userMessage)
        await persistMessage(userMessage)

        await streamResponse()
    }

    // MARK: - Shared Stream Response

    private func streamResponse() async {
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
                let assistantMessage = AIMessage(role: .assistant, content: streamingText)
                messages.append(assistantMessage)
                await persistMessage(assistantMessage)
                streamingText = ""

                // Auto-generate title after first assistant reply
                if messages.filter({ $0.role == .assistant }).count == 1 {
                    await generateAndSaveTitle()
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isStreaming = false
        }
    }

    // MARK: - Auto Title Generation

    private func generateAndSaveTitle() async {
        guard var currentChat = chat else { return }

        // Build a short prompt from the first exchange only
        let firstUser = messages.first(where: { $0.role == .user })?.content ?? ""
        let firstAssistant = messages.first(where: { $0.role == .assistant })?.content ?? ""
        let excerpt = String((firstUser + " " + firstAssistant).prefix(300))

        let titlePrompt = """
        Based on this conversation excerpt, generate a short chat title (4-6 words max, \
        no punctuation, no quotes). Reply with ONLY the title, nothing else.

        Excerpt: \(excerpt)
        """

        do {
            let title = try await aiService.complete(
                systemPrompt: "You generate short, descriptive chat titles.",
                messages: [AIMessage(role: .user, content: titlePrompt)]
            )
            let cleanTitle = title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")

            guard !cleanTitle.isEmpty else { return }

            // Update in memory
            currentChat.title = cleanTitle
            currentChat.updatedAt = Date()
            self.chat = currentChat

            // Update in chatHistory list so it reflects immediately in the history panel
            if let idx = chatHistory.firstIndex(where: { $0.id == currentChat.id }) {
                chatHistory[idx] = currentChat
            }

            // Persist to Supabase
            try await supabaseService.updateChat(currentChat)

        } catch {
            print("[AIChatVM] Title generation failed (non-critical): \(error)")
        }
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
            print("[AIChatVM] Failed to persist message: \(error)")
        }
    }
}