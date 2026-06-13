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
    @State private var pickedCanvasImageData: Data? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Main canvas area
            canvasArea

            // iPad: side panel for AI
            if sizeClass == .regular && showAIPanel {
                AIChatView(viewModel: aiVM, drawing: canvasVM.currentDrawing, onRegionCapture: {
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            canvasVM.updateKeyboardHeight(frame.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            canvasVM.updateKeyboardHeight(0)
        }
        .onChange(of: canvasVM.selectedElementIds) { _, _ in
            // If the keyboard is up, keep the selected text block visible.
            canvasVM.ensureSelectedTextVisible()
        }
        .sheet(isPresented: $showPatternPicker) {
            PatternPickerSheet(
                selectedPattern: $canvasVM.backgroundPattern,
                onPatternChanged: { newPattern in
                    canvasVM.updateNotebookPattern(newPattern)
                }
            )
        }
        .sheet(isPresented: $canvasVM.showCanvasImagePicker, onDismiss: {
            if pickedCanvasImageData == nil {
                canvasVM.cancelPendingImageInsertion()
            }
        }) {
            ImagePicker(imageData: $pickedCanvasImageData)
        }
        // iPhone: sheet for AI
        .sheet(isPresented: Binding(
            get: { sizeClass == .compact && showAIPanel },
            set: { if !$0 { showAIPanel = false } }
        )) {
            AIChatView(viewModel: aiVM, drawing: canvasVM.currentDrawing, onRegionCapture: {
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
        .onChange(of: pickedCanvasImageData) { _, newValue in
            guard let data = newValue, let image = UIImage(data: data) else { return }
            canvasVM.insertImage(image, at: canvasVM.pendingImageInsertionPoint)
            pickedCanvasImageData = nil
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
                CanvasToolbar(
                    notebook: notebook,
                    viewModel: canvasVM,
                    onBack: { dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)

                // Text tool formatting bar — full width, just below the top toolbar
                if canvasVM.selectedTool == .text {
                    TextToolKeyboardBar(viewModel: canvasVM)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(3)
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

                        if showPageStrip {
                            PageStripView(canvasVM: canvasVM)
                                .padding(.top, 16)
                                .transition(.move(edge: .leading).combined(with: .opacity))
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

                    if let pt = canvasVM.canvasContextMenuPoint {
                        CanvasContextMenuOverlay(viewModel: canvasVM, canvasPoint: pt)
                            .zIndex(9)
                            .transition(.opacity)
                    }
                }
                .zIndex(1)
            }
            .tint(Color.gPrimary)
            .background(Color.gBackground.ignoresSafeArea())
        }
    }
}
