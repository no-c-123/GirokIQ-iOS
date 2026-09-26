import SwiftUI

// MARK: - Review the generated questions
//
// Sits between generation and studying. The learner reads what the model
// produced, rewrites anything worded badly and deletes anything not worth
// answering.
//
// Answers are deliberately absent from this screen. Options, the correct
// index, the expected answer and the explanation all exist on the question by
// this point, and showing any of them here would let somebody memorise the
// answers before the quiz starts — which is exactly what the quiz is meant to
// measure. Only `question.question` and the page attribution are rendered.

struct FlashcardsReviewView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let onClose: () -> Void

    @FocusState private var focusedQuestion: UUID?
    @FocusState private var composerFocused: Bool

    @State private var newQuestionText: String = ""
    @State private var requestedCount: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.questions.isEmpty {
                emptyState
            } else {
                list
            }

            if viewModel.lastDeleted != nil {
                undoBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composer

            footer
        }
        .background(Color.gBackground)
        .animation(GAnimation.motionSafe(), value: viewModel.questions.count)
        .animation(GAnimation.motionSafe(), value: viewModel.lastDeleted?.question.id)
        .onChange(of: focusedQuestion) { previous, _ in
            // A field just lost focus: store what was typed into it.
            if previous != nil { viewModel.commitReviewEdits() }
        }
        .onDisappear { viewModel.commitReviewEdits() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            FModalHeader(
                title: "Review your questions",
                subtitle: viewModel.notebookName,
                onClose: onClose
            )

            HStack(spacing: GSpacing.xs) {
                Image(systemName: "eye.slash")
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
                Text("Answers stay hidden until you study. Tap any question to rewrite it.")
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, GSpacing.xs)
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.top, FMetrics.cardPadding)
        .padding(.bottom, FMetrics.blockGap)
        .frame(maxWidth: FMetrics.contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(spacing: GSpacing.sm) {
                ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                    row(index: index, question: question)
                }
            }
            .padding(.horizontal, FMetrics.cardPadding)
            .padding(.bottom, FMetrics.blockGap)
            .frame(maxWidth: FMetrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(index: Int, question: FlashcardsQuestion) -> some View {
        FCard(padding: 0) {
            VStack(alignment: .leading, spacing: GSpacing.xs) {
                HStack(alignment: .top, spacing: GSpacing.sm) {
                    Text("\(index + 1)")
                        .font(.fMetaStrong)
                        .foregroundColor(.gTextTertiary)
                        .frame(width: 22, alignment: .leading)
                        .padding(.top, 2)

                    TextField(
                        "Question",
                        text: Binding(
                            get: { question.question },
                            set: { viewModel.updateQuestionText(id: question.id, to: $0) }
                        ),
                        axis: .vertical
                    )
                    .font(.fBody)
                    .foregroundColor(.gTextPrimary)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focusedQuestion, equals: question.id)
                    .submitLabel(.done)

                    Button {
                        focusedQuestion = nil
                        viewModel.deleteQuestion(id: question.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.fMeta)
                            .foregroundColor(.gTextTertiary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete question \(index + 1)")
                }

                HStack(spacing: GSpacing.xs) {
                    // The page it came from is context, not an answer.
                    if let source = question.sourcePageTitle, !source.isEmpty {
                        FSourceLine(text: source)
                    }
                    Spacer(minLength: 0)
                    Text(question.kind == .multipleChoice ? "Multiple choice" : "Open ended")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                }
                .padding(.leading, 22 + GSpacing.sm)
            }
            .padding(FMetrics.rowPaddingH)
        }
    }

    // MARK: Undo

    private var undoBar: some View {
        HStack(spacing: GSpacing.sm) {
            Text("Question deleted")
                .font(.fMeta)
                .foregroundColor(.gTextSecondary)
            Spacer(minLength: 0)
            Button("Undo") { viewModel.undoDelete() }
                .font(.fMetaStrong)
                .buttonStyle(.plain)
                .foregroundColor(.gPrimary)
        }
        .padding(.horizontal, FMetrics.rowPaddingH)
        .padding(.vertical, 10)
        .background(Color.fInset, in: RoundedRectangle(cornerRadius: GRadius.sm))
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.bottom, GSpacing.xs)
        .frame(maxWidth: FMetrics.contentWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: Composer

    /// Adds questions without leaving the review.
    ///
    /// One field, two ways out. "Ask AI" treats the text as a topic and asks
    /// for one, two or three questions about it. "Use as question" takes the
    /// text as the question itself and has the model work out the answer from
    /// the notes -- a question with no answer could not be graded.
    private var composer: some View {
        VStack(alignment: .leading, spacing: GSpacing.xs) {
            if let error = viewModel.addQuestionsError {
                HStack(alignment: .top, spacing: GSpacing.xs) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.fMeta)
                        .foregroundColor(.fWrong)
                    Text(error)
                        .font(.fMeta)
                        .foregroundColor(.fWrong)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") { viewModel.dismissAddQuestionsError() }
                        .font(.fMeta)
                        .buttonStyle(.plain)
                        .foregroundColor(.gTextTertiary)
                }
            }

            TextField(
                "Add a question, or a topic to ask about",
                text: $newQuestionText,
                axis: .vertical
            )
            .font(.fBody)
            .foregroundColor(.gTextPrimary)
            .textFieldStyle(.plain)
            .lineLimit(1...3)
            .focused($composerFocused)
            .disabled(viewModel.isAddingQuestions)
            .padding(FMetrics.rowPaddingH)
            .background(Color.fInset, in: RoundedRectangle(cornerRadius: GRadius.sm))

            HStack(spacing: GSpacing.xs) {
                if viewModel.isAddingQuestions {
                    ProgressView().controlSize(.small)
                    Text("Writing…")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                } else {
                    Text("How many")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)

                    ForEach(Array(FlashcardsQuestionEditor.additionRange), id: \.self) { count in
                        FChip(title: "\(count)", isSelected: requestedCount == count) {
                            requestedCount = count
                        }
                    }
                }

                Spacer(minLength: 0)

                FMiniButton(title: "Use as question") { submit(verbatim: true) }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)

                FPrimaryButton(title: "Ask AI") { submit(verbatim: false) }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
            }
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.bottom, GSpacing.xs)
        .frame(maxWidth: FMetrics.contentWidth)
        .frame(maxWidth: .infinity)
    }

    private var canSubmit: Bool {
        !viewModel.isAddingQuestions
            && !newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(verbatim: Bool) {
        let text = newQuestionText
        composerFocused = false
        Task {
            await viewModel.addQuestions(
                instruction: text,
                // A question used word for word is always exactly one.
                count: verbatim ? 1 : requestedCount,
                verbatim: verbatim
            )
            // Keep the text when it failed, so the learner does not have to
            // type it again to retry.
            if viewModel.addQuestionsError == nil { newQuestionText = "" }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: GSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.gTextTertiary)
            Text("No questions left")
                .font(.fBodyStrong)
                .foregroundColor(.gTextPrimary)
            Text("You deleted every question. Go back to generate a new set.")
                .font(.fMeta)
                .foregroundColor(.gTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(FMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.questions.count) question\(viewModel.questions.count == 1 ? "" : "s")")
                    .font(.fMetaStrong)
                    .foregroundColor(.gTextPrimary)
                Text(viewModel.canStartStudying
                     ? "Edit or delete before you begin"
                     : "Nothing left to study")
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
            }

            Spacer(minLength: 0)

            FSecondaryButton(title: "Back") {
                viewModel.commitReviewEdits()
                viewModel.screen = .configure
            }

            FPrimaryButton(title: "Start studying") {
                focusedQuestion = nil
                viewModel.commitReviewEdits()
                viewModel.beginPreparedSession()
            }
            .disabled(!viewModel.canStartStudying)
            .opacity(viewModel.canStartStudying ? 1 : 0.5)
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: FMetrics.contentWidth)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
