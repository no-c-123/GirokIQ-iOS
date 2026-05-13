import SwiftUI
import UIKit
import Combine

/// A transparent overlay that sits on top of PKCanvasView to render and manage 
/// non-ink CanvasElements (Text, Images, etc.)
struct BlockOverlayView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var lassoStart: CGPoint? = nil
    @State private var lassoRect: CGRect? = nil

    // Receive the canvas view directly from the parent to avoid VM-mediated scroll updates
    weak var canvasView: UIScrollView?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Tap empty canvas to deselect
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedElementIds = []
                        viewModel.isResizingSelection = false
                        viewModel.dismissEditMenu()
                        viewModel.selectionBoundingBox = nil
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }

                // Lasso selection rect
                if let rect = lassoRect {
                    Rectangle()
                        .stroke(Color.blue.opacity(0.7), style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .background(Color.blue.opacity(0.06))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                ForEach($viewModel.pages[viewModel.currentPageIndex].elements) { $element in
                    BlockElementView(
                        element: $element, 
                        viewModel: viewModel,
                        canvasScale: viewModel.canvasScale,
                        canvasOffset: viewModel.canvasOffset
                    )
                }

                // Resize overlay — inside the scaled ZStack so it matches canvas coordinates
                if let bbox = viewModel.selectionBoundingBox, !bbox.isEmpty {
                    if viewModel.isResizingSelection {
                        SelectionResizeOverlay(
                            boundingBox: bbox,
                            canvasScale: viewModel.canvasScale,
                            canvasOffset: viewModel.canvasOffset,
                            viewModel: viewModel
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // CORRECT transform: scale from top-left, then shift by raw scroll offset
            .scaleEffect(viewModel.canvasScale, anchor: .topLeading)
            .offset(
                x: -viewModel.canvasOffset.width,
                y: -viewModel.canvasOffset.height
            )
        }
    }
}

struct BlockElementView: View {
    @Binding var element: CanvasElement
    @ObservedObject var viewModel: CanvasViewModel
    let canvasScale: CGFloat
    let canvasOffset: CGSize

    @FocusState private var isFocused: Bool
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeDelta: CGSize = .zero
    @State private var removalTask: Task<Void, Never>? = nil
    @State private var hasCommittedText: Bool = false
    @State private var loadedImage: UIImage? = nil

    var isSelected: Bool {
        viewModel.selectedElementIds.contains(element.id)
    }

    var body: some View {
        ZStack {
            elementContent
        }
        .frame(
            width: max(60, CGFloat(element.width ?? 200) + (isSelected ? resizeDelta.width : 0)),
            height: element.type == "text"
                ? nil
                : max(60, CGFloat(element.height ?? 200) + (isSelected ? resizeDelta.height : 0))
        )
        .overlay(selectionOverlay)
        .position(
            x: CGFloat(element.positionX) + dragOffset.width,
            y: CGFloat(element.positionY) + dragOffset.height
        )
        .allowsHitTesting(true)
        .onTapGesture {
            viewModel.selectedElementIds = [element.id]
            isFocused = element.type == "text"
            viewModel.computeSelectionBoundingBox()
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                let screenX = element.positionX * canvasScale - canvasOffset.width
                let screenY = (element.positionY - (element.height ?? 200) / 2) * canvasScale - canvasOffset.height - 16
                viewModel.presentEditMenu(at: CGPoint(x: screenX, y: screenY))
                viewModel.computeSelectionBoundingBox()
            } else {
                viewModel.dismissEditMenu()
            }
        }
        .gesture(dragGesture)
        .task(id: element.content) {
            guard element.type == "image", let fileName = element.content,
                  !fileName.isEmpty else { return }

            if let cached = ImageCache.shared.retrieve(for: fileName) {
                loadedImage = cached
                return
            }

            let fileURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)

            let img = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: fileURL.path)
            }.value

            guard let img else { return }

            ImageCache.shared.store(img, for: fileName)
            loadedImage = img
        }
    }

    // MARK: - Content

    @ViewBuilder
    var elementContent: some View {
        if element.type == "text" {
            TextField("", text: Binding(
                get: {
                    let raw = element.content ?? ""
                    return raw == "\u{200B}" ? "" : raw
                },
                set: { newVal in
                    element.content = newVal.isEmpty ? "\u{200B}" : newVal
                }
            ), axis: .vertical)
            .focused($isFocused)
            .font(.system(size: element.style?.fontSize != nil ? CGFloat(element.style!.fontSize!) : 24))
            .foregroundColor(Color(hex: element.style?.textColor ?? "#000000"))
            .padding(8)
            .background(Color.clear)
            .onChange(of: isFocused) { _, focused in
                removalTask?.cancel()
                guard !focused else { return }
                let real = (element.content ?? "")
                    .replacingOccurrences(of: "\u{200B}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if real.isEmpty {
                    removalTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !Task.isCancelled else { return }
                        viewModel.removeElement(id: element.id)
                    }
                } else {
                    viewModel.updateElement(element)
                    hasCommittedText = true
                }
            }
            .onAppear {
                let raw = element.content ?? ""
                let isEmpty = raw.isEmpty || raw == "\u{200B}"
                if isEmpty { isFocused = true }
            }
        } else if element.type == "image" {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    var imageMissing: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(Text("Image Missing").foregroundColor(.white).font(.caption))
    }

    // MARK: - Drag Gesture (move)

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragOffset) { value, state, _ in
                guard isSelected else { return }
                state = CGSize(
                    width: value.translation.width / viewModel.canvasScale,
                    height: value.translation.height / viewModel.canvasScale
                )
            }
            .onEnded { value in
                guard isSelected else { return }
                element.positionX += value.translation.width / viewModel.canvasScale
                element.positionY += value.translation.height / viewModel.canvasScale
                element.updatedAt = Date()
                viewModel.updateElement(element)
            }
    }

    // MARK: - Resize Gesture

    var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($resizeDelta) { value, state, _ in
                state = CGSize(
                    width: value.translation.width / viewModel.canvasScale,
                    height: value.translation.height / viewModel.canvasScale
                )
            }
            .onEnded { value in
                let dw = value.translation.width / viewModel.canvasScale
                let dh = value.translation.height / viewModel.canvasScale
                let oldW = element.width ?? 200
                let newW = max(60, oldW + dw)
                if element.type == "text" {
                    element.positionX += (newW - oldW) / 2
                    element.width = newW
                } else {
                    let oldH = element.height ?? 50
                    let newH = max(60, oldH + dh)
                    
                    // Shift center so the top-left remains fixed
                    element.positionX += (newW - oldW) / 2
                    element.positionY += (newH - oldH) / 2
                    
                    element.width = newW
                    element.height = newH
                }
                element.updatedAt = Date()
                viewModel.updateElement(element)
            }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    var selectionOverlay: some View {
        if isSelected {
            ZStack {
                // Dashed border
                Rectangle()
                    .stroke(Color.blue, style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [5]))

                // Delete button — top right
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.removeElement(id: element.id)
                        } label: {
                            ZStack {
                                Circle().fill(Color.red).frame(width: 26, height: 26)
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: 13, y: -13)
                        .zIndex(10)
                    }
                    Spacer()
                }

                // Resize handle — bottom right
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 26, height: 26)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 13, y: 13)
                        .highPriorityGesture(resizeGesture)
                        .zIndex(10)
                    }
                }
            }
        }
    }
}

