import SwiftUI

// MARK: - Quiz
//
// The answering surface for both multiple-choice and open-ended questions.
// The content sits in a centered reading column; the band that used to be
// empty below it now carries the session navigator.

struct FlashcardsQuizView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var answerFieldFocused: Bool

    private var isCompact: Bool { sizeClass == .compact }

    private var progress: Double {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Double(viewModel.currentQuestionIndex + (viewModel.hasSubmittedAnswer ? 1 : 0))
             / Double(viewModel.questions.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            FSessionBar(
                title: viewModel.notebookName,
                subtitle: "Question \(viewModel.currentQuestionIndex + 1) of \(viewModel.questions.count)",
                progress: progress,
                onClose: onClose,
                menu: AnyView(sessionMenu)
            )

            if let question = viewModel.currentQuestion {
                FCenteredColumn {
                    VStack(alignment: .leading, spacing: FMetrics.blockGap) {
                        Text(question.question)
                            .font(isCompact ? .fQuestionCompact : .fQuestion)
                            .foregroundColor(.gTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)

                        if question.kind == .multipleChoice {
                            optionList(question)
                        } else {
                            openEnded(question)
                        }

                        if viewModel.hasSubmittedAnswer {
                            resultBlock(question)
                                .transition(.opacity)
                        }
                    }
                    .animation(GAnimation.motionSafe(), value: viewModel.hasSubmittedAnswer)
                }

                footer
            } else {
                Spacer()
                Text("No questions in this session yet.")
                    .font(.fBody)
                    .foregroundColor(.gTextSecondary)
                Spacer()
            }
        }
        .background(Color.gBackground)
    }

    // MARK: Overflow

    private var sessionMenu: some View {
        Menu {
            Button {
                viewModel.restartCurrentSession()
            } label: {
                Label("Restart session", systemImage: "arrow.counterclockwise")
            }

            Button {
                viewModel.generateNewQuestions()
            } label: {
                Label("Generate new questions", systemImage: "sparkles")
            }

            if viewModel.answeredCount > 0 {
                Divider()
                Button {
                    viewModel.endSessionEarly()
                } label: {
                    Label("End and see results", systemImage: "flag.checkered")
                }
            }
        } label: {
            Image(systemName: "ellipsis").toolbarIconStyle()
        }
        .minTapTarget()
        .accessibilityLabel("Session options")
    }

    // MARK: Multiple choice

    private func optionList(_ question: FlashcardsQuestion) -> some View {
        VStack(spacing: FMetrics.rowGap) {
            ForEach((question.options ?? []).indices, id: \.self) { idx in
                FOptionRow(
                    letter: Self.letter(idx),
                    title: question.options?[idx] ?? "",
                    state: optionState(question: question, index: idx)
                ) {
                    viewModel.submitMultipleChoice(optionIndex: idx)
                }
            }
        }
    }

    private static func letter(_ index: Int) -> String {
        guard let scalar = UnicodeScalar(65 + index), index < 26 else { return "\(index + 1)" }
        return String(Character(scalar))
    }

    private func optionState(question: FlashcardsQuestion, index: Int) -> FOptionRow.State {
        guard viewModel.hasSubmittedAnswer else {
            return viewModel.selectedOptionIndex == index ? .selected : .idle
        }
        if index == question.correctIndex { return .correct }
        if viewModel.selectedOptionIndex == index { return .incorrect }
        return .dimmed
    }

    // MARK: Open ended

    @ViewBuilder
    private func openEnded(_ question: FlashcardsQuestion) -> some View {
        if viewModel.hasSubmittedAnswer {
            EmptyView() // the graded verdict card replaces the editor
        } else {
            VStack(alignment: .leading, spacing: FMetrics.rowGap) {
                ZStack(alignment: .topLeading) {
                    if viewModel.openEndedAnswerText.isEmpty {
                        Text("Type your answer…")
                            .font(.fBody)
                            .foregroundColor(.gTextTertiary)
                            .padding(.horizontal, FMetrics.cardPadding + 5)
                            .padding(.vertical, FMetrics.cardPadding + 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.openEndedAnswerText)
                        .font(.fBody)
                        .foregroundColor(.gTextPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($answerFieldFocused)
                        .frame(height: isCompact ? 130 : 156)
                        .padding(FMetrics.cardPadding)
                }
                .background(
                    RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                        .fill(Color.gSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                        .stroke(answerFieldFocused ? Color.gPrimary.opacity(0.55) : Color.gBorder,
                                lineWidth: answerFieldFocused ? 1.5 : 0.5)
                )
                .animation(GAnimation.motionSafe(GAnimation.springFast), value: answerFieldFocused)

                HStack(spacing: GSpacing.sm) {
                    Text("Graded on meaning, not exact wording")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)

                    Spacer(minLength: 0)

                    FPrimaryButton(
                        title: "Submit answer",
                        isLoading: viewModel.isGradingOpenEnded,
                        isDisabled: viewModel.openEndedAnswerText
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        answerFieldFocused = false
                        Task { await viewModel.submitOpenEnded() }
                    }
                }
            }
        }
    }

    // MARK: Revealed

    @ViewBuilder
    private func resultBlock(_ question: FlashcardsQuestion) -> some View {
        if question.kind == .openEnded {
            FGradedAnswerCard(
                isCorrect: isCurrentAnswerCorrect(question),
                isGrading: viewModel.isGradingOpenEnded,
                userAnswer: viewModel.openEndedAnswerText,
                expectedAnswer: question.expectedAnswer,
                feedback: viewModel.openEndedFeedback,
                stacked: isCompact
            )
        } else if let explanation = question.explanation, !explanation.isEmpty {
            FExplanationCard(
                explanation: explanation,
                quote: question.sourceQuote
            )
        }
    }

    private func isCurrentAnswerCorrect(_ question: FlashcardsQuestion) -> Bool {
        viewModel.outcomes[question.id] ?? false
    }

    // MARK: Footer
    //
    // Navigator on the left, primary action on the right. This is the band that
    // used to be empty space below the options.

    private var footer: some View {
        HStack(spacing: GSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                FQuestionNavigator(pips: viewModel.questionPips) { index in
                    animateMotionSafe(GAnimation.springFast) {
                        viewModel.goToQuestion(index)
                    }
                }
                if let source = sourceLabel {
                    FSourceLine(text: source)
                }
            }

            Spacer(minLength: 0)

            if viewModel.hasSubmittedAnswer {
                FPrimaryButton(
                    title: viewModel.currentQuestionIndex == viewModel.questions.count - 1 ? "Finish" : "Next"
                ) {
                    viewModel.nextQuestionOrFinish()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: FMetrics.contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, GSpacing.lg)
        .padding(.vertical, GSpacing.sm)
        .animation(GAnimation.motionSafe(), value: viewModel.hasSubmittedAnswer)
    }

    private var sourceLabel: String? {
        guard viewModel.hasSubmittedAnswer,
              let title = viewModel.currentQuestion?.sourcePageTitle,
              !title.isEmpty else { return nil }
        return "Source: \(viewModel.notebookName) / \(title)"
    }
}

// MARK: - Option row

struct FOptionRow: View {
    enum State {
        case idle, selected, correct, incorrect, dimmed
    }

    let letter: String
    let title: String
    let state: State
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                badge

                Text(title)
                    .font(.fBody)
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let tag {
                    Text(tag)
                        .font(.fMeta)
                        .foregroundColor(state == .correct ? .fCorrect : .fWrong)
                }
            }
            .padding(.horizontal, FMetrics.rowPaddingH)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .stroke(border, lineWidth: state == .selected || state == .correct || state == .incorrect ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(GScaleButtonStyle())
        .disabled(state != .idle && state != .selected)
        .animation(GAnimation.motionSafe(GAnimation.springFast), value: state)
        .accessibilityLabel("\(letter). \(title)")
        .accessibilityValue(tag ?? "")
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .correct:
            FBadge(systemName: "checkmark", tint: .fCorrect, size: 24)
        case .incorrect:
            FBadge(systemName: "xmark", tint: .fWrong, size: 24)
        case .selected:
            FLetterBadge(letter: letter, filled: true)
        case .idle, .dimmed:
            FLetterBadge(letter: letter)
        }
    }

    private var tag: String? {
        switch state {
        case .correct: return "Correct"
        case .incorrect: return "Your answer"
        default: return nil
        }
    }

    private var fill: Color {
        switch state {
        case .correct: return .fCorrectFill
        case .incorrect: return .fWrongFill
        case .dimmed: return Color.gSurface.opacity(0.5)
        default: return .gSurface
        }
    }

    private var border: Color {
        switch state {
        case .selected: return .gPrimary
        case .correct: return Color.fCorrect.opacity(0.45)
        case .incorrect: return Color.fWrong.opacity(0.45)
        case .dimmed: return Color.gBorder.opacity(0.4)
        case .idle: return .gBorder
        }
    }

    private var textColor: Color {
        state == .dimmed ? .gTextTertiary : .gTextPrimary
    }
}

