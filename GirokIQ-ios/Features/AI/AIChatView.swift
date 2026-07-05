import SwiftUI
import Combine
import PencilKit
import UIKit
internal import UniformTypeIdentifiers
import Foundation

// MARK: - AI Chat View

struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    var drawing: PKDrawing?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showImagePicker = false
    @State private var showFileImporter = false
    @State private var attachedContextKind: AttachmentContextKind = .none
    @State private var chatPendingDeletion: Chat?
    var onRegionCapture: (() -> Void)? = nil

    private var railBackground: Color {
        colorScheme == .dark ? Color(hex: "#12100D") : Color(hex: "#F6F1E7")
    }

    private var railSurface: Color {
        colorScheme == .dark ? Color(hex: "#171410") : Color(hex: "#FBF8F2")
    }

    private var railElevated: Color {
        colorScheme == .dark ? Color(hex: "#211C15") : Color(hex: "#EFE8DB")
    }

    private var railStroke: Color {
        colorScheme == .dark ? Color(hex: "#2B241B") : Color(hex: "#DDD2BE")
    }

    private var railText: Color {
        colorScheme == .dark ? Color(hex: "#F4EFE6") : Color(hex: "#241F18")
    }

    private var railSubtext: Color {
        colorScheme == .dark ? Color(hex: "#9D9488") : Color(hex: "#7D7367")
    }

    private var railAccent: Color { Color(hex: "#C9A84C") }

    private var isNarrowRail: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader

            if viewModel.showHistory {
                historyList
            } else {
                messageList
                composerSection
            }
        }
        .background(railBackground)
        .onChange(of: viewModel.attachedImageData) { _, newValue in
            if newValue == nil {
                attachedContextKind = .none
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(imageData: $viewModel.attachedImageData)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    if let data = try? Data(contentsOf: url) {
                        viewModel.attachedImageData = data
                        attachedContextKind = .image
                    }
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        .confirmationDialog(
            "Delete chat?",
            isPresented: Binding(
                get: { chatPendingDeletion != nil },
                set: { if !$0 { chatPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                if let chat = chatPendingDeletion {
                    Task { await viewModel.deleteChat(chat) }
                }
                chatPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                chatPendingDeletion = nil
            }
        } message: {
            Text("This will permanently remove the chat and its messages.")
        }
    }

    // MARK: - Header

    var chatHeader: some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(railAccent)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistant")
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(railText)

                    Text("This notebook")
                        .font(.gCaption)
                        .foregroundColor(railSubtext)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                Button {
                    Task { await viewModel.startNewChat() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.showHistory ? railSubtext : railText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")

                Button {
                    animateMotionSafe(GAnimation.springFast) {
                        viewModel.showHistory.toggle()
                    }
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(viewModel.showHistory ? railAccent : railSubtext)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chat History")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.top, GSpacing.md)
        .padding(.bottom, GSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notebook assistant")
    }

    // MARK: - History List
    
    var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: GSpacing.sm) {
                Button {
                    Task { await viewModel.startNewChat() }
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Chat")
                        Spacer()
                    }
                    .font(.gSubheadline)
                    .foregroundColor(railText)
                    .padding(.horizontal, GSpacing.md)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                            .fill(railElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                    .stroke(railStroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                ForEach(viewModel.chatHistory) { chat in
                    let isSelected = viewModel.chat?.id == chat.id

                    HStack(spacing: 10) {
                        Button {
                            Task { await viewModel.selectChat(chat) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chat.title)
                                        .font(.gSubheadline)
                                        .foregroundColor(railText)
                                        .lineLimit(1)
                                    Text(historyTimestamp(for: chat))
                                        .font(.gCaption.weight(.medium))
                                        .foregroundColor(railSubtext)
                                }
                                Spacer()
                                Circle()
                                    .fill(isSelected ? railAccent : Color.clear)
                                    .frame(width: 10, height: 10)
                            }
                            .padding(.horizontal, GSpacing.md)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                    .fill(isSelected ? railAccent.opacity(0.16) : railElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                            .stroke(isSelected ? railAccent.opacity(0.8) : railStroke, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            chatPendingDeletion = chat
                        } label: {
                            Image(systemName: "trash")
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.red.opacity(0.9))
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete chat")
                    }
                }

                Text("Chats are saved with this notebook")
                    .font(.gSubheadline)
                    .foregroundColor(railSubtext)
                    .padding(.top, GSpacing.md)
            }
            .padding(GSpacing.md)
        }
    }

    // MARK: - Message List

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GSpacing.md) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        welcomeMessage
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, colorScheme: colorScheme)
                            .id(message.id)
                    }

                    // Streaming indicator
                    if viewModel.isStreaming {
                        streamingBubble
                            .id("streaming")
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        errorBubble(error)
                    }
                }
                .padding(.horizontal, GSpacing.md)
                .padding(.vertical, GSpacing.md)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastId = viewModel.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    var welcomeMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.black.opacity(0.72))
                .frame(width: 46, height: 46)
                .background(railAccent)
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text("Ask anything about your notes")
                    .font(.gHeadline.weight(.semibold))
                    .foregroundColor(railText)
                Text("Grounded in the current page, a captured region, or an attached image.")
                    .font(.gCaption)
                    .foregroundColor(railSubtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }

            VStack(spacing: 10) {
                quickActionChip("Summarize this page")
                quickActionChip("Explain these notes")
                quickActionChip("Turn this into an outline")
                quickActionChip("What should I add next?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, isNarrowRail ? 44 : 72)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask anything about your notes")
    }

    private func quickActionChip(_ text: String) -> some View {
        Button {
            if let drawing, !drawing.strokes.isEmpty {
                Task { await viewModel.sendWithVision(text: text, drawing: drawing) }
            } else {
                viewModel.inputText = text
                Task { await viewModel.sendMessage() }
            }
        } label: {
            HStack(spacing: GSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(railAccent)
                    .frame(width: 18)

                Text(text)
                    .font(.gSubheadline)
                    .foregroundColor(railText)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(railSubtext)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                    .fill(railElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                            .stroke(railStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: isNarrowRail ? 280 : 320, alignment: .center)
    }

    var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(railAccent)
                Text("Thinking about your notes…")
                    .font(.gSubheadline.weight(.medium))
                    .foregroundColor(railSubtext)
            }

            AIFormattedText(text: viewModel.streamingText, emphasis: .regular)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(railElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(railStroke, lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notebook assistant is responding: \(viewModel.streamingText)")
    }

    func errorBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            HStack(spacing: GSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.gCaption)
                    .foregroundColor(.red)
                Text(text)
                    .font(.gCaption)
                    .foregroundColor(.red)
            }

            if viewModel.canRetryLastRequest {
                Button {
                    Task { await viewModel.retryLastRequest() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.gCaption.weight(.semibold))
                        .foregroundColor(.gPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(GSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(text)")
    }

    // MARK: - Composer

    var composerSection: some View {
        VStack(spacing: 12) {
            contextSection
            inputBar
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.top, 12)
        .padding(.bottom, GSpacing.md)
        .background(railBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(railStroke)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData = viewModel.attachedImageData, let uiImage = UIImage(data: imageData) {
                attachmentContextCard(image: uiImage)
            }

            contextChipRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var contextChipRow: some View {
        HStack(spacing: GSpacing.xs) {
            railContextChip(title: "Current page", icon: "square.on.square", isAccent: true)

            Button {
                attachedContextKind = .capturedRegion
                onRegionCapture?()
            } label: {
                railContextChip(title: "Add context", icon: "plus", isAccent: false)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    func attachmentContextCard(image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .stroke(Color.gBorder.opacity(0.3), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(attachedContextKind.title)
                    .font(.gSubheadline.weight(.medium))
                    .foregroundColor(railText)
                Text(attachedContextKind.subtitle)
                    .font(.gCaption)
                    .foregroundColor(railSubtext)
            }

            Spacer()

            Button {
                viewModel.attachedImageData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(railSubtext.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(railElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(railStroke, lineWidth: 0.8)
                )
        )
    }

    // MARK: - Input Bar

    var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                attachedContextKind = .capturedRegion
                onRegionCapture?()
            } label: {
                circularComposerButton(icon: "viewfinder", isFilled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Region Capture")
            .accessibilityHint("Capture a specific region of the canvas")

            Menu {
                Button {
                    showImagePicker = true
                    attachedContextKind = .image
                } label: {
                    Label("Photo Library", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                    attachedContextKind = .image
                } label: {
                    Label("Files", systemImage: "folder")
                }
            } label: {
                circularComposerButton(icon: "plus", isFilled: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insert image or file")

            HStack(spacing: 0) {
                TextField(inputPlaceholder, text: $viewModel.inputText, axis: .vertical)
                    .font(.gSubheadline)
                    .foregroundColor(railText)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type a question for the notebook assistant")
            }
            .background(
                Capsule(style: .continuous)
                    .fill(railElevated)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(railStroke, lineWidth: 0.8)
                    )
            )

            if viewModel.isStreaming {
                Button {
                    viewModel.cancelStream()
                } label: {
                    circularComposerButton(icon: "stop.fill", isFilled: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop generating")
                .accessibilityHint("Double tap to stop AI response")
            } else {
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    circularComposerButton(icon: "arrow.up", isFilled: true)
                        .opacity(canSendMessage ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
                .accessibilityLabel("Send message")
                .accessibilityHint("Double tap to send your message to the AI")
            }
        }
    }

    private var canSendMessage: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.attachedImageData != nil
    }

    private var inputPlaceholder: String {
        viewModel.isStreaming ? "Ask a follow-up…" : "Ask your notes…"
    }

    private func railContextChip(title: String, icon: String, isAccent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.gCaption.weight(.medium))
        }
        .foregroundColor(isAccent ? railAccent : railSubtext)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(isAccent ? railAccent.opacity(0.14) : railElevated)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isAccent ? railAccent.opacity(0.22) : railStroke, lineWidth: 0.8)
                )
        )
    }

    private var chatSubtitle: String {
        if viewModel.showHistory {
            return "This notebook · History"
        }
        if let chat = viewModel.chat {
            let title = chat.title == "New Chat" ? "New chat" : chat.title
            return "This notebook · \(title)"
        }
        return "This notebook"
    }

    private func historyTimestamp(for chat: Chat) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(chat.updatedAt) {
            return chat.updatedAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(chat.updatedAt) {
            return "Yesterday"
        }
        return chat.updatedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func circularComposerButton(icon: String, isFilled: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(isFilled ? .black.opacity(0.72) : railAccent)
            .frame(width: 42, height: 42)
            .background(isFilled ? railAccent : railElevated)
            .overlay(
                Circle()
                    .stroke(isFilled ? railAccent.opacity(0.35) : railStroke, lineWidth: 0.8)
            )
            .clipShape(Circle())
    }
}

// MARK: - Inline AI Answer Overlay (selection/region)

@MainActor
final class InlineAIOverlayViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var anchorCanvasRect: CGRect? = nil
    @Published var popupOffset: CGSize = .zero
    @Published var prompt: String = ""
    @Published var answer: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String? = nil
    @Published var canRetry: Bool = false
    
    var contextProvider: (() -> String)?
    var onDismiss: (() -> Void)?
    
    private let aiService = AIService()
    private var lastImageData: Data? = nil
    private var streamTask: Task<Void, Never>?
    
    func present(anchorCanvasRect: CGRect, imageData: Data, defaultPrompt: String = "", autoSend: Bool = false) {
        self.anchorCanvasRect = anchorCanvasRect
        self.popupOffset = .zero
        self.lastImageData = imageData
        self.prompt = defaultPrompt
        self.answer = ""
        self.errorMessage = nil
        self.canRetry = false
        self.isVisible = true
        
        if autoSend {
            Task { await send() }
        }
    }
    
    func dismiss() {
        cancel()
        isVisible = false
        anchorCanvasRect = nil
        popupOffset = .zero
        lastImageData = nil
        answer = ""
        errorMessage = nil
        canRetry = false
        onDismiss?()
    }
    
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        canRetry = false
    }
    
    func send() async {
        guard !isStreaming else { return }
        guard let imageData = lastImageData?.anthropicSafeImageData() else { return }
        
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        errorMessage = nil
        answer = ""
        isStreaming = true
        canRetry = false

        if imageData.isStillTooLargeForVisionRequest {
            answer = Self.oversizedVisionFallbackText
            isStreaming = false
            return
        }
        
        let basePrompt = """
        You are GirokIQ Assistant, an AI embedded in a handwritten canvas note-taking app. \
        The attached image is a screenshot of the user's selected notes region. \
        Read all visible handwriting carefully and base your answer on it. \
        Keep the response concise and practical. \
        Use real markdown with headings, bullets, and short sections when helpful. \
        For math or worked examples, put each equation or evaluation step on its own line instead of cramming multiple expressions into one sentence. \
        Do not write raw markdown symbols unless they actually create structure.
        """
        
        let systemPrompt: String
        if let ctx = contextProvider?(), !ctx.isEmpty {
            systemPrompt = """
            \(basePrompt)
            
            Current Canvas Context:
            \(ctx)
            """
        } else {
            systemPrompt = basePrompt
        }
        
        let messages: [AIMessage] = [
            AIMessage(role: .user, content: trimmed, imageData: imageData)
        ]
        
        streamTask = Task {
            do {
                let stream = aiService.stream(systemPrompt: systemPrompt, messages: messages)
                for try await chunk in stream {
                    answer += chunk
                }
            } catch {
                if !Task.isCancelled {
                    if let aiError = error as? AIError, aiError.isOversizedVisionFailure {
                        errorMessage = nil
                        answer = Self.oversizedVisionFallbackText
                    } else if error.localizedDescription.lowercased().contains("image")
                                && (error.localizedDescription.lowercased().contains("too large")
                                    || error.localizedDescription.lowercased().contains("too big")
                                    || error.localizedDescription.lowercased().contains("payload")
                                    || error.localizedDescription.lowercased().contains("dimension")
                                    || error.localizedDescription.lowercased().contains("max allowed size")
                                    || error.localizedDescription.lowercased().contains("8000 pixel")
                                    || error.localizedDescription.lowercased().contains("exceed max allowed size")) {
                        errorMessage = nil
                        answer = Self.oversizedVisionFallbackText
                    } else {
                        errorMessage = error.localizedDescription
                        canRetry = true
                    }
                }
            }
            isStreaming = false
        }
    }

    private static let oversizedVisionFallbackText =
        "This page is too large for me to read reliably in one pass. I didn’t analyze the full image, so please capture a smaller region or zoom into the part you want me to help with."
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

struct InlineAIAnswerOverlay: View {
    @ObservedObject var viewModel: InlineAIOverlayViewModel
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    
    @State private var measuredBubbleHeight: CGFloat = 228
    @State private var measuredResponseHeight: CGFloat = 72
    @State private var morphProgress: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            if viewModel.isVisible, let anchorCanvasRect = viewModel.anchorCanvasRect {
                let resolvedScale = max(canvasScale, 0.001)
                let bubbleWidth: CGFloat = min(340, max(260, geo.size.width * 0.32))
                let projectedAnchor = CGRect(
                    x: anchorCanvasRect.minX * resolvedScale - canvasOffset.width,
                    y: anchorCanvasRect.minY * resolvedScale - canvasOffset.height,
                    width: anchorCanvasRect.width * resolvedScale,
                    height: anchorCanvasRect.height * resolvedScale
                )
                let placement = popupPlacement(
                    for: projectedAnchor,
                    in: geo.size,
                    bubbleWidth: bubbleWidth,
                    bubbleHeight: measuredBubbleHeight
                )
                let liveOffset = CGSize(
                    width: viewModel.popupOffset.width + dragTranslation.width,
                    height: viewModel.popupOffset.height + dragTranslation.height
                )
                let finalCenter = CGPoint(
                    x: placement.center.x + liveOffset.width,
                    y: placement.center.y + liveOffset.height
                )
                let liveBubbleHeight = min(max(180, measuredBubbleHeight), placement.maxBubbleHeight)
                let bubbleRect = CGRect(
                    x: finalCenter.x - bubbleWidth / 2,
                    y: finalCenter.y - liveBubbleHeight / 2,
                    width: bubbleWidth,
                    height: liveBubbleHeight
                )
                let connector = connectorPoints(selectionRect: projectedAnchor, bubbleRect: bubbleRect)
                let sourceFrame = morphSourceFrame(for: projectedAnchor, in: geo.size)
                let interpolatedCenter = CGPoint(
                    x: interpolate(from: sourceFrame.midX, to: finalCenter.x, progress: morphProgress),
                    y: interpolate(from: sourceFrame.midY, to: finalCenter.y, progress: morphProgress)
                )
                let interpolatedScaleX = interpolate(
                    from: min(1, max(0.18, sourceFrame.width / bubbleWidth)),
                    to: 1,
                    progress: morphProgress
                )
                let interpolatedScaleY = interpolate(
                    from: min(1, max(0.18, sourceFrame.height / max(measuredBubbleHeight, 1))),
                    to: 1,
                    progress: morphProgress
                )
                let contentOpacity = max(0, min(1, (morphProgress - 0.22) / 0.78))
                
                ZStack(alignment: .topLeading) {
                    popupConnector(from: connector.start, to: connector.end)
                        .opacity(contentOpacity)
                    
                    bubble(width: bubbleWidth, maxBubbleHeight: placement.maxBubbleHeight)
                        .background(
                            GeometryReader { bubbleGeo in
                                Color.clear
                                    .onAppear {
                                        measuredBubbleHeight = bubbleGeo.size.height
                                    }
                                    .onChange(of: bubbleGeo.size.height) { _, newValue in
                                        measuredBubbleHeight = newValue
                                    }
                            }
                        )
                        .scaleEffect(x: interpolatedScaleX, y: interpolatedScaleY, anchor: morphAnchor(for: connector.end, relativeTo: finalCenter))
                        .opacity(interpolate(from: 0.82, to: 1, progress: morphProgress))
                        .position(x: interpolatedCenter.x, y: interpolatedCenter.y)
                }
                    .genieTransitionProgress(
                        morphProgress,
                        from: genieEdge(for: placement.side),
                        travel: 34
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .transaction { transaction in
                        if dragTranslation != .zero {
                            transaction.animation = nil
                        }
                    }
                    .zIndex(11)
            }
        }
        .allowsHitTesting(viewModel.isVisible)
        .onAppear {
            if viewModel.isVisible {
                startMorphAnimation()
            }
        }
        .onChange(of: viewModel.anchorCanvasRect) { _, newValue in
            guard newValue != nil else { return }
            startMorphAnimation()
        }
    }
    
    private func bubble(width: CGFloat, maxBubbleHeight: CGFloat) -> some View {
        let responseAreaHeight = min(
            max(72, measuredResponseHeight + 8),
            max(72, maxBubbleHeight - 122)
        )
        
        return VStack(spacing: 10) {
            header
            
            HStack(spacing: 10) {
                TextField("Ask about this selection…", text: $viewModel.prompt, axis: .vertical)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextPrimary)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                            .fill(Color.gElevated.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                    .stroke(Color.gBorder.opacity(0.25), lineWidth: 0.8)
                            )
                    )
                
                Button {
                    if viewModel.isStreaming {
                        viewModel.cancel()
                    } else {
                        Task { await viewModel.send() }
                    }
                } label: {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.gPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isStreaming && viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Divider().opacity(0.18)
            
            ScrollView {
                responseContent
                    .background(
                        GeometryReader { responseGeo in
                            Color.clear
                                .onAppear {
                                    measuredResponseHeight = responseGeo.size.height
                                }
                                .onChange(of: responseGeo.size.height) { _, newValue in
                                    measuredResponseHeight = newValue
                                }
                        }
                    )
            }
            .frame(height: responseAreaHeight)
        }
        .padding(12)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gSurface.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(Color.gBorder.opacity(0.28), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
    }
    
    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.isStreaming && viewModel.answer.isEmpty {
                Text("Thinking…")
                    .font(.gSubheadline.weight(.medium))
                    .foregroundColor(.gTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let error = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.gCaption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.canRetry {
                        Button {
                            Task { await viewModel.send() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.gPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !viewModel.answer.isEmpty {
                AIFormattedText(text: viewModel.answer, emphasis: .regular)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !viewModel.isStreaming {
                Text("Ask a question about what you selected.")
                    .font(.gCaption)
                    .foregroundColor(.gTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
    
    private func popupPlacement(
        for anchor: CGRect,
        in viewport: CGSize,
        bubbleWidth: CGFloat,
        bubbleHeight: CGFloat
    ) -> InlinePopupPlacement {
        let horizontalMargin: CGFloat = 12
        let verticalMargin: CGFloat = 14
        let tetherSpacing: CGFloat = 14
        let availableRight = viewport.width - anchor.maxX - horizontalMargin
        let availableLeft = anchor.minX - horizontalMargin
        let fitsRight = availableRight >= bubbleWidth + tetherSpacing
        let fitsLeft = availableLeft >= bubbleWidth + tetherSpacing
        let availableBelow = viewport.height - anchor.maxY - verticalMargin
        let availableAbove = anchor.minY - verticalMargin
        
        let clampedHeight = min(max(160, bubbleHeight), min(viewport.height - (verticalMargin * 2), 420))
        let side: InlinePopupSide
        if fitsRight {
            side = .right
        } else if fitsLeft {
            side = .left
        } else if availableBelow >= clampedHeight + tetherSpacing {
            side = .below
        } else if availableAbove >= clampedHeight + tetherSpacing {
            side = .above
        } else {
            let horizontalPreference = max(availableRight, availableLeft)
            let verticalPreference = max(availableBelow, availableAbove)
            if horizontalPreference >= verticalPreference {
                side = availableRight >= availableLeft ? .right : .left
            } else {
                side = availableBelow >= availableAbove ? .below : .above
            }
        }
        
        let maxBubbleHeight = max(160, min(viewport.height - (verticalMargin * 2), 420))
        let clampedBubbleHeight = min(maxBubbleHeight, max(180, clampedHeight))
        let idealY = anchor.minY + min(20, max(10, anchor.height * 0.2)) + clampedHeight / 2
        let centerY = min(
            max(verticalMargin + clampedBubbleHeight / 2, idealY),
            viewport.height - verticalMargin - clampedBubbleHeight / 2
        )
        
        let centerX: CGFloat
        let centerYResolved: CGFloat
        
        switch side {
        case .right:
            let preferredCenterX = anchor.maxX + tetherSpacing + bubbleWidth / 2
            centerX = min(
                max(preferredCenterX, horizontalMargin + bubbleWidth / 2),
                viewport.width - horizontalMargin - bubbleWidth / 2
            )
            centerYResolved = centerY
        case .left:
            let preferredCenterX = anchor.minX - tetherSpacing - bubbleWidth / 2
            centerX = min(
                max(preferredCenterX, horizontalMargin + bubbleWidth / 2),
                viewport.width - horizontalMargin - bubbleWidth / 2
            )
            centerYResolved = centerY
        case .below:
            centerX = min(
                max(anchor.midX, horizontalMargin + bubbleWidth / 2),
                viewport.width - horizontalMargin - bubbleWidth / 2
            )
            centerYResolved = min(
                max(anchor.maxY + tetherSpacing + clampedBubbleHeight / 2, verticalMargin + clampedBubbleHeight / 2),
                viewport.height - verticalMargin - clampedBubbleHeight / 2
            )
        case .above:
            centerX = min(
                max(anchor.midX, horizontalMargin + bubbleWidth / 2),
                viewport.width - horizontalMargin - bubbleWidth / 2
            )
            centerYResolved = min(
                max(anchor.minY - tetherSpacing - clampedBubbleHeight / 2, verticalMargin + clampedBubbleHeight / 2),
                viewport.height - verticalMargin - clampedBubbleHeight / 2
            )
        }

        return InlinePopupPlacement(
            center: CGPoint(x: centerX, y: centerYResolved),
            maxBubbleHeight: maxBubbleHeight,
            side: side
        )
    }

    private func genieEdge(for side: InlinePopupSide) -> Edge {
        switch side {
        case .left:
            return .trailing
        case .right:
            return .leading
        case .below:
            return .top
        case .above:
            return .bottom
        }
    }
    
    private func morphSourceFrame(for anchor: CGRect, in viewport: CGSize) -> CGRect {
        let minimumWidth: CGFloat = 52
        let minimumHeight: CGFloat = 40
        let clamped = anchor.intersection(CGRect(origin: .zero, size: viewport))
        let source = clamped.isNull || clamped.isEmpty ? CGRect(
            x: min(max(anchor.midX - 34, 12), viewport.width - 68),
            y: min(max(anchor.midY - 24, 12), viewport.height - 48),
            width: 68,
            height: 48
        ) : clamped
        
        return CGRect(
            x: source.midX - max(minimumWidth, source.width) / 2,
            y: source.midY - max(minimumHeight, source.height) / 2,
            width: max(minimumWidth, source.width),
            height: max(minimumHeight, source.height)
        )
    }
    
    private func morphAnchor(for connectorEnd: CGPoint, relativeTo center: CGPoint) -> UnitPoint {
        let x: CGFloat = connectorEnd.x < center.x ? 0 : (connectorEnd.x > center.x ? 1 : 0.5)
        let y: CGFloat = connectorEnd.y < center.y ? 0 : (connectorEnd.y > center.y ? 1 : 0.5)
        return UnitPoint(x: x, y: y)
    }
    
    private func interpolate(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }
    
    private func startMorphAnimation() {
        morphProgress = 0
        animateMotionSafe(GAnimation.springGentle) {
            morphProgress = 1
        }
    }
    
    private var popupDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                viewModel.popupOffset = CGSize(
                    width: viewModel.popupOffset.width + value.translation.width,
                    height: viewModel.popupOffset.height + value.translation.height
                )
            }
    }
    
    private func connectorPoints(selectionRect: CGRect, bubbleRect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let selectionCenter = CGPoint(x: selectionRect.midX, y: selectionRect.midY)
        let bubbleCenter = CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)
        
        return (
            start: edgePoint(on: selectionRect, toward: bubbleCenter),
            end: edgePoint(on: bubbleRect, toward: selectionCenter)
        )
    }
    
    private func edgePoint(on rect: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else {
            return CGPoint(x: rect.maxX, y: rect.midY)
        }
        
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        let scaleX = abs(dx) > 0.001 ? halfWidth / abs(dx) : .greatestFiniteMagnitude
        let scaleY = abs(dy) > 0.001 ? halfHeight / abs(dy) : .greatestFiniteMagnitude
        let scale = min(scaleX, scaleY)
        
        return CGPoint(
            x: center.x + dx * scale,
            y: center.y + dy * scale
        )
    }
    
    private func popupConnector(from start: CGPoint, to end: CGPoint) -> some View {
        return ZStack {
            Path { path in
                path.move(to: start)
                let controlOffset = abs(end.x - start.x) * 0.45
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + (end.x >= start.x ? controlOffset : -controlOffset), y: start.y),
                    control2: CGPoint(x: end.x - (end.x >= start.x ? controlOffset : -controlOffset), y: end.y)
                )
            }
            .stroke(
                Color.gPrimary.opacity(0.55),
                style: SwiftUI.StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: SwiftUI.CGLineCap.round,
                    lineJoin: SwiftUI.CGLineJoin.round
                )
            )
            
            Circle()
                .fill(Color.gPrimary)
                .frame(width: 8, height: 8)
                .position(start)
            
            Circle()
                .fill(Color.gPrimary.opacity(0.9))
                .frame(width: 6, height: 6)
                .position(end)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gPrimary)
                .frame(width: 22, height: 22)
                .background(Color.gPrimary.opacity(0.12))
                .clipShape(Circle())
            
            Text("AI")
                .font(.gSubheadline.weight(.semibold))
                .foregroundColor(.gTextPrimary)
            
            Spacer()
            
            Capsule()
                .fill(Color.gBorder.opacity(0.7))
                .frame(width: 34, height: 6)
                .frame(width: 52, height: 32)
                .contentShape(Rectangle())
                .highPriorityGesture(popupDragGesture)
            
            Button {
                viewModel.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gTextTertiary)
                    .frame(width: 30, height: 30)
                    .background(Color.gElevated.opacity(0.7))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close inline AI")
        }
    }
}

private struct InlinePopupPlacement {
    let center: CGPoint
    let maxBubbleHeight: CGFloat
    let side: InlinePopupSide
}

private enum InlinePopupSide {
    case left
    case right
    case below
    case above
}

private enum AttachmentContextKind {
    case none
    case image
    case capturedRegion

    var title: String {
        switch self {
        case .none:
            return "Attached context"
        case .image:
            return "Attached image"
        case .capturedRegion:
            return "Captured region"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            return "From this notebook"
        case .image:
            return "Ready to analyze"
        case .capturedRegion:
            return "From this page"
        }
    }
}

// MARK: - Extensions

extension String {
    var markdownAttributed: AttributedString {
        (try? AttributedString(markdown: normalizedMarkdownForAI, options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(normalizedMarkdownForAI)
    }
    
    fileprivate var normalizedMarkdownForAI: String {
        var text = self.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        text = text.replacingOccurrences(of: "||", with: "\n\n")
        text = text.replacingOccurrences(of: "\\#", with: "#")
        text = text.replacingOccurrences(of: "\\*", with: "*")
        text = text.replacingOccurrences(of: "\\-", with: "-")
        text = text.replacingOccurrences(of: "\\(", with: "(")
        text = text.replacingOccurrences(of: "\\)", with: ")")
        text = text.replacingOccurrences(of: "\\[", with: "[")
        text = text.replacingOccurrences(of: "\\]", with: "]")
        text = text.replacingOccurrences(of: "\\,", with: " ")
        text = text.replacingOccurrences(of: "\\cdot", with: "·")
        text = text.replacingOccurrences(of: "\\times", with: "×")
        text = text.replacingOccurrences(of: "\\left", with: "")
        text = text.replacingOccurrences(of: "\\right", with: "")
        text = text.replacingOccurrences(of: #"(?<!\n)(\d+\))\s+"#, with: "\n$1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<!\n)(Final answer:|Answer:|Summary:)"#, with: "\n$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<!\n)(=)\s*"#, with: "\n= ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
        
        let lines = text.components(separatedBy: .newlines)
        var normalized: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                if normalized.last?.isEmpty == false {
                    normalized.append("")
                }
                continue
            }
            
            let isHeading = trimmed.hasPrefix("#")
            let isBullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(of: #"^\d+\."#, options: .regularExpression) != nil
            let isMathLike = trimmed.contains("∫") || trimmed.contains("=") || trimmed.contains("→") || trimmed.contains(" dx") || trimmed.contains(" dy")
            
            if (isHeading || isBullet) && normalized.last?.isEmpty == false {
                normalized.append("")
            }
            
            if isMathLike && !isBullet && normalized.last?.isEmpty == false {
                normalized.append("")
            }
            
            normalized.append(line)
        }
        
        while normalized.last?.isEmpty == true {
            normalized.removeLast()
        }
        
        return normalized.joined(separator: "\n")
    }
}

// MARK: - AI Rich Text

private struct AIFormattedText: View {
    let text: String
    let emphasis: AITextEmphasis
    
    private var blocks: [AITextBlock] {
        AITextBlockParser.parse(text: text)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { item in
                blockView(item.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    
    @ViewBuilder
    private func blockView(_ block: AITextBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text.inlineMarkdownAttributed)
                .font(level == 1 ? .gHeadline : .gSubheadline.weight(.semibold))
                .foregroundColor(.gTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.gSubheadline.weight(.bold))
                    .foregroundColor(.gPrimary)
                Text(block.text.inlineMarkdownAttributed)
                    .font(emphasis.font)
                    .foregroundColor(.gTextPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
        case .math:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text.normalizedMathDisplayText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.gTextPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                            .fill(Color.gElevated.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                    .stroke(Color.gBorder.opacity(0.22), lineWidth: 0.8)
                            )
                    )
            }
            
        case .paragraph:
            Text(block.text.inlineMarkdownAttributed)
                .font(emphasis.font)
                .foregroundColor(.gTextPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum AITextEmphasis {
    case regular
    
    var font: Font {
        switch self {
        case .regular:
            return .gSubheadline
        }
    }
}

private struct AITextBlock {
    let kind: AITextBlockKind
    let text: String
}

private enum AITextBlockKind {
    case heading(level: Int)
    case bullet
    case math
    case paragraph
}

private enum AITextBlockParser {
    static func parse(text: String) -> [AITextBlock] {
        let normalized = text.normalizedMarkdownForAI
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return paragraphs.flatMap { paragraph -> [AITextBlock] in
            let lines = paragraph
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if lines.isEmpty { return [] }
            
            if lines.count == 1 {
                return [makeBlock(from: lines[0])]
            }
            
            if lines.allSatisfy({ isBulletLine($0) }) {
                return lines.map { makeBlock(from: $0) }
            }
            
            if lines.allSatisfy({ isMathLike($0) }) {
                return [AITextBlock(kind: .math, text: lines.joined(separator: "\n"))]
            }
            
            return lines.map { makeBlock(from: $0) }
        }
    }
    
    private static func makeBlock(from line: String) -> AITextBlock {
        if line.hasPrefix("### ") {
            return AITextBlock(kind: .heading(level: 3), text: String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return AITextBlock(kind: .heading(level: 2), text: String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return AITextBlock(kind: .heading(level: 1), text: String(line.dropFirst(2)))
        }
        if isBulletLine(line) {
            return AITextBlock(kind: .bullet, text: bulletText(from: line))
        }
        if isMathLike(line) {
            return AITextBlock(kind: .math, text: line)
        }
        return AITextBlock(kind: .paragraph, text: line)
    }
    
    private static func isBulletLine(_ line: String) -> Bool {
        line.hasPrefix("- ") ||
        line.hasPrefix("* ") ||
        line.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) != nil
    }
    
    private static func bulletText(from line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }
        return line.replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
    }
    
    private static func isMathLike(_ line: String) -> Bool {
        let symbolScore = [
            line.contains("∫"),
            line.contains("="),
            line.contains("dx"),
            line.contains("dy"),
            line.contains("\\frac"),
            line.contains("^"),
            line.contains("→"),
            line.contains("["),
            line.contains("]")
        ].filter { $0 }.count
        
        return symbolScore >= 2 || (symbolScore >= 1 && line.count <= 80)
    }
}

private extension String {
    var inlineMarkdownAttributed: AttributedString {
        (try? AttributedString(markdown: self, options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(self)
    }
    
    var normalizedMathDisplayText: String {
        var output = self
            .replacingOccurrences(of: "\\(", with: "(")
            .replacingOccurrences(of: "\\)", with: ")")
            .replacingOccurrences(of: "\\[", with: "[")
            .replacingOccurrences(of: "\\]", with: "]")
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\cdot", with: "·")
            .replacingOccurrences(of: "\\times", with: "×")
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
        
        output = output.replacingFractionCommands()
        output = output.replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
        return output
    }
    
    func replacingFractionCommands() -> String {
        let pattern = #"\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: "($1)/($2)"
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AIMessage
    let colorScheme: ColorScheme

    private var assistantBackground: Color {
        colorScheme == .dark ? Color(hex: "#1A1611") : Color(hex: "#F1EADC")
    }

    private var userBackground: Color {
        colorScheme == .dark ? Color(hex: "#2A2113") : Color(hex: "#E8D7AE")
    }

    private var assistantStroke: Color {
        colorScheme == .dark ? Color(hex: "#2E271D") : Color(hex: "#D8CBB4")
    }

    private let accent = Color(hex: "#C9A84C")

    private var bubbleText: Color {
        colorScheme == .dark ? Color(hex: "#F4EFE6") : Color(hex: "#241F18")
    }

    private var bubbleSubtext: Color {
        colorScheme == .dark ? Color(hex: "#9D9488") : Color(hex: "#7D7367")
    }

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 56) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background(accent)
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous))
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.gCaption2)
                            Text("Canvas context attached")
                                .font(.gCaption2)
                        }
                        .foregroundColor(bubbleSubtext)
                    }
                }

                if isUser {
                    Text(message.content.markdownAttributed)
                        .font(.gSubheadline)
                        .foregroundColor(bubbleText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else {
                    AIFormattedText(text: message.content, emphasis: .regular)
                }
            }
            .frame(maxWidth: isUser ? 320 : .infinity, alignment: isUser ? .trailing : .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                    .fill(isUser ? userBackground : assistantBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                            .stroke(isUser ? accent.opacity(0.3) : assistantStroke, lineWidth: 0.8)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "AI"): \(message.content)")
    }
}
