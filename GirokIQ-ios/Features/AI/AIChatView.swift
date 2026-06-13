import SwiftUI
import PencilKit
internal import UniformTypeIdentifiers

// MARK: - AI Chat View

struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    var drawing: PKDrawing?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showImagePicker = false
    @State private var showFileImporter = false
    @State private var attachedContextKind: AttachmentContextKind = .none
    var onRegionCapture: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().opacity(0.16)

            if viewModel.showHistory {
                historyList
            } else {
                messageList
                composerSection
            }
        }
        .background(Color.gSurface)
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
    }

    // MARK: - Header

    var chatHeader: some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.gPrimary.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notebook assistant")
                        .font(.custom("InstrumentSerif-Regular", size: 22))
                        .foregroundColor(.gTextPrimary)

                    Text(chatSubtitle)
                        .font(.gCaption)
                        .foregroundColor(.gTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                Button {
                    Task { await viewModel.startNewChat() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("New chat")
                            .font(.gSubheadline)
                    }
                    .foregroundColor(.gPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(GAnimation.springFast) {
                        viewModel.showHistory.toggle()
                    }
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(viewModel.showHistory ? .gPrimary : .gTextTertiary)
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
                    .foregroundColor(.gPrimary)
                    .padding(.horizontal, GSpacing.md)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                            .fill(Color.gPrimary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                
                ForEach(viewModel.chatHistory) { chat in
                    Button {
                        Task { await viewModel.selectChat(chat) }
                    } label: {
                        let isSelected = viewModel.chat?.id == chat.id
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.title)
                                    .font(.gSubheadline)
                                    .foregroundColor(.gTextPrimary)
                                    .lineLimit(1)
                                Text(historyTimestamp(for: chat))
                                    .font(.gCaption.weight(.medium))
                                    .foregroundColor(.gTextTertiary)
                            }
                            Spacer()
                            Circle()
                                .fill(isSelected ? Color.gPrimary : Color.clear)
                                .frame(width: 10, height: 10)
                        }
                        .padding(.horizontal, GSpacing.md)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                .fill(isSelected ? Color.gPrimary.opacity(0.07) : Color.gElevated.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                        .stroke(isSelected ? Color.gPrimary.opacity(0.9) : Color.gBorder.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("Chats are saved with this notebook")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextTertiary)
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
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.gPrimary.opacity(0.9))
                .frame(width: 54, height: 54)
                .background(Color.gPrimary.opacity(0.08))
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text("Ask anything about your notes")
                    .font(.gSubheadline.weight(.medium))
                    .foregroundColor(.gTextSecondary)
                Text("Use the current page, a captured region, or an attached image to get grounded answers.")
                    .font(.gCaption)
                    .foregroundColor(.gTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }

            VStack(spacing: 10) {
                quickActionChip("Summarize this page")
                quickActionChip("Explain these notes")
                quickActionChip("Turn this into an outline")
                quickActionChip("What should I add next?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 68)
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
            Text(text)
                .font(.gSubheadline)
                .foregroundColor(.gPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.gPrimary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gPrimary)
                Text("Thinking about your notes…")
                    .font(.gSubheadline.weight(.medium))
                    .foregroundColor(.gTextTertiary)
            }

            Text(viewModel.streamingText.markdownAttributed)
                .font(.gSubheadline)
                .foregroundColor(.gTextPrimary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gElevated.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(Color.gBorder.opacity(0.3), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notebook assistant is responding: \(viewModel.streamingText)")
    }

    func errorBubble(_ text: String) -> some View {
        HStack(spacing: GSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.gCaption)
                .foregroundColor(.red)
            Text(text)
                .font(.gCaption)
                .foregroundColor(.red)
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
        .background(Color.gSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gBorder.opacity(0.18))
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
        HStack {
            Label("Current page", systemImage: "square.on.square")
                .font(.gSubheadline)
                .foregroundColor(.gPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.gPrimary.opacity(0.08))
                )
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
                    .foregroundColor(.gTextPrimary)
                Text(attachedContextKind.subtitle)
                    .font(.gCaption)
                    .foregroundColor(.gTextTertiary)
            }

            Spacer()

            Button {
                viewModel.attachedImageData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gTextTertiary.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gElevated.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(Color.gBorder.opacity(0.35), lineWidth: 0.8)
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
                    .foregroundColor(.gTextPrimary)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type a question for the notebook assistant")
            }
            .background(
                Capsule(style: .continuous)
                    .fill(Color.gElevated.opacity(0.75))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.gBorder.opacity(0.35), lineWidth: 0.8)
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
            .foregroundColor(isFilled ? .white : .gPrimary)
            .frame(width: 42, height: 42)
            .background(isFilled ? Color.gPrimary : Color.gPrimary.opacity(0.08))
            .clipShape(Circle())
    }
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
        (try? AttributedString(markdown: self, options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(self)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AIMessage
    let colorScheme: ColorScheme

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 56) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gPrimary)
                    .frame(width: 24, height: 24)
                    .background(Color.gPrimary.opacity(0.08))
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
                        .foregroundColor(.gTextTertiary)
                    }
                }

                Text(message.content.markdownAttributed)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextPrimary)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                    .fill(isUser ? Color.gPrimary.opacity(0.14) : Color.gElevated.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                            .stroke(isUser ? Color.gPrimary.opacity(0.18) : Color.gBorder.opacity(0.28), lineWidth: 0.8)
                    )
            )

            if !isUser { Spacer(minLength: 56) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "AI"): \(message.content)")
    }
}
