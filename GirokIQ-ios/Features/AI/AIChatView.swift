import SwiftUI

// MARK: - AI Chat View

struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider().opacity(0.2)

            // Messages
            messageList

            Divider().opacity(0.2)

            // Input bar
            inputBar
        }
        .background(Color.gSurface)
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
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.top, GSpacing.md)
        .padding(.bottom, GSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Assistant")
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, GSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask me anything about your canvas")
    }

    var streamingBubble: some View {
        HStack(alignment: .top, spacing: GSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.gCaption)
                .foregroundColor(.gPrimary)
                .frame(width: 20, height: 20)

            Text(viewModel.streamingText)
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

                Text(message.content)
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
