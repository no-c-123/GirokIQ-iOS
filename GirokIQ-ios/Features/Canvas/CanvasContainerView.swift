import SwiftUI

/// Hosts the canvas toolbar, page strip, drawing surface, and AI panel.
/// Uses PencilKit (PKCanvasRepresentable) with a CATiledLayer background.
struct CanvasContainerView: View {
    let notebook: Notebook
    @StateObject private var canvasVM = CanvasViewModel()
    @StateObject private var aiVM = AIChatViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass

    @State private var showPageStrip = false
    @State private var showPatternPicker = false
    @State private var showAIPanel = false

    var body: some View {
        HStack(spacing: 0) {
            // Main canvas area
            canvasArea

            // iPad: side panel for AI
            if sizeClass == .regular && showAIPanel {
                AIChatView(viewModel: aiVM)
                    .frame(width: UIScreen.main.bounds.width * 0.38)
                    .background(Color.gSurface)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gBorder)
                            .frame(width: 0.5)
                    }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(GAnimation.motionSafe(), value: showAIPanel)
        .navigationBarHidden(true)
        .sheet(isPresented: $showPatternPicker) {
            PatternPickerSheet(
                selectedPattern: $canvasVM.backgroundPattern,
                onPatternChanged: { newPattern in
                    canvasVM.updateNotebookPattern(newPattern)
                }
            )
        }
        // iPhone: sheet for AI
        .sheet(isPresented: Binding(
            get: { sizeClass == .compact && showAIPanel },
            set: { if !$0 { showAIPanel = false } }
        )) {
            AIChatView(viewModel: aiVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if let userId = authViewModel.currentUserId {
                await canvasVM.loadNotebook(notebook: notebook, userId: userId)
                await aiVM.startSession(userId: userId, notebookId: notebook.id)
            }
        }
        .onDisappear {
            // Force save any pending strokes immediately before the view model is destroyed
            Task {
                await canvasVM.flushSave()
            }
        }
    }

    // MARK: - Canvas Area

    var canvasArea: some View {
        ZStack(alignment: .top) {
            // Route based on notebook canvas type
            if notebook.canvasType == "fixed",
               let dims = notebook.pageDimensions {
                let pageSize = CGSize(width: dims.widthPt, height: dims.heightPt)
                FixedCanvasView(viewModel: canvasVM, pageSize: pageSize)
                    .ignoresSafeArea()
            } else {
                PKCanvasRepresentable(
                    viewModel: canvasVM,
                    allowsFingerDrawing: !canvasVM.palmRejectionEnabled
                )
                .ignoresSafeArea()
            }

            // Top Toolbar (auto-hides during drawing)
            if canvasVM.isToolbarVisible {
                VStack(spacing: 0) {
                    CanvasToolbar(
                        notebook: notebook,
                        viewModel: canvasVM,
                        onBack: { dismiss() },
                        onShowPages: { withAnimation { showPageStrip.toggle() } },
                        onShowPatterns: { showPatternPicker = true },
                        onShowAI: {
                            withAnimation(GAnimation.spring) {
                                showAIPanel.toggle()
                            }
                        },
                        isAIPanelVisible: showAIPanel
                    )

                    if showPageStrip {
                        PageStripView(canvasVM: canvasVM)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Properties Panel
            if canvasVM.showProperties && canvasVM.isToolbarVisible {
                VStack {
                    Spacer().frame(height: showPageStrip ? 172 : 64)
                    HStack(alignment: .top) {
                        PropertiesPanel(viewModel: canvasVM)
                            .padding(.leading, 16)
                            .padding(.top, 8)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .tint(Color.gPrimary)
        // Finger touch detection is handled by TouchTypeRecognizer in PKCanvasRepresentable.
        // It calls viewModel.showToolbar() when a finger touch is detected.
    }
}
