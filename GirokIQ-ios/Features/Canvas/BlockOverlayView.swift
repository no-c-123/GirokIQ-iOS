import SwiftUI
import UIKit

/// A transparent overlay that sits on top of PKCanvasView to render and manage 
/// non-ink CanvasElements (Text, Images, etc.)
struct BlockOverlayView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var lassoStart: CGPoint? = nil
    @State private var lassoRect: CGRect? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Tap empty canvas to deselect
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedElementIds = []
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
                    BlockElementView(element: $element, viewModel: viewModel)
                }

                if viewModel.isResizing, let bbox = viewModel.selectionBoundingBox {
                    SelectionResizeOverlay(viewModel: viewModel, boundingBox: bbox)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // CORRECT transform: scale from top-left, then shift by raw scroll offset
            .scaleEffect(viewModel.canvasScale, anchor: .topLeading)
            .offset(
                x: -viewModel.canvasOffset.width,
                y: -viewModel.canvasOffset.height
            )
            // NO .animation() modifiers here — overlay must track canvas with zero latency
        }
    }
}

struct SelectionResizeOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let boundingBox: CGRect

    @GestureState private var resizeDelta: CGSize = .zero

    // Live-preview scaled box during drag
    var liveScale: CGFloat {
        guard boundingBox.width > 0 else { return 1 }
        let draggedWidth = boundingBox.width + resizeDelta.width
        return max(0.1, draggedWidth / boundingBox.width)
    }

    var liveBox: CGRect {
        CGRect(
            x: boundingBox.minX,
            y: boundingBox.minY,
            width: max(40, boundingBox.width  * liveScale),
            height: max(40, boundingBox.height * liveScale)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box border
            Rectangle()
                .stroke(Color.blue, style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: liveBox.width, height: liveBox.height)
                .position(x: liveBox.midX, y: liveBox.midY)
                .allowsHitTesting(false)

            // Resize handle — bottom right corner
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            // Position at bottom-right of live box
            .position(x: liveBox.maxX, y: liveBox.maxY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($resizeDelta) { value, state, _ in
                        state = CGSize(
                            width:  value.translation.width  / viewModel.canvasScale,
                            height: value.translation.height / viewModel.canvasScale
                        )
                    }
                    .onEnded { value in
                        viewModel.applySelectionResize(scale: liveScale)
                    }
            )

            // Dismiss resize mode — tap outside
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.isResizing = false
                }
                .allowsHitTesting(!viewModel.isResizing)
        }
    }
}

struct BlockElementView: View {
    @Binding var element: CanvasElement
    @ObservedObject var viewModel: CanvasViewModel

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
                        .gesture(resizeGesture)
                        // Prevent parent dragGesture from stealing this touch
                        .simultaneousGesture(TapGesture())
                        .zIndex(10)
                    }
                }
            }
        }
    }
}