// MARK: - Explanation

struct FExplanationCard: View {
    let explanation: String
    let quote: String?

    var body: some View {
        FCard(padding: FMetrics.rowPaddingH) {
            HStack(alignment: .top, spacing: 10) {
                FBadge(systemName: "info", tint: .gSecondary)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Explanation")
                        .font(.fMetaStrong)
                        .foregroundColor(.gTextPrimary)

                    Text(explanation)
                        .font(.fBody)
                        .foregroundColor(.gTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let quote, !quote.isEmpty {
                        Text("“\(quote)”")
                            .font(.fMeta)
                            .italic()
                            .foregroundColor(.gTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Graded open-ended answer
//
// Your answer and the expected answer sit side by side on regular width so the
// comparison reads in one glance and the card stays short.

struct FGradedAnswerCard: View {
    let isCorrect: Bool
    let isGrading: Bool
    let userAnswer: String
    let expectedAnswer: String?
    let feedback: String?
    var stacked: Bool = false

    var body: some View {
        FCard(padding: FMetrics.rowPaddingH) {
            VStack(alignment: .leading, spacing: FMetrics.blockGap) {
                verdict

                if stacked {
                    VStack(spacing: FMetrics.rowGap) { panels }
                } else {
                    HStack(alignment: .top, spacing: FMetrics.rowGap) { panels }
                }

                if let feedback, !feedback.isEmpty {
                    Divider().opacity(0.5)

                    HStack(alignment: .top, spacing: 10) {
                        FBadge(systemName: "info", tint: .gSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AI feedback")
                                .font(.fMetaStrong)
                                .foregroundColor(.gTextPrimary)
                            Text(feedback)
                                .font(.fBody)
                                .foregroundColor(.gTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var verdict: some View {
        HStack(spacing: 8) {
            if isGrading {
                ProgressView().tint(.gPrimary).scaleEffect(0.8)
                Text("Grading your answer…")
                    .font(.fBodyStrong)
                    .foregroundColor(.gTextSecondary)
            } else {
                FBadge(systemName: isCorrect ? "checkmark" : "xmark",
                       tint: isCorrect ? .fCorrect : .fWrong,
                       size: 24)
                Text(isCorrect ? "Correct" : "Not quite")
                    .font(.gTitle3)
                    .foregroundColor(isCorrect ? .fCorrect : .fWrong)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var panels: some View {
        FInsetPanel {
            VStack(alignment: .leading, spacing: 4) {
                FEyebrow(text: "Your answer")
                Text(userAnswer.isEmpty ? "—" : userAnswer)
                    .font(.fBody)
                    .foregroundColor(.gTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let expectedAnswer, !expectedAnswer.isEmpty {
            FInsetPanel(fill: .fCorrectFill) {
                VStack(alignment: .leading, spacing: 4) {
                    FEyebrow(text: "Expected answer", color: .fCorrect)
                    Text(expectedAnswer)
                        .font(.fBody)
                        .foregroundColor(.gTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
