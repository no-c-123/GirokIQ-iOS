import SwiftUI

// MARK: - Setup surfaces
//
// Selecting content and configuring the session are presented as centered
// cards that hug their content. Nothing is pinned to the bottom of the screen,
// so the footer sits directly under the last row instead of leaving a gap.

/// Centers a setup card on the study background and caps how tall it can grow.
private struct FSetupStage<Content: View>: View {
    var maxWidth: CGFloat = FMetrics.modalWidth
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, GSpacing.lg)
                    .padding(.vertical, GSpacing.lg)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - 1. Select study content

struct FlashcardsContentSelectionView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let onClose: () -> Void

    private enum Scope { case entire, pick }

    /// Scope is explicit state rather than derived from the selection: picking
    /// every page by hand should not collapse the checklist back to "Entire
    /// notebook" under the learner.
    @State private var scope: Scope = .entire

    private var isWholeNotebook: Bool { scope == .entire }

    private var allSelected: Bool {
        !viewModel.pages.isEmpty && viewModel.config.selectedPageIds.count == viewModel.pages.count
    }

    var body: some View {
        FSetupStage {
            FCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    FModalHeader(
                        title: "Study",
                        subtitle: "Choose what to review",
                        onClose: onClose
                    )
                    .padding(.horizontal, FMetrics.cardPadding)
                    .padding(.top, FMetrics.cardPadding)
                    .padding(.bottom, FMetrics.blockGap)

                    if viewModel.isLoadingPages {
                        HStack(spacing: GSpacing.sm) {
                            ProgressView().tint(.gPrimary)
                            Text("Reading this notebook…")
                                .font(.fBody)
                                .foregroundColor(.gTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else if viewModel.pages.isEmpty {
                        Text("This notebook has no pages to study yet.")
                            .font(.fBody)
                            .foregroundColor(.gTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        scopeRows
                    }

                    Divider().opacity(0.5)

                    footer
                }
            }
        }
    }

    // MARK: Scope

    private var scopeRows: some View {
        VStack(spacing: FMetrics.rowGap) {
            FScopeRow(
                icon: "book.closed",
                title: "Entire notebook",
                subtitle: "All \(viewModel.pages.count) page\(viewModel.pages.count == 1 ? "" : "s")",
                isSelected: isWholeNotebook
            ) {
                animateMotionSafe {
                    scope = .entire
                    viewModel.config.selectedPageIds = Set(viewModel.pages.map(\.id))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                FScopeRow(
                    icon: "list.bullet",
                    title: "Select pages",
                    subtitle: isWholeNotebook
                        ? "Choose individual pages"
                        : "\(viewModel.config.selectedPageIds.count) of \(viewModel.pages.count) selected",
                    isSelected: !isWholeNotebook,
                    embedded: true
                ) {
                    animateMotionSafe { scope = .pick }
                }

                if !isWholeNotebook {
                    Divider().opacity(0.5)
                        .padding(.horizontal, FMetrics.rowPaddingH)

                    HStack(spacing: GSpacing.xs) {
                        FMiniButton(title: "Select all") {
                            animateMotionSafe {
                                viewModel.config.selectedPageIds = Set(viewModel.pages.map(\.id))
                            }
                        }
                        .disabled(allSelected)
                        FMiniButton(title: "Clear") {
                            animateMotionSafe { viewModel.config.selectedPageIds = [] }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, FMetrics.rowPaddingH)
                    .padding(.top, 4)

                    pageChecklist
                }
            }
            .background(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .fill(Color.gBackground.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .stroke(isWholeNotebook ? Color.gBorder : Color.gPrimary.opacity(0.55),
                            lineWidth: isWholeNotebook ? 0.5 : 1.5)
            )
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.bottom, FMetrics.blockGap)
    }

    private var pageChecklist: some View {
        // Caps at roughly six rows, then scrolls — the card never runs off screen
        // and never stretches past its content on short notebooks.
        ScrollView {
            VStack(spacing: 2) {
                ForEach(viewModel.pages) { page in
                    FPageRow(
                        page: page,
                        isSelected: viewModel.config.selectedPageIds.contains(page.id)
                    ) {
                        animateMotionSafe(GAnimation.springFast) {
                            if viewModel.config.selectedPageIds.contains(page.id) {
                                viewModel.config.selectedPageIds.remove(page.id)
                            } else {
                                viewModel.config.selectedPageIds.insert(page.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 264)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.config.selectedPageIds.isEmpty
                     ? "Nothing selected"
                     : "\(viewModel.config.selectedPageIds.count) page\(viewModel.config.selectedPageIds.count == 1 ? "" : "s") selected")
                    .font(.fMetaStrong)
                    .foregroundColor(.gTextPrimary)
                if let flagged = flaggedCount, flagged > 0 {
                    Text("\(flagged) with no readable text")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                }
            }

            Spacer(minLength: 0)

            FPrimaryButton(
                title: "Continue",
                isDisabled: !viewModel.canContinueFromSelection
            ) {
                viewModel.goToConfigure()
            }
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.vertical, 12)
    }

    private var flaggedCount: Int? {
        let count = viewModel.pages
            .filter { viewModel.config.selectedPageIds.contains($0.id) && !$0.hasReadableText }
            .count
        return count
    }
}

// MARK: Selection rows

private struct FScopeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    var embedded: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: GSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .gPrimary : .gTextTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                            .fill(isSelected ? Color.gPrimaryMuted : Color.gElevated)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.fBodyStrong)
                        .foregroundColor(.gTextPrimary)
                    Text(subtitle)
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                }

                Spacer(minLength: 0)

                FRadioMark(isSelected: isSelected)
            }
            .padding(.horizontal, FMetrics.rowPaddingH)
            .padding(.vertical, FMetrics.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .fill(Color.gBackground.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .stroke(isSelected ? Color.gPrimary.opacity(0.55) : Color.gBorder,
                                    lineWidth: isSelected ? 1.5 : 0.5)
                    )
            }
        }
    }
}

private struct FRadioMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.gPrimary : Color.clear)
                .overlay(Circle().stroke(isSelected ? Color.gPrimary : Color.gBorderStrong, lineWidth: 1.2))
                .frame(width: 20, height: 20)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
    }
}

