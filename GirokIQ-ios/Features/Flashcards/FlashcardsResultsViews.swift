import SwiftUI

// MARK: - Results
//
// Score hero, three stat tiles, the topics behind the misses, a per-question
// strip, and the four ways out. Instrument Serif appears here and nowhere else
// in the feature, on the hero numbers.

struct FlashcardsResultsView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let result: FlashcardsSessionResult
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var arcProgress: Double = 0
    @State private var shownScore: Int = 0

    private var isCompact: Bool { sizeClass == .compact }

    private var subtitle: String {
        [viewModel.notebookName,
         result.config.studyMode.title,
         result.config.difficulty.title].joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").toolbarIconStyle()
                }
                .minTapTarget()
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.top, GSpacing.xs)

            FCenteredColumn {
                VStack(alignment: .leading, spacing: FMetrics.blockGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Study complete")
                            .font(.gTitle2)
                            .foregroundColor(.gTextPrimary)
                        Text(subtitle)
                            .font(.fMeta)
                            .foregroundColor(.gTextTertiary)
                            .lineLimit(1)
                    }

                    heroCard

                    if !result.reviewTopics.isEmpty {
                        topicsCard
                    }

                    questionStrip

                    actions
                }
            }
        }
        .background(Color.gBackground)
        .task { await animateIn() }
    }

    // MARK: Hero

    private var heroCard: some View {
        FCard {
            let layout = isCompact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: FMetrics.blockGap))
                : AnyLayout(HStackLayout(alignment: .center, spacing: FMetrics.sectionGap))

            layout {
                scoreRing

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(result.correct)")
                            .font(.gScoreSerif)
                            .foregroundColor(.gTextPrimary)
                        Text("/ \(result.total)")
                            .font(.gDisplaySerif)
                            .foregroundColor(.gTextTertiary)
                    }

                    HStack(spacing: FMetrics.rowGap) {
                        FStatTile(label: "Correct", value: "\(result.correct)", tint: .fCorrect, fill: .fCorrectFill)
                        FStatTile(label: "Incorrect", value: "\(result.incorrect)", tint: .fWrong, fill: .fWrongFill)
                        FStatTile(label: "Time", value: result.elapsedText, tint: .gTextPrimary, fill: .fInset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gBorder.opacity(0.45), lineWidth: 8)
            Circle()
                .trim(from: 0, to: arcProgress)
                .stroke(Color.gPrimary, style: SwiftUI.StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(shownScore)%")
                .font(.gDisplaySerif)
                .foregroundColor(.gTextPrimary)
                .monospacedDigit()
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(result.scorePercent) percent, \(result.correct) of \(result.total) correct")
    }

    // MARK: Topics

    private var topicsCard: some View {
        FCard(padding: FMetrics.rowPaddingH) {
            VStack(alignment: .leading, spacing: FMetrics.rowGap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Topics to review")
                        .font(.fBodyStrong)
                        .foregroundColor(.gTextPrimary)
                    Text("Drawn from the pages you missed questions on")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                }

                FlowRow(spacing: 6) {
                    ForEach(result.reviewTopics, id: \.self) { topic in
                        FChip(title: topic, isInteractive: false)
                    }
                }
            }
        }
    }

    // MARK: Per-question strip

    private var questionStrip: some View {
        FCard(padding: FMetrics.rowPaddingH) {
            VStack(alignment: .leading, spacing: FMetrics.rowGap) {
                Text("Question by question")
                    .font(.fBodyStrong)
                    .foregroundColor(.gTextPrimary)

                FlowRow(spacing: 6) {
                    ForEach(Array(result.answered.enumerated()), id: \.element.id) { index, item in
                        FQuestionTick(number: index + 1, isCorrect: item.isCorrect)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        FlowRow(spacing: GSpacing.xs) {
            if !result.missed.isEmpty {
                FPrimaryButton(title: "Review mistakes") {
                    viewModel.showMistakes(from: result)
                }
            }
            FSecondaryButton(title: "Study again") { viewModel.restartCurrentSession() }
            FSecondaryButton(title: "Generate new questions") { viewModel.generateNewQuestions() }
            FSecondaryButton(title: "Done", action: onClose)
        }
    }

    // MARK: Entrance

    private func animateIn() async {
        guard !reduceMotion else {
            arcProgress = Double(result.scorePercent) / 100
            shownScore = result.scorePercent
            return
        }

        withAnimation(.easeOut(duration: 0.9)) {
            arcProgress = Double(result.scorePercent) / 100
        }

        // Count the hero number up once, in step with the arc.
        let target = result.scorePercent
        guard target > 0 else { return }
        let step = max(1, target / 40)
        var current = 0
        while current < target {
            do {
                try await Task.sleep(nanoseconds: 22_000_000)
            } catch {
                shownScore = target
                return
            }
            current = min(target, current + step)
            shownScore = current
        }
    }
}

// MARK: - Stat tile

struct FStatTile: View {
    let label: String
    let value: String
    let tint: Color
    let fill: Color

    var body: some View {
        FInsetPanel(fill: fill, padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                FEyebrow(text: label, color: tint.opacity(0.9))
                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.gTextPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Numbered tick

private struct FQuestionTick: View {
    let number: Int
    let isCorrect: Bool

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isCorrect ? .fCorrect : .fWrong)
            .monospacedDigit()
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isCorrect ? Color.fCorrectFill : Color.fWrongFill)
            )
            .accessibilityLabel("Question \(number), \(isCorrect ? "correct" : "incorrect")")
    }
}

// MARK: - Review mistakes

struct FlashcardsMistakesView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let result: FlashcardsSessionResult
    let onBack: () -> Void
    let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: GSpacing.sm) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").toolbarIconStyle()
                }
                .minTapTarget()
                .accessibilityLabel("Back to results")

                VStack(alignment: .leading, spacing: 1) {
                    Text("Review mistakes")
                        .font(.fMetaStrong)
                        .foregroundColor(.gTextPrimary)
                    Text("\(result.missed.count) missed")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.top, GSpacing.xs)
            .padding(.bottom, GSpacing.sm)

            FCenteredColumn {
                VStack(spacing: FMetrics.blockGap) {
                    ForEach(Array(result.missed.enumerated()), id: \.element.id) { index, item in
                        FMissedCard(
                            number: questionNumber(for: item) ?? index + 1,
                            item: item,
                            notebookName: viewModel.notebookName,
                            stacked: isCompact
                        )
                    }
                }
            }

            HStack(spacing: GSpacing.xs) {
                Spacer(minLength: 0)
                FSecondaryButton(title: "Retry these \(result.missed.count)") {
                    viewModel.retryMissed(from: result)
                }
                FPrimaryButton(title: "Done", action: onClose)
            }
            .frame(maxWidth: FMetrics.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, GSpacing.lg)
            .padding(.vertical, GSpacing.sm)
        }
        .background(Color.gBackground)
    }

    /// Position of this question in the original run, so the numbering matches
    /// what the learner saw during the session.
    private func questionNumber(for item: FlashcardsAnsweredQuestion) -> Int? {
        result.answered.firstIndex(where: { $0.id == item.id }).map { $0 + 1 }
    }
}

