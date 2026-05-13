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
    @State private var showRegionCapture = false
    @State private var pendingCaptureData: Data? = nil
    @State private var canvasAreaFrame: CGRect = .zero

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Main canvas area
                canvasArea

                // iPad: side panel for AI
                if sizeClass == .regular && showAIPanel {
                    AIChatView(
                        viewModel: aiVM,
                        drawing: canvasVM.currentPage.pkDrawing,
                        pendingCaptureData: $pendingCaptureData,
                        onRequestRegionCapture: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRegionCapture = true
                            }
                        }
                    )
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

            // Fullscreen region capture overlay
            if showRegionCapture {
                CanvasRegionCaptureView(
                    canvasAreaFrame: canvasAreaFrame,
                    onCapture: { data in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRegionCapture = false
                        }
                        if let data {
                            pendingCaptureData = data
                            // Open AI panel if not already open
                            if !showAIPanel {
                                withAnimation(GAnimation.spring) {
                                    showAIPanel = true
                                }
                            }
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRegionCapture = false
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(100)
            }
        }
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
            AIChatView(
                viewModel: aiVM,
                drawing: canvasVM.currentPage.pkDrawing,
                pendingCaptureData: $pendingCaptureData,
                onRequestRegionCapture: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRegionCapture = true
                    }
                }
            )
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
                    
                    if showPageStrip {
                        PageStripView(canvasVM: canvasVM)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                ZStack(alignment: .leading) {
                    // PERFORMANCE: Paging Architecture
                    // Instead of reusing a single canvas instance, we use a TabView to host
                    // a separate canvas for each page. This avoids heavy drawing-swap hitches
                    // and lets PencilKit manage memory more efficiently for charged notebooks.
                    TabView(selection: $canvasVM.currentPageIndex) {
                        ForEach(canvasVM.pages.indices, id: \.self) { index in
                            canvasPage(at: index)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(edges: [.horizontal, .bottom])

                    // Left sidebar — shown when toolbar is visible
                    if canvasVM.isToolbarVisible {
                        HStack(spacing: 0) {
                            CanvasSidebar(
                                viewModel: canvasVM,
                                onShowPages: { withAnimation { showPageStrip.toggle() } },
                                onShowPatterns: { showPatternPicker = true },
                                onShowAI: { withAnimation(GAnimation.spring) { showAIPanel.toggle() } },
                                isAIPanelVisible:  showAIPanel
                            )
                            .padding(.leading, 12)
                            .padding(.top, 16)
                            Spacer(minLength: 0)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .zIndex(2)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Properties panel — keep existing placement (top-leading, offset to not overlap sidebar)
                    if canvasVM.showProperties && canvasVM.isToolbarVisible {
                        HStack(alignment: .top, spacing: 0) {
                            Spacer().frame(width: 76) // 52 sidebar + 12 leading + 12 gap
                            PropertiesPanel(viewModel: canvasVM)
                                .padding(.top, 8)
                            Spacer(minLength: 0)
                        }
                        .transition(.opacity)
                        .allowsHitTesting(true)
                        .zIndex(1)
                    }
                    
                    // Edit menu — strictly positioned on top of the canvas ZStack
                    CanvasEditMenu(viewModel: canvasVM)
                        .zIndex(500)
                }
                .zIndex(1)
            }
            .tint(Color.gPrimary)
            .background(Color.gBackground.ignoresSafeArea())
            .onAppear {
                canvasAreaFrame = geo.frame(in: .global)
            }
            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                canvasAreaFrame = newFrame
            }
        }
        // Finger touch detection is handled by TouchTypeRecognizer in PKCanvasRepresentable.
        // It calls viewModel.showToolbar() when a finger touch is detected.
    }

    @ViewBuilder
    private func canvasPage(at index: Int) -> some View {
        if notebook.canvasType == "fixed", let dims = notebook.pageDimensions {
            let pageSize = CGSize(width: dims.widthPt, height: dims.heightPt)
            FixedCanvasView(viewModel: canvasVM, pageIndex: index, pageSize: pageSize)
        } else {
            PKCanvasRepresentable(
                viewModel: canvasVM,
                pageIndex: index,
                allowsFingerDrawing: !canvasVM.palmRejectionEnabled
            )
        }
    }
}
