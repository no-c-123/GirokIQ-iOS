import SwiftUI
import UIKit

/// A transparent overlay that sits on top of PKCanvasView to render and manage 
/// non-ink CanvasElements (Text, Images, etc.)
struct BlockOverlayView: View {
    @ObservedObject var viewModel: CanvasViewModel


    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Tap empty canvas to deselect and show toolbar
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedElementIds = []
                        if !viewModel.isToolbarVisible {
                            viewModel.showToolbar()
                        }
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }



                ForEach($viewModel.pages[viewModel.currentPageIndex].elements) { $element in
                    BlockElementView(element: $element, viewModel: viewModel)
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
                        .highPriorityGesture(resizeGesture)
                        .zIndex(10)
                    }
                }
            }
        }
    }
}

struct LassoSelectionOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let box: CGRect
    @State private var showColorPicker = false
    @State private var pickedColor: Color = .white
    @State private var screenshotImage: UIImage? = nil
    @State private var showScreenshotPreview = false
    @GestureState private var resizeDelta: CGSize = .zero
    @GestureState private var moveDelta: CGSize = .zero

    // Convert canvas-space box to screen-space for rendering
    // Since this view is now in CanvasContainerView (screen space), we must project.
    var screenBox: CGRect {
        let s = viewModel.canvasScale
        let ox = viewModel.canvasOffset.width
        let oy = viewModel.canvasOffset.height
        return CGRect(
            x: box.minX * s - ox,
            y: box.minY * s - oy,
            width: box.width * s,
            height: box.height * s
        )
    }

    var liveScale: CGFloat {
        guard screenBox.width > 0 else { return 1 }
        return max(0.1, (screenBox.width + resizeDelta.width) / screenBox.width)
    }

    var liveBox: CGRect {
        let sb = screenBox
        return CGRect(
            x: sb.minX + moveDelta.width,
            y: sb.minY + moveDelta.height,
            width: max(40, sb.width * liveScale),
            height: max(40, sb.height * liveScale)
        )
    }

    var isNearTop: Bool {
        liveBox.minY < 180
    }

    var primaryPillY: CGFloat {
        isNearTop ? liveBox.maxY + 32 : liveBox.minY - 52
    }

    var secondaryPillY: CGFloat {
        isNearTop ? liveBox.maxY + 76 : liveBox.minY - 96
    }

    var colorPickerY: CGFloat {
        isNearTop ? liveBox.maxY + 124 : liveBox.minY - 144
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Draggable hit area inside the bounding box (invisible, for moving selection)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: liveBox.width, height: liveBox.height)
                .position(x: liveBox.midX, y: liveBox.midY)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .updating($moveDelta) { value, state, _ in
                            state = CGSize(
                                width: value.translation.width,
                                height: value.translation.height
                            )
                        }
                        .onEnded { value in
                            let dx = value.translation.width / viewModel.canvasScale
                            let dy = value.translation.height / viewModel.canvasScale
                            viewModel.applyLassoMove(translation: CGSize(width: dx, height: dy))
                        }
                )

            // Dashed bounding box (not hit-testable — ink must be tappable through it)
            Rectangle()
                .stroke(Color(hex: "#C9A84C"), style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: liveBox.width, height: liveBox.height)
                .position(x: liveBox.midX, y: liveBox.midY)
                .allowsHitTesting(false)

            // PRIMARY pill — Cut / Copy / Paste / Duplicate / Delete
            // Styled exactly like Apple's native edit menu: dark pill, text only
            HStack(spacing: 0) {
                pillButton("Cut") { viewModel.cutSelection() }
                pillDivider()
                pillButton("Copy") { viewModel.copySelection() }
                pillDivider()
                pillButton("Paste") { viewModel.pasteSelection() }
                pillDivider()
                pillButton("Duplicate") { viewModel.duplicateSelection() }
                pillDivider()
                pillButton("Delete", tint: .red) { viewModel.deleteSelectedLassoContent() }
            }
            .background(Color(hex: "#1A1A18").opacity(0.93))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .position(x: liveBox.midX, y: primaryPillY)

            // SECONDARY pill — Color / Resize / Screenshot
            HStack(spacing: 0) {
                pillButton("Color") { showColorPicker.toggle() }
                pillDivider()
                pillButton("Resize") { }
                    .opacity(0.5)
                    .allowsHitTesting(false)
                pillDivider()
                pillButton("Screenshot") {
                    if let img = viewModel.screenshotSelection() {
                        screenshotImage = img
                        showScreenshotPreview = true
                    }
                }
            }
            .background(Color(hex: "#1A1A18").opacity(0.93))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 6, y: 1)
            .position(x: liveBox.midX, y: secondaryPillY)
            .sheet(isPresented: $showScreenshotPreview) {
                if let img = screenshotImage {
                    LassoScreenshotPreview(image: img)
                }
            }

            // Color picker popover (appears above or below secondary pill)
            if showColorPicker {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Color.strokePresets, id: \.self) { preset in
                            Circle()
                                .fill(preset)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                                .onTapGesture {
                                    viewModel.applyLassoColorChange(preset)
                                    showColorPicker = false
                                }
                        }
                        
                        // Custom Color Picker disguised as rainbow swatch
                        ZStack {
                            Circle()
                                .fill(
                                    AngularGradient(
                                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                        center: .center
                                    )
                                )
                                .frame(width: 28, height: 28)
                            
                            ColorPicker("Custom", selection: $pickedColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 28, height: 28)
                                .opacity(0.01) // transparent but tappable
                                .onChange(of: pickedColor) { _, c in
                                    viewModel.applyLassoColorChange(c)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: 320)
                .background(Color(hex: "#1A1A18").opacity(0.95))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.4), radius: 12)
                .position(x: liveBox.midX, y: colorPickerY)
            }

            // Resize handle — bottom right corner, gold circle
            Circle()
                .fill(Color(hex: "#C9A84C"))
                .frame(width: 28, height: 28)
                .position(x: liveBox.maxX, y: liveBox.maxY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($resizeDelta) { value, state, _ in
                            state = CGSize(
                                width: value.translation.width,
                                height: value.translation.height
                            )
                        }
                        .onEnded { value in
                            // Compute scale from the final translation directly —
                            // liveScale cannot be used here because @GestureState
                            // resets to .zero before onEnded fires.
                            let sb = screenBox
                            guard sb.width > 0 else { return }
                            let finalScale = max(0.1, (sb.width + value.translation.width) / sb.width)
                            viewModel.applyLassoResize(scale: finalScale)
                        }
                )
        }
    }

    // Apple-style text pill button — no icon, just label
    @ViewBuilder
    private func pillButton(_ label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pillDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 0.5, height: 28)
    }
}
