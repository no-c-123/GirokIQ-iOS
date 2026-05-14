import Foundation
import Combine
import SwiftUI
import PencilKit

// MARK: - AI Chat ViewModel

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var inputText: String = ""
    @Published var attachedImageData: Data? = nil
    @Published var isStreaming: Bool = false
    @Published var streamingText: String = ""
    @Published var errorMessage: String?

    /// The persisted Chat row for this session
    @Published var chat: Chat?
    @Published var chatHistory: [Chat] = []
    @Published var showHistory: Bool = false

    private let aiService = AIService()
    private let supabaseService = SupabaseService.shared
    private var streamTask: Task<Void, Never>?

    var notebookId: UUID?
    var userId: UUID?

    var contextProvider: (() -> String)?

    private var systemPrompt: String {
        let basePrompt = """
        You are GirokIQ Assistant, an AI embedded in a handwritten canvas note-taking app. \
        When an image is attached, it is a screenshot of the user's canvas containing handwritten notes, diagrams, or drawings. \
        Read all visible handwriting carefully and base your answer on it. \
        Keep responses concise and actionable. Use markdown formatting when helpful.
        """
        
        if let context = contextProvider?(), !context.isEmpty {
            return """
            \(basePrompt)
            
            Current Canvas Context:
            \(context)
            """
        }
        return basePrompt
    }

    var hasAPIKey: Bool { true }

    // MARK: - Session Management

    func startSession(userId: UUID, notebookId: UUID?) async {
        self.userId = userId
        self.notebookId = notebookId
        
        await loadHistory()

        if let existing = chatHistory.first {
            await selectChat(existing)
        } else {
            await startNewChat()
        }
    }

    func loadHistory() async {
        guard let userId = userId else { return }
        do {
            let allChats = try await supabaseService.fetchChats(userId: userId)
            // Filter chats by notebookId if applicable
            if let notebookId = notebookId {
                chatHistory = allChats.filter { $0.notebookId == notebookId }
            } else {
                chatHistory = allChats
            }
        } catch {
            print("[AIChatVM] Failed to fetch chat history: \(error)")
        }
    }

    func selectChat(_ chat: Chat) async {
        self.chat = chat
        self.showHistory = false
        self.messages = []
        
        do {
            let fetchedMessages = try await supabaseService.fetchMessages(chatId: chat.id)
            self.messages = fetchedMessages.map { msg in
                AIMessage(
                    role: msg.role == .user ? .user : .assistant,
                    content: msg.content
                )
            }
        } catch {
            print("[AIChatVM] Failed to fetch messages for chat: \(error)")
        }
    }

    func startNewChat() async {
        guard let userId = userId else { return }
        self.messages = []
        self.showHistory = false
        
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
        guard !text.isEmpty || attachedImageData != nil else { return }
        guard !isStreaming else { return }

        let currentAttachedImage = attachedImageData
        let content = text.isEmpty && currentAttachedImage != nil ? "What do you see in this image?" : text

        inputText = ""
        attachedImageData = nil
        errorMessage = nil

        // Add user message
        let userMessage = AIMessage(role: .user, content: content, imageData: currentAttachedImage)
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

    func sendWithVision(text: String, imageData: Data) async {
        guard !isStreaming else { return }

        print("[AI Vision] imageData size: \(imageData.count) bytes")
        
        let content = text.isEmpty ? "What do you see on this canvas page?" : text
        inputText = ""
        errorMessage = nil

        let userMessage = AIMessage(role: .user, content: content, imageData: imageData)
        messages.append(userMessage)
        await persistMessage(userMessage)

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

    func sendWithVision(text: String, drawing: PKDrawing) async {
        guard !isStreaming else { return }

        let imageData = PencilKitBridge.renderPNGData(from: drawing)
        print("[AI Vision] imageData size: \(imageData?.count ?? 0) bytes")
        print("[AI Vision] drawing strokes count: \(drawing.strokes.count)")
        
        if let data = imageData {
            await sendWithVision(text: text, imageData: data)
        } else {
            await sendMessage()
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
            print("[AIChatVM] Failed to persist message, SyncEngine will retry: \(error)")
        }
    }
}
