import SwiftUI

/// Hosts the canvas toolbar, page strip, drawing surface, and AI panel.
/// Uses PencilKit (PKCanvasRepresentable) with a CATiledLayer background.
struct CanvasContainerView: View {
    let notebook: Notebook
    @StateObject private var canvasVM = CanvasViewModel()
    @StateObject private var aiVM = AIChatViewModel()
    @StateObject private var inlineAIVM = InlineAIOverlayViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("aiPanelDockSide") private var aiPanelDockSide: AIChatPanelSide = .right
    @AppStorage("aiEnabled") private var aiEnabled: Bool = true

    @State private var showPageStrip = false
    @State private var showPatternPicker = false
    @State private var showAIPanel = false
    @State private var pickedCanvasImageData: Data? = nil

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if aiEnabled && sizeClass == .regular && showAIPanel && aiPanelDockSide == .left {
                    aiPanel(for: proxy.size)
                        .transition(.move(edge: .leading))
                }

                // Main canvas area
                canvasArea

                if aiEnabled && sizeClass == .regular && showAIPanel && aiPanelDockSide == .right {
                    aiPanel(for: proxy.size)
                        .transition(.move(edge: .trailing))
                }
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
            get: { aiEnabled && sizeClass == .compact && showAIPanel },
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
                canvasVM.joinPresence(notebookId: notebook.id, userId: userId)

                aiVM.contextProvider = { [weak canvasVM] in
                    canvasVM?.canvasContextSummary() ?? ""
                }

                inlineAIVM.contextProvider = { [weak canvasVM] in
                    canvasVM?.canvasContextSummary() ?? ""
                }
                
                inlineAIVM.onDismiss = { [weak canvasVM] in
                    canvasVM?.inlineAIHighlightRect = nil
                }
                
                if aiEnabled {
                    await aiVM.startSession(userId: userId, notebookId: notebook.id)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !PerfBisect.disableSceneRefresh else { return }
            Task {
                guard let userId = authViewModel.currentUserId else { return }
                let shouldRefresh = await canvasVM.shouldRefreshFromSceneActivation(userId: userId)
                guard shouldRefresh else {
                    await authViewModel.syncMonitor.pushPending()
                    return
                }
                await refreshNotebookContents(pushPendingFirst: true, flushBeforeRefresh: true)
            }
        }
        .onChange(of: aiEnabled) { _, enabled in
            if !enabled {
                showAIPanel = false
                canvasVM.isRegionCaptureMode = false
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
                canvasVM.leavePresence()
            }
        }
    }

    private func refreshNotebookContents(pushPendingFirst: Bool, flushBeforeRefresh: Bool) async {
        guard authViewModel.currentUserId != nil else { return }

        if flushBeforeRefresh {
            await canvasVM.flushSave()
        }

        if pushPendingFirst {
            await authViewModel.syncMonitor.pushPending()
        }

        await canvasVM.refreshNotebookFromRemote()
    }

    // MARK: - Canvas Area

    var canvasArea: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                CanvasToolbar(
                    notebook: notebook,
                    viewModel: canvasVM,
                    syncEngine: authViewModel.syncMonitor,
                    onBack: { dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)

                if Configuration.cloudSyncEnabled, let quotaNotice = canvasVM.quotaNoticeMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .foregroundColor(.orange)
                        Text(quotaNotice)
                            .font(.gCaption)
                            .foregroundColor(.gTextPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.gElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.gBorder.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
                }

                // Text tool formatting bar — full width, just below the top toolbar
                if canvasVM.selectedTool == .text {
                    TextToolKeyboardBar(viewModel: canvasVM)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(4)
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
                        
                        // Purely visual — the lasso pencil gesture is captured on the
                        // canvas host so fingers can still pan/zoom while lassoing.
                        CustomLassoGestureView(viewModel: canvasVM)
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea(edges: [.horizontal, .bottom])

                    // Left-aligned controls
                    HStack(spacing: 0) {
                        CanvasSidebar(
                            viewModel: canvasVM,
                            onShowPages: { withAnimation { showPageStrip.toggle() } },
                            onShowPatterns: { showPatternPicker = true },
                            onShowAI: { animateMotionSafe(GAnimation.spring) { showAIPanel.toggle() } },
                            isAIPanelVisible: showAIPanel,
                            isAIEnabled: aiEnabled,
                            onRegionCapture: {
                                showAIPanel = false
                                canvasVM.isRegionCaptureMode = true
                            },
                            onManualSync: {
                                Task {
                                    await canvasVM.flushSave()
                                    await authViewModel.syncMonitor.pushPending()
                                    HapticEngine.success()
                                }
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
                    
                    if aiEnabled && canvasVM.isRegionCaptureMode {
                        RegionCaptureOverlay(
                            canvasVM: canvasVM,
                            aiVM: aiVM,
                            showAIPanel: $showAIPanel,
                            onInlineAI: { canvasRect, imageData in
                                canvasVM.inlineAIHighlightRect = canvasRect
                                inlineAIVM.present(
                                    anchorCanvasRect: canvasRect,
                                    imageData: imageData
                                )
                            }
                        )
                            .zIndex(10)
                            .transition(.opacity)
                    }

                    if canvasVM.isLassoSelectionActive, let box = canvasVM.lassoSelectionBox {
                        LassoSelectionOverlay(
                            viewModel: canvasVM,
                            box: box,
                            onAskAI: { canvasRect, imageData in
                                guard aiEnabled else { return }
                                canvasVM.inlineAIHighlightRect = canvasRect
                                inlineAIVM.present(anchorCanvasRect: canvasRect, imageData: imageData)
                            }
                        )
                            .zIndex(8)
                    }

                    if let pt = canvasVM.canvasContextMenuPoint {
                        CanvasContextMenuOverlay(viewModel: canvasVM, canvasPoint: pt)
                            .zIndex(9)
                            .transition(.opacity)
                    }

                    InlineAIAnswerOverlay(
                        viewModel: inlineAIVM,
                        canvasScale: canvasVM.canvasScale,
                        canvasOffset: canvasVM.canvasOffset
                    )
                        .zIndex(11)

                    if let morph = canvasVM.shapeSnapMorph {
                        ShapeSnapMorphOverlay(viewModel: canvasVM, morph: morph)
                            .id(morph.id)
                            .allowsHitTesting(false)
                            .zIndex(12)
                    }
                }
                .zIndex(1)
            }
            .tint(Color.gPrimary)
            .background(Color.gBackground.ignoresSafeArea())
        }
    }

    private func aiPanel(for size: CGSize) -> some View {
        AIChatView(viewModel: aiVM, drawing: canvasVM.currentDrawing, onRegionCapture: {
            showAIPanel = false
            canvasVM.isRegionCaptureMode = true
        })
            .frame(width: aiPanelWidth(for: size))
            .background(aiPanelBackground)
            .overlay(alignment: aiPanelDockSide == .left ? .trailing : .leading) {
                Rectangle()
                    .fill(aiPanelDivider)
                    .frame(width: 0.5)
            }
    }

    private func aiPanelWidth(for size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        let ratio: CGFloat = isLandscape ? 0.27 : 0.36
        let rawWidth = size.width * ratio
        return min(max(rawWidth, 300), isLandscape ? 390 : 420)
    }

    private var aiPanelBackground: Color {
        colorScheme == .dark ? Color(hex: "#12100D") : Color(hex: "#F6F1E7")
    }

    private var aiPanelDivider: Color {
        colorScheme == .dark ? Color(hex: "#2B241B") : Color(hex: "#DDD2BE")
    }
}
