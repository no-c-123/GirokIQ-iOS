import SwiftUI

// MARK: - Focus mode
//
// The quiet surface: one card, question on the front, answer on the back, and a
// self-rating that feeds the SM-2 signal. Browsing chevrons flank the card on
// regular width and tuck under it when compact.

struct FlashcardsFocusView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    private var progress: Double {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Double(viewModel.currentQuestionIndex + 1) / Double(viewModel.questions.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            FSessionBar(
                title: viewModel.notebookName,
                subtitle: "Card \(viewModel.currentQuestionIndex + 1) of \(viewModel.questions.count)",
                progress: progress,
                onClose: onClose,
                menu: AnyView(menu)
            )

            if let question = viewModel.currentQuestion {
                VStack(spacing: FMetrics.blockGap) {
                    Spacer(minLength: GSpacing.sm)

                    cardRow(question)

                    if isCompact {
                        HStack(spacing: GSpacing.md) {
                            chevron(.backward)
                            chevron(.forward)
                        }
                    }

                    // One slot holds either the reveal button or the rating row,
                    // so the layout never jumps between the two states.
                    ZStack {
                        if viewModel.focusRevealed {
                            ratingRow
                        } else {
                            FPrimaryButton(title: "Reveal answer") {
                                animateMotionSafe { viewModel.focusReveal() }
                            }
                        }
                    }
                    .frame(height: 68)

                    Spacer(minLength: GSpacing.sm)
                }
                .padding(.horizontal, GSpacing.lg)
            } else {
                Spacer()
                Text("No cards in this session yet.")
                    .font(.fBody)
                    .foregroundColor(.gTextSecondary)
                Spacer()
            }
        }
        .background(Color.gBackground)
        .animation(GAnimation.motionSafe(), value: viewModel.focusRevealed)
        .animation(GAnimation.motionSafe(), value: viewModel.currentQuestionIndex)
    }

    private var menu: some View {
        Menu {
            Button {
                viewModel.restartCurrentSession()
            } label: {
                Label("Restart session", systemImage: "arrow.counterclockwise")
            }
            Button {
                viewModel.generateNewQuestions()
            } label: {
                Label("Generate new cards", systemImage: "sparkles")
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

    // MARK: Card

    @ViewBuilder
    private func cardRow(_ question: FlashcardsQuestion) -> some View {
        HStack(spacing: GSpacing.sm) {
            if !isCompact { chevron(.backward) }

            FocusCard(
                question: question,
                revealed: viewModel.focusRevealed,
                notebookName: viewModel.notebookName,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: FMetrics.focusCardWidth)

            if !isCompact { chevron(.forward) }
        }
        .frame(maxWidth: .infinity)
    }

    private enum Direction { case backward, forward }

    private func chevron(_ direction: Direction) -> some View {
        let enabled = direction == .backward ? viewModel.canFocusGoBack : viewModel.canFocusGoForward
        return Button {
            animateMotionSafe {
                direction == .backward ? viewModel.focusGoBack() : viewModel.focusGoForward()
            }
        } label: {
            Image(systemName: direction == .backward ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(enabled ? .gTextSecondary : .gTextTertiary.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.gElevated.opacity(enabled ? 0.8 : 0.3)))
                .contentShape(Circle())
        }
        .buttonStyle(GScaleButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(direction == .backward ? "Previous card" : "Next card")
    }

    // MARK: Rating

    private var ratingRow: some View {
        VStack(spacing: 8) {
            Text("Did you know it?")
                .font(.fMeta)
                .foregroundColor(.gTextTertiary)

            HStack(spacing: GSpacing.xs) {
                ForEach(FlashcardsSelfRating.allCases) { rating in
                    Button {
                        animateMotionSafe { viewModel.focusRateAndAdvance(rating) }
                    } label: {
                        Text(rating.title)
                            .font(.fMetaStrong)
                            .foregroundColor(rating == .easy ? .white : .gTextPrimary)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(
                                Capsule().fill(rating == .easy ? Color.gPrimary : Color.gElevated)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GScaleButtonStyle())
                }
            }
        }
        .transition(.opacity)
    }
}

// MARK: - The card itself

private struct FocusCard: View {
    let question: FlashcardsQuestion
    let revealed: Bool
    let notebookName: String
    let reduceMotion: Bool

    private var answerText: String {
        if let expected = question.expectedAnswer, !expected.isEmpty { return expected }
        if let options = question.options, let idx = question.correctIndex, options.indices.contains(idx) {
            return options[idx]
        }
        return "No answer recorded for this card."
    }

    /// Half-turn applied to the card, and again to its content so the back face
    /// reads the right way round instead of mirrored.
    private var flip: Double { reduceMotion ? 0 : (revealed ? 180 : 0) }

    var body: some View {
        face
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0))
            .padding(FMetrics.cardPadding + 4)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: revealed ? .topLeading : .center)
            .background(
                RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                    .fill(Color.gSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                    .stroke(Color.gBorder, lineWidth: 0.5)
            )
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .animation(GAnimation.motionSafe(GAnimation.springGentle), value: revealed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(revealed ? "Answer: \(answerText)" : "Question: \(question.question)")
    }

    private var face: some View {
        VStack(alignment: revealed ? .leading : .center, spacing: FMetrics.blockGap) {
            if revealed {
                // The prompt shrinks to a header so the answer owns the card.
                Text(question.question)
                    .font(.fBody)
                    .foregroundColor(.gTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)

                FEyebrow(text: "Answer", color: .gPrimary)

                Text(answerText)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.gTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let page = question.sourcePageTitle, !page.isEmpty {
                    FSourceLine(text: "Source: \(notebookName) / \(page)")
                }
            } else {
                Spacer(minLength: 0)

                FEyebrow(text: "Question")

                Text(question.question)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.gTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: revealed ? .leading : .center)
    }
}