private struct FMissedCard: View {
    let number: Int
    let item: FlashcardsAnsweredQuestion
    let notebookName: String
    var stacked: Bool = false

    private var correctAnswer: String? {
        if let expected = item.question.expectedAnswer, !expected.isEmpty { return expected }
        if let options = item.question.options,
           let idx = item.question.correctIndex,
           options.indices.contains(idx) {
            return options[idx]
        }
        return nil
    }

    var body: some View {
        FCard(padding: FMetrics.rowPaddingH) {
            VStack(alignment: .leading, spacing: FMetrics.blockGap) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gTextTertiary)
                        .monospacedDigit()
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.gElevated))

                    Text(item.question.question)
                        .font(.fBodyStrong)
                        .foregroundColor(.gTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if stacked {
                    VStack(spacing: FMetrics.rowGap) { answerPanels }
                } else {
                    HStack(alignment: .top, spacing: FMetrics.rowGap) { answerPanels }
                }

                if let explanation = item.question.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(.fBody)
                        .foregroundColor(.gTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let page = item.question.sourcePageTitle, !page.isEmpty {
                    FSourceLine(text: "Source: \(notebookName) / \(page)")
                }
            }
        }
    }

    @ViewBuilder
    private var answerPanels: some View {
        FInsetPanel(fill: .fWrongFill) {
            VStack(alignment: .leading, spacing: 4) {
                FEyebrow(text: "Your answer", color: .fWrong)
                Text(item.userAnswer?.isEmpty == false ? item.userAnswer! : "No answer")
                    .font(.fBody)
                    .foregroundColor(.gTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let correctAnswer {
            FInsetPanel(fill: .fCorrectFill) {
                VStack(alignment: .leading, spacing: 4) {
                    FEyebrow(text: "Correct answer", color: .fCorrect)
                    Text(correctAnswer)
                        .font(.fBody)
                        .foregroundColor(.gTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Flow layout
//
// Wraps chips and buttons onto as many lines as they need, so a long row of
// actions or topics never overflows or truncates on narrow widths.

struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
