import SwiftUI

// MARK: - Flashcards (Study Mode)
//
// One host for the whole feature. Every screen is a full-bleed surface on the
// study background; setup steps present themselves as centered cards rather
// than sheets, so the flow never stacks a modal on a modal.

struct FlashcardsCoordinatorView: View {
    let notebook: Notebook
    let userId: UUID?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FlashcardsViewModel

    init(notebook: Notebook, userId: UUID?) {
        self.notebook = notebook
        self.userId = userId
        _viewModel = StateObject(wrappedValue: FlashcardsViewModel(notebook: notebook, userId: userId))
    }

    var body: some View {
        ZStack {
            Color.gBackground.ignoresSafeArea()

            // Generation takes over the whole surface while it runs.
            if viewModel.preparationState == .generating {
                FlashcardsGeneratingView(
                    summary: generationSummary,
                    onCancel: { viewModel.dismissPreparationModal() }
                )
                .transition(.opacity)
            } else if case .failed(let message) = viewModel.preparationState {
                FlashcardsErrorView(
                    title: "Couldn’t create your questions",
                    message: message,
                    onRetry: { Task { await viewModel.startSession() } },
                    onBack: { viewModel.dismissPreparationModal() },
                    onClose: { dismiss() }
                )
                .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(GAnimation.motionSafe(), value: viewModel.preparationState)
        .animation(GAnimation.motionSafe(), value: viewModel.screen)
        .task { await viewModel.load() }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.preparationState) { _, state in
            // Questions are ready: hand them to the learner to review before
            // studying, so a badly worded or irrelevant one can be fixed or
            // dropped instead of being answered.
            if state == .ready { viewModel.beginQuestionReview() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .selectContent:
            FlashcardsContentSelectionView(viewModel: viewModel, onClose: { dismiss() })

        case .configure:
            FlashcardsConfigureSessionView(
                viewModel: viewModel,
                notebookName: notebook.name,
                onClose: { dismiss() }
            )

        case .reviewQuestions:
            FlashcardsReviewView(viewModel: viewModel, onClose: { dismiss() })

        case .quiz:
            FlashcardsQuizView(viewModel: viewModel, onClose: { dismiss() })

        case .focus:
            FlashcardsFocusView(viewModel: viewModel, onClose: { dismiss() })

        case .results(let result):
            FlashcardsResultsView(viewModel: viewModel, result: result, onClose: { dismiss() })

        case .reviewMistakes(let result):
            FlashcardsMistakesView(
                viewModel: viewModel,
                result: result,
                onBack: { viewModel.screen = .results(result) },
                onClose: { dismiss() }
            )

        case .error(let title, let message):
            FlashcardsErrorView(
                title: title,
                message: message,
                onRetry: { viewModel.retryFromError() },
                onBack: { viewModel.retryFromError() },
                onClose: { dismiss() }
            )
        }
    }

    private var generationSummary: String {
        let pages = viewModel.config.selectedPageIds.count
        return "\(viewModel.config.questionCount) questions from \(pages) page\(pages == 1 ? "" : "s") · \(viewModel.config.difficulty.title)"
    }
}
