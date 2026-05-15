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
                AIChatView(viewModel: aiVM, drawing: canvasVM.currentPage.pkDrawing, onRegionCapture: {
                    showAIPanel = false
                    canvasVM.isRegionCaptureMode = true
                })
                    .frame(width: UIScreen.main.bounds.width * 0.3)
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
            AIChatView(viewModel: aiVM, drawing: canvasVM.currentPage.pkDrawing, onRegionCapture: {
                showAIPanel = false
                canvasVM.isRegionCaptureMode = true
            })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if let userId = authViewModel.currentUserId {
                await canvasVM.loadNotebook(notebook: notebook, userId: userId)
                
                aiVM.contextProvider = { [weak canvasVM] in
                    canvasVM?.canvasContextSummary() ?? ""
                }
                
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
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top Toolbar (auto-hides during drawing)
                if canvasVM.isToolbarVisible {
                    CanvasToolbar(
                        notebook: notebook,
                        viewModel: canvasVM,
                        onBack: { dismiss() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
                }

                ZStack(alignment: .leading) {
                    // Main Drawing Surface
                    ZStack {
                        // Route based on notebook canvas type
                        if notebook.canvasType == "fixed",
                           let dims = notebook.pageDimensions {
                            let pageSize = CGSize(width: dims.widthPt, height: dims.heightPt)
                            FixedCanvasView(viewModel: canvasVM, pageSize: pageSize)
                        } else {
                            PKCanvasRepresentable(
                                viewModel: canvasVM,
                                allowsFingerDrawing: !canvasVM.palmRejectionEnabled
                            )
                        }
                        
                        CustomLassoGestureView(viewModel: canvasVM)
                            .allowsHitTesting(canvasVM.selectedTool == .lasso)
                    }
                    .ignoresSafeArea(edges: [.horizontal, .bottom])

                    // Left-aligned controls
                    HStack(spacing: 0) {
                        // 1. Sidebar (always shown if toolbar is visible)
                        if canvasVM.isToolbarVisible {
                            CanvasSidebar(
                                viewModel: canvasVM,
                                onShowPages: { withAnimation { showPageStrip.toggle() } },
                                onShowPatterns: { showPatternPicker = true },
                                onShowAI: { withAnimation(GAnimation.spring) { showAIPanel.toggle() } },
                                isAIPanelVisible: showAIPanel,
                                onRegionCapture: {
                                    showAIPanel = false
                                    canvasVM.isRegionCaptureMode = true
                                }
                            )
                            .padding(.leading, 12)
                            .padding(.top, 16)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }

                        // 2. Page Manager (vertical list)
                        if showPageStrip && canvasVM.isToolbarVisible {
                            PageStripView(canvasVM: canvasVM)
                                .padding(.top, 16)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }

                        // 3. Properties Panel
                        if canvasVM.showProperties && canvasVM.isToolbarVisible {
                            PropertiesPanel(viewModel: canvasVM)
                                .padding(.leading, 12)
                                .padding(.top, 16)
                                .transition(.opacity)
                        }
                        
                        Spacer()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .zIndex(5)
                    
                    if canvasVM.isRegionCaptureMode {
                        RegionCaptureOverlay(canvasVM: canvasVM, aiVM: aiVM, showAIPanel: $showAIPanel)
                            .zIndex(10)
                            .transition(.opacity)
                    }

                    if canvasVM.isLassoSelectionActive, let box = canvasVM.lassoSelectionBox {
                        LassoSelectionOverlay(viewModel: canvasVM, box: box)
                            .zIndex(8)
                    }
                }
                .zIndex(1)
            }
            .tint(Color.gPrimary)
            .background(Color.gBackground.ignoresSafeArea())
        }
    }
}