private struct FPageRow: View {
    let page: FlashcardsPageItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.gPrimary : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isSelected ? Color.gPrimary : Color.gBorderStrong, lineWidth: 1.2)
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                    }
                }

                Text(page.title)
                    .font(.fBody)
                    .foregroundColor(page.hasReadableText ? .gTextPrimary : .gTextTertiary)
                    .lineLimit(1)

                Spacer(minLength: GSpacing.xs)

                if !page.hasReadableText {
                    Text("No readable text")
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.gElevated))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.gPrimary.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 2. Configure session

struct FlashcardsConfigureSessionView: View {
    @ObservedObject var viewModel: FlashcardsViewModel
    let notebookName: String
    let onClose: () -> Void

    private let presetCounts = [5, 10, 20]
    @State private var isCustomCount = false

    var body: some View {
        FSetupStage {
            FCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    FModalHeader(
                        title: "Create study session",
                        subtitle: notebookName,
                        onClose: onClose
                    )
                    .padding(.horizontal, FMetrics.cardPadding)
                    .padding(.top, FMetrics.cardPadding)
                    .padding(.bottom, FMetrics.blockGap)

                    VStack(alignment: .leading, spacing: FMetrics.sectionGap) {
                        studyMode
                        questionCount
                        difficulty
                    }
                    .padding(.horizontal, FMetrics.cardPadding)
                    .padding(.bottom, FMetrics.blockGap)

                    Divider().opacity(0.5)

                    contentRow

                    Divider().opacity(0.5)

                    footer
                }
            }
        }
        .onAppear {
            isCustomCount = !presetCounts.contains(viewModel.config.questionCount)
        }
    }

    // MARK: Sections

    private var studyMode: some View {
        VStack(alignment: .leading, spacing: FMetrics.rowGap) {
            FSectionLabel(title: "Study mode", hint: "How you want to be quizzed")

            FSegmented(
                items: FlashcardsStudyMode.allCases,
                title: { $0.title },
                selection: Binding(
                    get: { viewModel.config.studyMode },
                    set: { viewModel.config.studyMode = $0 }
                )
            )

            Text(viewModel.config.studyMode.blurb)
                .font(.fMeta)
                .foregroundColor(.gTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionCount: some View {
        VStack(alignment: .leading, spacing: FMetrics.rowGap) {
            FSectionLabel(title: "Number of questions", hint: nil)

            HStack(spacing: GSpacing.xs) {
                ForEach(presetCounts, id: \.self) { count in
                    FChip(
                        title: "\(count)",
                        isSelected: !isCustomCount && viewModel.config.questionCount == count
                    ) {
                        animateMotionSafe(GAnimation.springFast) {
                            isCustomCount = false
                            viewModel.config.questionCount = count
                        }
                    }
                }

                FChip(title: "Custom", isSelected: isCustomCount) {
                    animateMotionSafe(GAnimation.springFast) { isCustomCount = true }
                }

                Spacer(minLength: 0)

                if isCustomCount {
                    FStepper(
                        value: Binding(
                            get: { viewModel.config.questionCount },
                            set: { viewModel.config.questionCount = $0 }
                        ),
                        range: 3...30
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    private var difficulty: some View {
        VStack(alignment: .leading, spacing: FMetrics.rowGap) {
            FSectionLabel(title: "Difficulty", hint: nil)

            HStack(spacing: GSpacing.xs) {
                ForEach(FlashcardsDifficulty.allCases) { level in
                    FChip(title: level.title, isSelected: viewModel.config.difficulty == level) {
                        animateMotionSafe(GAnimation.springFast) { viewModel.config.difficulty = level }
                    }
                }
                Spacer(minLength: 0)
            }

            Text(viewModel.config.difficulty.blurb)
                .font(.fMeta)
                .foregroundColor(.gTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contentRow: some View {
        HStack(spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Content")
                    .font(.fBodyStrong)
                    .foregroundColor(.gTextPrimary)
                Text("\(viewModel.config.selectedPageIds.count) page\(viewModel.config.selectedPageIds.count == 1 ? "" : "s") selected")
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
            }

            Spacer(minLength: 0)

            FMiniButton(title: "Edit") { viewModel.goBackToSelection() }
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.config.questionCount) questions · \(viewModel.config.difficulty.title)")
                    .font(.fMetaStrong)
                    .foregroundColor(.gTextPrimary)
                Text("About \(viewModel.config.estimatedMinutes) min")
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
            }

            Spacer(minLength: 0)

            FSecondaryButton(title: "Back") { viewModel.goBackToSelection() }

            FPrimaryButton(title: "Generate") {
                Task { await viewModel.startSession() }
            }
        }
        .padding(.horizontal, FMetrics.cardPadding)
        .padding(.vertical, 12)
    }
}

private struct FSectionLabel: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.fSectionTitle)
                .foregroundColor(.gTextPrimary)
            if let hint {
                Text(hint)
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
            }
        }
    }
}

private struct FStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text("\(value)")
                .font(.fBodyStrong)
                .foregroundColor(.gTextPrimary)
                .monospacedDigit()
                .frame(minWidth: 30)

            stepButton(systemName: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(Color.gElevated))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number of questions")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(enabled ? .gTextPrimary : .gTextTertiary)
                .frame(width: 32, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 3. Generating

struct FlashcardsGeneratingView: View {
    let summary: String
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var spin = false

    private let stages = [
        "Analyzing your notes",
        "Identifying key concepts",
        "Creating questions",
        "Preparing your session"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark").toolbarIconStyle()
                }
                .minTapTarget()
                .accessibilityLabel("Cancel")
                Spacer()
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.top, GSpacing.xs)

            Spacer()

            VStack(spacing: FMetrics.sectionGap) {
                ring

                VStack(spacing: 10) {
                    ForEach(stages.indices, id: \.self) { idx in
                        stageLine(idx)
                    }
                }

                Text(summary)
                    .font(.fMeta)
                    .foregroundColor(.gTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, GSpacing.lg)

            Spacer()
        }
        .task { await runStages() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing questions. \(stages[min(stage, stages.count - 1)]).")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.gBorder.opacity(0.6), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Color.gPrimary, style: SwiftUI.StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: 46, height: 46)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    @ViewBuilder
    private func stageLine(_ idx: Int) -> some View {
        let isActive = idx == stage
        let isDone = idx < stage

        VStack(spacing: 5) {
            Text(stages[idx])
                .font(isActive ? .fBodyStrong : .fBody)
                .foregroundColor(isActive ? .gTextPrimary : isDone ? .gTextSecondary : .gTextTertiary)
                .multilineTextAlignment(.center)

            // The gold underline marks the active line without animating text.
            Capsule()
                .fill(isActive ? Color.gPrimary : Color.clear)
                .frame(width: isActive ? 120 : 0, height: 1.5)
        }
        .animation(GAnimation.motionSafe(), value: stage)
    }

    private func runStages() async {
        guard !reduceMotion else { return }
        // Walks the copy forward, then stops — generation itself decides when
        // this view goes away.
        while stage < stages.count - 1 {
            do {
                try await Task.sleep(nanoseconds: 1_100_000_000)
            } catch {
                return // cancelled when the view disappears
            }
            stage += 1
        }
    }
}

// MARK: - 4. Error

struct FlashcardsErrorView: View {
    let title: String
    let message: String
    var retryTitle: String = "Retry"
    let onRetry: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

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

            Spacer()

            FCard {
                VStack(alignment: .leading, spacing: FMetrics.blockGap) {
                    FBadge(systemName: "exclamationmark", tint: .fWrong, size: 26)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.gTitle3)
                            .foregroundColor(.gTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(.fBody)
                            .foregroundColor(.gTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: GSpacing.xs) {
                        FPrimaryButton(title: retryTitle, action: onRetry)
                        FSecondaryButton(title: "Back to setup", action: onBack)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, GSpacing.lg)

            Spacer()
        }
    }
}
