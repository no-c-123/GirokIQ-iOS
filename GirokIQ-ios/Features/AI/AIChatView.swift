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
    var onRegionCapture: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider().opacity(0.2)

            if viewModel.showHistory {
                historyList
            } else {
                // Messages
                messageList

                Divider().opacity(0.2)

                // Input bar
                VStack(spacing: 0) {
                    if let imageData = viewModel.attachedImageData, let uiImage = UIImage(data: imageData) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                                .cornerRadius(GRadius.sm)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        viewModel.attachedImageData = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .padding(4)
                                }
                            Spacer()
                        }
                        .padding(.horizontal, GSpacing.md)
                        .padding(.top, GSpacing.sm)
                    }
                    inputBar
                }
            }
        }
        .background(Color.gSurface)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(imageData: $viewModel.attachedImageData)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    if let data = try? Data(contentsOf: url) {
                        viewModel.attachedImageData = data
                    }
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    // MARK: - Header

    var chatHeader: some View {
        HStack(spacing: GSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundColor(.gPrimary)
            
            Text("AI Assistant")
                .font(.custom("InstrumentSerif-Regular", size: 20))
                .foregroundColor(.gTextPrimary)
            
            Spacer()
            
            Button {
                withAnimation {
                    viewModel.showHistory.toggle()
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(viewModel.showHistory ? .gPrimary : .gTextTertiary)
            }
            .accessibilityLabel("Chat History")
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.top, GSpacing.md)
        .padding(.bottom, GSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Assistant")
    }

    // MARK: - History List
    
    var historyList: some View {
        ScrollView {
            LazyVStack(spacing: GSpacing.sm) {
                Button {
                    Task { await viewModel.startNewChat() }
                } label: {
                    HStack {
                        Image(systemName: "plus.message")
                        Text("New Chat")
                        Spacer()
                    }
                    .font(.gSubheadline)
                    .foregroundColor(.gPrimary)
                    .padding(GSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                            .fill(Color.gPrimary.opacity(0.1))
                    )
                }
                
                ForEach(viewModel.chatHistory) { chat in
                    Button {
                        Task { await viewModel.selectChat(chat) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.title)
                                    .font(.gSubheadline)
                                    .foregroundColor(.gTextPrimary)
                                    .lineLimit(1)
                                Text(chat.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.gCaption)
                                    .foregroundColor(.gTextTertiary)
                            }
                            Spacer()
                            if viewModel.chat?.id == chat.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.gPrimary)
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .padding(GSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(Color.gElevated)
                        )
                    }
                }
            }
            .padding(GSpacing.md)
        }
    }

    // MARK: - Message List

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GSpacing.sm) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        welcomeMessage
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, colorScheme: colorScheme)
                            .id(message.id)
                    }

                    // Streaming indicator
                    if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                        streamingBubble
                            .id("streaming")
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        errorBubble(error)
                    }
                }
                .padding(GSpacing.md)
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
        VStack(spacing: GSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.gPrimary.opacity(0.5))
            Text("Ask me anything about your canvas")
                .font(.gSubheadline)
                .foregroundColor(.gTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, GSpacing.sm)
            
            VStack(spacing: GSpacing.xs) {
                quickActionChip("Summarize this page")
                quickActionChip("Suggest a title for my notes")
                quickActionChip("What should I add next?")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, GSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask me anything about your canvas")
    }

    private func quickActionChip(_ text: String) -> some View {
        Button {
            if let drawing = drawing, !drawing.strokes.isEmpty {
                Task { await viewModel.sendWithVision(text: text, drawing: drawing) }
            } else {
                viewModel.inputText = text
                Task { await viewModel.sendMessage() }
            }
        } label: {
            Text(text)
                .font(.gSubheadline)
                .foregroundColor(.gPrimary)
                .padding(.horizontal, GSpacing.md)
                .padding(.vertical, GSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: GRadius.md)
                        .fill(Color.gPrimary.opacity(0.1))
                )
        }
    }

    var streamingBubble: some View {
        HStack(alignment: .top, spacing: GSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.gCaption)
                .foregroundColor(.gPrimary)
                .frame(width: 20, height: 20)

            Text(viewModel.streamingText.markdownAttributed)
                .font(.gSubheadline)
                .foregroundColor(.gTextPrimary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(GSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gElevated)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI is responding: \(viewModel.streamingText)")
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

    // MARK: - Input Bar

    var inputBar: some View {
        HStack(spacing: GSpacing.xs) {
            Menu {
                Button {
                    showImagePicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.gIconLarge)
                    .foregroundColor(.gPrimary)
            }
            .accessibilityLabel("Insert image or file")

            Button {
                onRegionCapture?()
            } label: {
                Image(systemName: "viewfinder.circle")
                    .font(.gIconLarge)
                    .foregroundColor(.gPrimary)
            }
            .accessibilityLabel("Region Capture")
            .accessibilityHint("Capture a specific region of the canvas")

            TextField("Ask something…", text: $viewModel.inputText, axis: .vertical)
                .font(.gSubheadline)
                .foregroundColor(.gTextPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .accessibilityLabel("Message input")
                .accessibilityHint("Type a question for the AI assistant")
                .padding(.horizontal, GSpacing.sm)
                .padding(.vertical, GSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .fill(Color.gElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .stroke(Color.gBorder, lineWidth: 0.5)
                        )
                )

            if viewModel.isStreaming {
                Button {
                    viewModel.cancelStream()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.gIconLarge)
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Stop generating")
                .accessibilityHint("Double tap to stop AI response")
            } else {
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.gIconLarge)
                        .foregroundColor(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .gTextTertiary
                            : .gPrimary
                        )
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message")
                .accessibilityHint("Double tap to send your message to the AI")
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, GSpacing.sm)
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
        HStack(alignment: .top, spacing: GSpacing.xs) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.gCaption)
                    .foregroundColor(.gPrimary)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: GSpacing.xxs) {
                if message.imageData != nil {
                    HStack(spacing: GSpacing.xxs) {
                        Image(systemName: "photo")
                            .font(.gCaption2)
                            .foregroundColor(.gTextTertiary)
                        Text("Canvas snapshot attached")
                            .font(.gCaption2)
                            .foregroundColor(.gTextTertiary)
                    }
                }

                Text(message.content.markdownAttributed)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextPrimary)
                    .textSelection(.enabled)
            }
            .padding(GSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(isUser ? Color.gPrimary.opacity(0.15) : Color.gElevated)
            )

            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "AI"): \(message.content)")
    }
}