struct CanvasEditMenu: View { 
    @ObservedObject var viewModel: CanvasViewModel 
    
    var body: some View { 
        if viewModel.showEditMenu { 
            HStack(spacing: 4) { 
                menuButton(icon: "doc.on.doc",           label: "Copy")      { copy() } 
                menuButton(icon: "scissors",             label: "Cut")       { cut() } 
                menuButton(icon: "plus.square.on.square",label: "Duplicate") { duplicate() } 
                menuButton(icon: "arrow.up.left.and.arrow.down.right", label: "Resize") { resize() } 
                menuButton(icon: "camera.viewfinder",    label: "Screenshot") { screenshot() } 
                
                Divider() 
                    .frame(width: 0.5, height: 24) 
                    .background(Color(hex: "#1A1A18").opacity(0.25)) 
                    .padding(.horizontal, 2) 
                
                menuButton(icon: "trash", label: "Delete", destructive: true) { delete() } 
            } 
            .padding(.horizontal, 10) 
            .padding(.vertical, 6) 
            .background(Color(hex: "#C9A84C")) 
            .clipShape(Capsule()) 
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4) 
            .position(viewModel.editMenuScreenPosition) 
            .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)) 
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: viewModel.showEditMenu) 
            .zIndex(500) 
            .allowsHitTesting(true) 
        } 
    } 
    
    private func menuButton(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View { 
        Button(action: action) { 
            VStack(spacing: 3) { 
                Image(systemName: icon) 
                    .font(.system(size: 15, weight: .semibold)) 
                Text(label) 
                    .font(.system(size: 9, weight: .medium)) 
            } 
            .foregroundColor(destructive ? .red : Color(hex: "#1A1A18")) 
            .frame(width: 44, height: 40) 
        } 
        .buttonStyle(.plain) 
    } 
    
    private func copy()      { viewModel.performLassoAction(#selector(UIResponderStandardEditActions.copy(_:))) } 
    private func cut()       { viewModel.performLassoAction(#selector(UIResponderStandardEditActions.cut(_:))); viewModel.dismissEditMenu() } 
    private func delete()    { viewModel.performLassoAction(#selector(UIResponderStandardEditActions.delete(_:))); viewModel.dismissEditMenu() } 
    private func duplicate() { viewModel.performLassoAction(NSSelectorFromString("duplicate:")) } 
    private func resize()    { viewModel.isResizingSelection = true; viewModel.dismissEditMenu() } 
    private func screenshot() {
        guard let data = viewModel.renderSelectionToPNG(), let image = UIImage(data: data) else { return } 
        let ac = UIActivityViewController(activityItems: [image], applicationActivities: nil) 
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first, 
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return } 
        var topVC = rootVC 
        while let presented = topVC.presentedViewController { topVC = presented } 
        if let popover = ac.popoverPresentationController { 
            popover.sourceView = topVC.view 
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0) 
            popover.permittedArrowDirections = [] 
        } 
        topVC.present(ac, animated: true) 
    } 
}

/// The overlay that shows the bounding box and resize handles for the selection.
struct SelectionResizeOverlay: View {
    let boundingBox: CGRect
    let canvasScale: CGFloat
    let canvasOffset: CGSize
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        let currentWidth = boundingBox.width
        let currentHeight = boundingBox.height
        
        ZStack {
            // Dashed border
            Rectangle()
                .stroke(Color.blue, style: SwiftUI.StrokeStyle(lineWidth: 2.0, dash: [6]))
                .background(Color.blue.opacity(0.05))

            // Done button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        viewModel.isResizingSelection = false
                    } label: {
                        ZStack {
                            Circle().fill(Color.green).frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: 14, y: -14)
                    .zIndex(10)
                }
                Spacer()
            }

            // Resize handle — bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 28, height: 28)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 14, y: 14)
                    .highPriorityGesture(resizeGesture)
                    .zIndex(10)
                }
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        // Position at the center of the bounding box
        .position(
            x: boundingBox.midX,
            y: boundingBox.midY
        )
        .gesture(dragGesture)
    }
    
    var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.preResizeBoundingBox == nil {
                    viewModel.beginLiveResize()
                }
                let dw = value.translation.width / canvasScale
                let dh = value.translation.height / canvasScale
                viewModel.applySelectionResize(dw: dw, dh: dh, dx: 0, dy: 0)
            }
            .onEnded { value in
                if viewModel.preResizeBoundingBox == nil {
                    viewModel.beginLiveResize()
                }
                let dw = value.translation.width / canvasScale
                let dh = value.translation.height / canvasScale
                viewModel.applySelectionResize(dw: dw, dh: dh, dx: 0, dy: 0)
                viewModel.commitLiveResize()
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewModel.preResizeBoundingBox == nil {
                    viewModel.beginLiveResize()
                }
                let dx = value.translation.width / canvasScale
                let dy = value.translation.height / canvasScale
                viewModel.applySelectionResize(dw: 0, dh: 0, dx: dx, dy: dy)
            }
            .onEnded { value in
                if viewModel.preResizeBoundingBox == nil {
                    viewModel.beginLiveResize()
                }
                let dx = value.translation.width / canvasScale
                let dy = value.translation.height / canvasScale
                viewModel.applySelectionResize(dw: 0, dh: 0, dx: dx, dy: dy)
                viewModel.commitLiveResize()
            }
    }
}
