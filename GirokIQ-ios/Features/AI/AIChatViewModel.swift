import Foundation
import Combine
import SwiftUI
import PencilKit
import UIKit

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
    @Published private(set) var canRetryLastRequest: Bool = false

    private let aiService = AIService()
    private let supabaseService = SupabaseService.shared
    private let localDatabase = LocalDatabase.shared
    private let quotaService = CloudStorageQuotaService.shared
    private var streamTask: Task<Void, Never>?
    private var historyRefreshTask: Task<Void, Never>?
    private var lastRequestHadImageAttachment: Bool = false

    var notebookId: UUID?
    var userId: UUID?

    var contextProvider: (() -> String)?

    private var systemPrompt: String {
        let basePrompt = """
        You are GirokIQ Assistant, an AI embedded in a handwritten canvas note-taking app. \
        When an image is attached, it is a screenshot of the user's canvas containing handwritten notes, diagrams, or drawings. \
        Read all visible handwriting carefully and base your answer on it. \
        Keep responses concise and actionable. \
        Use real markdown with headings, bullets, and short sections when helpful. \
        For math or worked examples, put each equation or evaluation step on its own line instead of cramming multiple expressions into one sentence. \
        Do not write raw markdown symbols unless they actually create structure.
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

    private func canWriteToCloud() async -> Bool {
        guard Configuration.cloudChatEnabled else { return false }
        return await quotaService.canSyncToCloud(userId: userId)
    }

    // MARK: - Session Management

    func startSession(userId: UUID, notebookId: UUID?) async {
        let isSameSession = self.userId == userId && self.notebookId == notebookId
        let currentChatID = self.chat?.id

        self.userId = userId
        self.notebookId = notebookId
        
        await loadHistory()

        if isSameSession,
           let currentChatID,
           let refreshedCurrentChat = chatHistory.first(where: { $0.id == currentChatID }) {
            self.chat = refreshedCurrentChat
            if !messages.isEmpty || isStreaming || !streamingText.isEmpty {
                return
            }
            await selectChat(refreshedCurrentChat)
            return
        }

        if let existing = chatHistory.first(where: { $0.id == currentChatID }) ?? chatHistory.first {
            await selectChat(existing)
            return
        }

        await startNewChat()
    }

    func loadHistory() async {
        guard let userId = userId else { return }
        let localChats = (try? await localDatabase.fetchChats(userId: userId, notebookId: notebookId)) ?? []
        // Local-only launch mode: keep AI chat history on device.
        chatHistory = localChats
    }

    func selectChat(_ chat: Chat) async {
        self.chat = chat
        self.showHistory = false
        self.messages = []
        
        let localMessages = (try? await localDatabase.fetchMessages(chatId: chat.id)) ?? []
        self.messages = localMessages.map(Self.aiMessage(from:))
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
        chat = newChat
        chatHistory.insert(newChat, at: 0)
        try? await localDatabase.saveChat(newChat, syncStatus: .synced)
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedImageData != nil else { return }
        guard !isStreaming else { return }

        let currentAttachedImage = attachedImageData?.anthropicSafeImageData()
        let content = text.isEmpty && currentAttachedImage != nil ? "What do you see in this image?" : text

        inputText = ""
        attachedImageData = nil
        errorMessage = nil
        canRetryLastRequest = false

        // Add user message
        let userMessage = AIMessage(role: .user, content: content, imageData: currentAttachedImage)
        messages.append(userMessage)
        await persistMessage(userMessage)

        if let currentAttachedImage, currentAttachedImage.isStillTooLargeForVisionRequest {
            await appendOversizedVisionFallback()
            return
        }

        // Stream assistant response
        isStreaming = true
        streamingText = ""
        lastRequestHadImageAttachment = currentAttachedImage != nil
        startStreamingResponse(hadImageAttachment: currentAttachedImage != nil)
    }

    // MARK: - Send with Vision (canvas screenshot)

    func sendWithVision(text: String, imageData: Data) async {
        guard !isStreaming else { return }

        let safeImageData = imageData.anthropicSafeImageData()
        print("[AI Vision] imageData size: \(safeImageData.count) bytes")
        
        let content = text.isEmpty ? "What do you see on this canvas page?" : text
        inputText = ""
        errorMessage = nil
        canRetryLastRequest = false

        let userMessage = AIMessage(role: .user, content: content, imageData: safeImageData)
        messages.append(userMessage)
        await persistMessage(userMessage)

        if safeImageData.isStillTooLargeForVisionRequest {
            await appendOversizedVisionFallback()
            return
        }

        isStreaming = true
        streamingText = ""
        lastRequestHadImageAttachment = true
        startStreamingResponse(hadImageAttachment: true)
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
        canRetryLastRequest = false
    }

    func retryLastRequest() async {
        guard !isStreaming else { return }
        guard canRetryLastRequest else { return }
        guard messages.last?.role == .user else { return }

        errorMessage = nil
        canRetryLastRequest = false
        isStreaming = true
        streamingText = ""
        startStreamingResponse(hadImageAttachment: lastRequestHadImageAttachment)
    }

    func deleteMessage(_ aiMessage: AIMessage) async {
        messages.removeAll { $0.id == aiMessage.id }

        if canRetryLastRequest, messages.last?.role != .user {
            canRetryLastRequest = false
            errorMessage = nil
        }

        do {
            try await localDatabase.deleteMessage(id: aiMessage.id, syncStatus: .synced)
            await touchCurrentChat()
        } catch {
            print("[AIChatVM] Failed to delete message locally: \(error)")
        }
    }

    func deleteChat(_ chatToDelete: Chat) async {
        let deletingCurrentChat = chat?.id == chatToDelete.id

        if deletingCurrentChat {
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
            streamingText = ""
            errorMessage = nil
            canRetryLastRequest = false
            messages = []
            chat = nil
        }

        chatHistory.removeAll { $0.id == chatToDelete.id }

        do {
            try await localDatabase.deleteChat(id: chatToDelete.id, syncStatus: .synced)
        } catch {
            print("[AIChatVM] Failed to delete chat locally: \(error)")
        }

        if deletingCurrentChat {
            if let replacement = chatHistory.first {
                await selectChat(replacement)
            } else {
                await startNewChat()
            }
        }
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
            // Local-only launch mode: chat history stays on device.
            try await localDatabase.saveMessage(message, syncStatus: .synced)
            await touchCurrentChat()
        } catch {
            print("[AIChatVM] Failed to persist message, SyncEngine will retry: \(error)")
        }
    }

    private func appendAssistantMessage(_ content: String) async {
        let assistantMessage = AIMessage(role: .assistant, content: content)
        messages.append(assistantMessage)
        await persistMessage(assistantMessage)
        streamingText = ""
        errorMessage = nil
        canRetryLastRequest = false
    }

    private func appendOversizedVisionFallback() async {
        await appendAssistantMessage(Self.oversizedVisionFallbackText)
        isStreaming = false
    }

    private func oversizedVisionFallbackMessageIfNeeded(for error: Error, hadImageAttachment: Bool) -> String? {
        guard hadImageAttachment else { return nil }
        if let aiError = error as? AIError, aiError.isOversizedVisionFailure {
            return Self.oversizedVisionFallbackText
        }
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("image") && (
            lowered.contains("too large")
            || lowered.contains("too big")
            || lowered.contains("payload")
            || lowered.contains("dimension")
            || lowered.contains("max allowed size")
            || lowered.contains("8000 pixel")
            || lowered.contains("exceed max allowed size")
        ) {
            return Self.oversizedVisionFallbackText
        }
        return nil
    }

    private func startStreamingResponse(hadImageAttachment: Bool) {
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
                canRetryLastRequest = false
            } catch {
                if !Task.isCancelled {
                    if let oversizedFallback = oversizedVisionFallbackMessageIfNeeded(for: error, hadImageAttachment: hadImageAttachment) {
                        await appendAssistantMessage(oversizedFallback)
                    } else {
                        errorMessage = error.localizedDescription
                        canRetryLastRequest = true
                    }
                }
            }
            isStreaming = false
        }
    }

    private static let oversizedVisionFallbackText =
        "This page is too large for me to read reliably in one pass. I didn’t analyze the full image, so please capture a smaller region or zoom into the part you want me to help with."

    private func refreshHistoryFromRemote(userId: UUID, notebookId: UUID?) {
        // No-op in local-only launch mode.
        _ = userId
        _ = notebookId
    }

    private func filterChats(_ chats: [Chat], notebookId: UUID?) -> [Chat] {
        if let notebookId {
            return chats.filter { $0.notebookId == notebookId }
        }
        return chats
    }

    private func mergeChats(local: [Chat], remote: [Chat]) -> [Chat] {
        var mergedByID: [UUID: Chat] = [:]
        for chat in local {
            mergedByID[chat.id] = chat
        }
        for chat in remote {
            mergedByID[chat.id] = chat
        }
        return mergedByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func aiMessage(from message: Message) -> AIMessage {
        AIMessage(
            id: message.id,
            role: AIMessage.Role(rawValue: message.role.rawValue) ?? .assistant,
            content: message.content
        )
    }

    private func mergePersistedMessages(local: [Message], remote: [Message]) -> [AIMessage] {
        var mergedByID: [UUID: Message] = [:]

        for message in local {
            mergedByID[message.id] = message
        }

        for message in remote {
            mergedByID[message.id] = message
        }

        return mergedByID.values
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(Self.aiMessage(from:))
    }

    private func touchCurrentChat() async {
        guard var chat else { return }
        chat.updatedAt = Date()
        self.chat = chat

        if let index = chatHistory.firstIndex(where: { $0.id == chat.id }) {
            chatHistory[index] = chat
        } else {
            chatHistory.insert(chat, at: 0)
        }

        do {
            try await localDatabase.saveChat(chat, syncStatus: .synced)
        } catch {
            print("[AIChatVM] Failed to update chat timestamp: \(error)")
        }
    }
}

private extension Data {
    var isStillTooLargeForVisionRequest: Bool {
        count > 3_500_000
    }

    func anthropicSafeImageData(
        maxDimension: CGFloat = 4096,
        targetByteCount: Int = 3_500_000,
        compressionQuality: CGFloat = 0.8
    ) -> Data {
        guard let image = UIImage(data: self) else { return self }
        
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
        var quality = compressionQuality
        var encoded = workingImage.jpegData(compressionQuality: quality) ?? self
        
        while encoded.count > targetByteCount && quality > 0.45 {
            quality -= 0.1
            encoded = workingImage.jpegData(compressionQuality: quality) ?? encoded
        }
        
        var currentMaxDimension = Swift.max(workingImage.size.width, workingImage.size.height)
        while encoded.count > targetByteCount && currentMaxDimension > 1600 {
            currentMaxDimension *= 0.82
            workingImage = resizedImage(from: workingImage, maxDimension: currentMaxDimension)
            encoded = workingImage.jpegData(compressionQuality: quality) ?? encoded
            
            while encoded.count > targetByteCount && quality > 0.35 {
                quality -= 0.05
                encoded = workingImage.jpegData(compressionQuality: quality) ?? encoded
            }
        }
        
        return encoded
    }
}
