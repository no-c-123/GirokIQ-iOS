import SwiftUI
import UIKit

enum TextElementMetrics {
    static let editorInsets = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
    static let selectedHandleTopPadding: CGFloat = 22
    static let selectedHandleYOffsetCompensation: CGFloat = selectedHandleTopPadding / 2
    static let caretBottomAllowance: CGFloat = 4
}

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
                    .onTapGesture { location in
                        if viewModel.selectedTool == .text {
                            if viewModel.selectedElementIds.isEmpty {
                                // Nothing selected — place a new text block
                                let canvasX = location.x
                                let canvasY = location.y
                                viewModel.addTextElement(at: CGPoint(x: canvasX, y: canvasY))
                            } else {
                                // Something is selected — dismiss keyboard, deselect, then
                                // immediately place a new block at the tap location.
                                // This matches GoodNotes: every tap with the text tool places
                                // a block; it never wastes a tap on a "deselect only" step.
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil
                                )
                                viewModel.selectedElementIds = []
                                let canvasX = location.x
                                let canvasY = location.y
                                viewModel.addTextElement(at: CGPoint(x: canvasX, y: canvasY))
                            }
                        } else {
                            // Resign keyboard FIRST before clearing selection
                            // so UITextView has a chance to commit its content
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                            viewModel.selectedElementIds = []
                            if !viewModel.isToolbarVisible {
                                viewModel.showToolbar()
                            }
                        }
                    }



                ForEach(viewModel.pages[viewModel.currentPageIndex].elements) { element in
                    BlockElementView(element: element, viewModel: viewModel)
                }


            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // No transform — backgroundScrollView handles scroll/zoom automatically
        }
    }
}



// MARK: - TextEditorView (UIViewRepresentable replacing UIViewControllerRepresentable)

/// Hosts a UITextView directly as a UIViewRepresentable.
/// Using UIViewRepresentable instead of UIViewControllerRepresentable avoids
/// UIViewController containment, which fights CATransform3D applied to the
/// UIHostingController parent during pan/zoom — causing text blocks to disappear.
struct ScribbleFreeTextEditor: UIViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var textColor: UIColor
    var fontName: String?
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    var isStrikethrough: Bool
    var lineSpacing: CGFloat
    var textAlignment: NSTextAlignment
    var isEditable: Bool
    var isUserResized: Bool
    var fixedWidth: CGFloat
    var onEditingBegan: () -> Void
    var onEditingEnded: () -> Void
    var onNaturalSizeChanged: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PassthroughTextView {
        let tv = PassthroughTextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = TextElementMetrics.editorInsets
        tv.delegate = context.coordinator
        tv.isUserInteractionEnabled = isEditable

        let scribble = UIScribbleInteraction(delegate: context.coordinator)
        tv.addInteraction(scribble)

        return tv
    }

    func updateUIView(_ tv: PassthroughTextView, context: Context) {
        context.coordinator.parent = self

        // Font — apply bold/italic as symbolic traits
        let baseFont: UIFont
        if let name = fontName, let namedFont = UIFont(name: name, size: fontSize) {
            baseFont = namedFont
        } else {
            baseFont = UIFont.systemFont(ofSize: fontSize)
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold      { traits.insert(.traitBold) }
        if isItalic    { traits.insert(.traitItalic) }
        let font: UIFont
        if !traits.isEmpty,
           let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            font = baseFont
        }

        let isConstrained = isUserResized && fixedWidth > 0
        let constrainedTextWidth = max(
            1,
            fixedWidth - tv.textContainerInset.left - tv.textContainerInset.right
        )

        // Paragraph style
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = lineSpacing
        paraStyle.alignment = textAlignment
        // Important: UITextView wrapping respects paragraphStyle's lineBreakMode.
        // In resized mode we must force wrapping even for long runs of characters.
        paraStyle.lineBreakMode = isConstrained ? .byCharWrapping : .byClipping

        // Build attributes with underline and strikethrough
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paraStyle,
            .font: font,
            .foregroundColor: textColor
        ]
        if isUnderline     { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if isStrikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let newAttr = NSAttributedString(string: tv.text.isEmpty ? "" : tv.text, attributes: attrs)
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            tv.selectedRange = sel
        }
        if tv.attributedText != newAttr {
            let sel = tv.selectedRange
            tv.attributedText = NSAttributedString(string: text, attributes: attrs)
            tv.selectedRange = sel
        }
        tv.typingAttributes = attrs
        tv.textAlignment = textAlignment

        tv.isEditable = isEditable
        tv.isUserInteractionEnabled = isEditable

        if isEditable && !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
        if !isEditable && tv.isFirstResponder {
            tv.resignFirstResponder()
        }

        // Text container sizing
        if isConstrained {
            tv.textContainer.maximumNumberOfLines = 0
            tv.textContainer.lineBreakMode = .byCharWrapping
            // Explicitly size the textContainer based on the provided fixedWidth.
            // Relying on widthTracksTextView can fail during SwiftUI-driven resizing
            // because updateUIView may run before the UITextView's bounds update.
            tv.textContainer.widthTracksTextView = false
            tv.textContainer.size = CGSize(
                width: constrainedTextWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            tv.textContainer.maximumNumberOfLines = 1
            tv.textContainer.lineBreakMode = .byClipping
            tv.textContainer.widthTracksTextView = false
            tv.textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        // Force layout so wrapping takes effect immediately when width changes.
        tv.setNeedsLayout()
        tv.layoutIfNeeded()

        context.coordinator.measureAndReport(tv)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIScribbleInteractionDelegate {
        var parent: ScribbleFreeTextEditor
        private var lastReportedSize: CGSize = .zero

        init(parent: ScribbleFreeTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            measureAndReport(tv)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.onEditingBegan()
            measureAndReport(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            parent.onEditingEnded()
            measureAndReport(tv)
        }

        func measureAndReport(_ tv: UITextView) {
            let size: CGSize
            if parent.isUserResized && parent.fixedWidth > 0 {
                size = tv.sizeThatFits(CGSize(width: parent.fixedWidth, height: CGFloat.greatestFiniteMagnitude))
            } else {
                size = tv.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            }
            let rounded = CGSize(
                width:  (size.width  * 2).rounded() / 2,
                height: (size.height * 2).rounded() / 2
            )
            let roundedOld = CGSize(
                width:  (lastReportedSize.width  * 2).rounded() / 2,
                height: (lastReportedSize.height * 2).rounded() / 2
            )
            guard rounded != roundedOld else { return }
            lastReportedSize = rounded
            DispatchQueue.main.async { [weak self] in
                self?.parent.onNaturalSizeChanged(rounded)
            }
        }

        // MARK: UIScribbleInteractionDelegate
        func scribbleInteraction(_ interaction: UIScribbleInteraction,
                                 shouldBeginAt location: CGPoint) -> Bool {
            return parent.isEditable
        }
    }
}

// MARK: - PassthroughTextView

/// UITextView subclass that only accepts touches within its text content bounds,
/// letting touches on transparent areas fall through to SwiftUI underneath.
final class PassthroughTextView: UITextView {
    // Disable the system edit menu ("pills") for canvas textboxes.
    // We provide our own canvas context menu instead.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        // Only pass through touches when not editable (not selected).
        // When editable, return self so Scribble and keyboard input work.
        if result == self && !isEditable {
            return nil
        }
        return result
    }
}



struct BlockElementView: View {
    let element: CanvasElement
    @ObservedObject var viewModel: CanvasViewModel

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeDelta: CGSize = .zero
    @State private var loadedImage: UIImage? = nil
    @State private var textContent: String = ""
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var isEditing: Bool = false
    @State private var naturalContentSize: CGSize = .zero
    @State private var isCommittingResize: Bool = false

    var isSelected: Bool {
        viewModel.selectedElementIds.contains(element.id)
    }

    var body: some View {
        ZStack {
            elementContent
        }
        .frame(
            width: frameWidth,
            height: frameHeight
        )
        .overlay(selectionOverlay)
        // Padding exposes the overhanging handles to hit-testing without
        // shifting the visual frame. Compensated in .position() below.
        .padding(isSelected ? .init(top: TextElementMetrics.selectedHandleTopPadding, leading: 10, bottom: 0, trailing: 10) : .init())
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedElementIds = [element.id]
        }
        // No whole-block dragGesture — movement is via the top grabber only.
        .position(
            x: CGFloat(element.positionX) + dragOffset.width + frameWidth / 2,
            y: CGFloat(element.positionY) + dragOffset.height + frameHeight / 2 - (isSelected ? TextElementMetrics.selectedHandleYOffsetCompensation : 0)
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            // System keyboard dismiss button was tapped — deselect the block
            // so isEditable becomes false and the keyboard stays down
            if isSelected && viewModel.selectedTool == .text {
                viewModel.selectedElementIds = []
            }
        }
        .task(id: element.id) {
            if element.type == "text" {
                textContent = (element.content ?? "").replacingOccurrences(of: "\u{200B}", with: "")
            }
        }
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

    var frameWidth: CGFloat {
        if element.type == "text" && !element.userResized {
            return max(200, naturalContentSize.width + 16)
        }
        return max(60, CGFloat(element.width ?? 200) + (isSelected ? resizeDelta.width : 0))
    }

    var frameHeight: CGFloat {
        if element.type == "text" && !element.userResized {
            return max(32, naturalContentSize.height)
        }
        if element.type == "text" && element.userResized {
            let storedHeight = CGFloat(element.height ?? 200)
            let liveMeasuredHeight = max(
                60,
                naturalContentSize.height + TextElementMetrics.caretBottomAllowance
            )
            return max(storedHeight, liveMeasuredHeight) + (isSelected ? resizeDelta.height : 0)
        }
        return max(60, CGFloat(element.height ?? 200) + (isSelected ? resizeDelta.height : 0))
    }

    // MARK: - Content

    @ViewBuilder
    var elementContent: some View {
        if element.type == "image" {
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
        } else if element.type == "text" {
            let isEditingNow = isSelected && viewModel.selectedTool == .text
            ZStack(alignment: .topLeading) {
                ScribbleFreeTextEditor(
                    text: $textContent,
                    fontSize: element.style?.fontSize ?? 16,
                    textColor: element.style?.textColor != nil
                        ? UIColor(Color(hex: element.style!.textColor!))
                        : UIColor.label,
                    fontName: element.style?.fontName,
                    isBold: element.style?.isBold ?? false,
                    isItalic: element.style?.isItalic ?? false,
                    isUnderline: element.style?.isUnderline ?? false,
                    isStrikethrough: element.style?.isStrikethrough ?? false,
                    lineSpacing: CGFloat(element.style?.lineSpacing ?? 0),
                    textAlignment: {
                        switch element.style?.textAlignment {
                        case "center": return .center
                        case "right":  return .right
                        case "justified": return .justified
                        default:       return .left
                        }
                    }(),
                    isEditable: isEditingNow,
                    isUserResized: element.userResized,
                    fixedWidth: frameWidth,
                    onEditingBegan: { isEditing = true },
                    onEditingEnded: { isEditing = false },
                    onNaturalSizeChanged: { size in
                        naturalContentSize = size
                    }
                )
                .frame(width: frameWidth, height: frameHeight, alignment: .topLeading)
                .clipped()
                .onChange(of: naturalContentSize) { _, size in
                    // naturalContentSize is in canvas space (reported by UITextView).
                    // All comparisons and writes must stay in canvas space.
                    guard element.type == "text", !isCommittingResize else { return }
                    var updated = element
                    if element.userResized {
                        // In fixed/resized mode, only height auto-grows to fit content
                        let newHeight = max(32, size.height + TextElementMetrics.caretBottomAllowance)
                        let roundedNew = (newHeight * 2).rounded() / 2
                        let roundedOld = ((CGFloat(element.height ?? 32)) * 2).rounded() / 2
                        guard roundedNew != roundedOld else { return }
                        updated.height = Double(roundedNew)
                        viewModel.updateElement(updated)
                    } else {
                        // In free mode, both width and height follow content
                        let newWidth = max(200, size.width + 16)
                        let newHeight = max(32, size.height + TextElementMetrics.caretBottomAllowance)
                        let roundedNewW = (newWidth * 2).rounded() / 2
                        let roundedNewH = (newHeight * 2).rounded() / 2
                        let roundedOldW = ((CGFloat(element.width ?? 200)) * 2).rounded() / 2
                        let roundedOldH = ((CGFloat(element.height ?? 32)) * 2).rounded() / 2
                        guard roundedNewW != roundedOldW || roundedNewH != roundedOldH else { return }
                        updated.width = Double(roundedNewW)
                        updated.height = Double(roundedNewH)
                        viewModel.updateElement(updated)
                    }
                }
                .onChange(of: textContent) { _, newValue in
                    let newContent = newValue.isEmpty ? "\u{200B}" : newValue
                    if element.content != newContent {
                        var updated = element
                        updated.content = newContent
                        saveTask?.cancel()
                        saveTask = Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            if !Task.isCancelled {
                                viewModel.updateElement(updated)
                            }
                        }
                    }
                }

                // Placeholder
                if textContent.isEmpty && !isEditing {
                    Text("Tap to type...")
                        .font(.system(size: element.style?.fontSize ?? 16))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, TextElementMetrics.editorInsets.top)
                        .padding(.leading, TextElementMetrics.editorInsets.left)
                        .allowsHitTesting(false)
                }
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
                var updated = element
                updated.positionX += value.translation.width / viewModel.canvasScale
                updated.positionY += value.translation.height / viewModel.canvasScale
                updated.updatedAt = Date()
                viewModel.updateElement(updated)
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
                let oldH = element.height ?? 50
                let newH = max(60, oldH + dh)
                
                // Suppress naturalContentSize onChange during this commit
                // to prevent a re-render loop (AttributeGraph cycle)
                isCommittingResize = true
                
                var updated = element
                // Shift center so the top-left remains fixed
                updated.positionX += (newW - oldW) / 2
                updated.positionY += (newH - oldH) / 2
                
                updated.width = newW
                updated.height = newH
                updated.userResized = true
                updated.updatedAt = Date()
                viewModel.updateElement(updated)
                
                // Re-enable after one run loop tick — long enough for
                // the resize render pass to complete without triggering onChange
                DispatchQueue.main.async {
                    isCommittingResize = false
                }
            }
    }

    /// Left-edge resize — drags left/right, grows/shrinks width from the left side.
    /// positionX shifts so the right edge stays fixed.
    var leftResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($resizeDelta) { value, state, _ in
                // Negative translation = dragging left = wider block
                let dw = -value.translation.width / viewModel.canvasScale
                state = CGSize(width: -dw, height: 0)
            }
            .onEnded { value in
                let dw = -value.translation.width / viewModel.canvasScale
                let oldW = element.width ?? Double(frameWidth)
                let newW = max(60, oldW + dw)
                isCommittingResize = true
                var updated = element
                // Right edge fixed: shift positionX left by the growth amount
                updated.positionX -= (newW - oldW)
                updated.width = newW
                updated.userResized = true
                updated.updatedAt = Date()
                viewModel.updateElement(updated)
                DispatchQueue.main.async { isCommittingResize = false }
            }
    }

    /// Right-edge resize — drags left/right, grows/shrinks width from the right side.
    /// positionX stays fixed (left edge is anchor).
    var rightResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($resizeDelta) { value, state, _ in
                let dw = value.translation.width / viewModel.canvasScale
                state = CGSize(width: dw, height: 0)
            }
            .onEnded { value in
                let dw = value.translation.width / viewModel.canvasScale
                let oldW = element.width ?? Double(frameWidth)
                let newW = max(60, oldW + dw)
                isCommittingResize = true
                var updated = element
                updated.width = newW
                updated.userResized = true
                updated.updatedAt = Date()
                viewModel.updateElement(updated)
                DispatchQueue.main.async { isCommittingResize = false }
            }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    var selectionOverlay: some View {
        if isSelected && element.type == "text" {
            ZStack {
                // Gold border
                Rectangle()
                    .stroke(Color.gPrimary, lineWidth: 1.5)

                // ── TOP GRABBER PILL ──
                // A draggable pill centred above the top edge. Drives the block's
                // position via dragGesture which updates $dragOffset.
                VStack {
                    ZStack {
                        Capsule()
                            .fill(Color.gPrimary)
                            .frame(width: 44, height: 22)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    // Float 14pt above the top border (offset upward by half height + gap)
                    .offset(y: -22)
                    .gesture(dragGesture)
                    .zIndex(10)
                    Spacer()
                }

                // ── LEFT RESIZE DOT ──
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.gPrimary)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: -10)
                    .highPriorityGesture(leftResizeGesture)
                    .zIndex(10)
                    Spacer()
                }

                // ── RIGHT RESIZE DOT ──
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.gPrimary)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 10)
                    .highPriorityGesture(rightResizeGesture)
                    .zIndex(10)
                }
            }
        } else if isSelected {
            // Non-text elements (images) keep the original overlay
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

// MARK: - Canvas Context Menu (empty canvas)

struct CanvasContextMenuOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasPoint: CGPoint

    private var screenPoint: CGPoint {
        let s = viewModel.canvasScale
        let ox = viewModel.canvasOffset.width
        let oy = viewModel.canvasOffset.height
        return CGPoint(
            x: canvasPoint.x * s - ox,
            y: canvasPoint.y * s - oy
        )
    }

    var body: some View {
        ZStack {
            // Dismiss layer
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.hideCanvasContextMenu() }

            // System-like pill menu (horizontal capsule)
            HStack(spacing: 0) {
                if viewModel.canCopySelection {
                    pillButton("Copy") {
                        viewModel.copyForCanvasMenu()
                        viewModel.hideCanvasContextMenu()
                    }
                    pillDivider()
                }
                pillButton("Paste", enabled: UIPasteboard.general.hasStrings || UIPasteboard.general.data(forPasteboardType: "com.apple.ink.drawing") != nil) {
                    viewModel.pasteForCanvasMenu(at: canvasPoint)
                    viewModel.hideCanvasContextMenu()
                }
                pillDivider()
                pillButton("Undo", enabled: viewModel.canUndo) {
                    viewModel.undo()
                    viewModel.hideCanvasContextMenu()
                }
                pillDivider()
                pillButton("Redo", enabled: viewModel.canRedo) {
                    viewModel.redo()
                    viewModel.hideCanvasContextMenu()
                }
                pillDivider()
                pillButton("Add Image") {
                    viewModel.selectTool(.image)
                    viewModel.hideCanvasContextMenu()
                }
            }
            .background(Color(hex: "#1A1A18").opacity(0.93))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            .position(x: screenPoint.x, y: max(70, screenPoint.y - 46))
        }
    }

    @ViewBuilder
    private func pillButton(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(enabled ? .white : .white.opacity(0.35))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func pillDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 0.5, height: 28)
    }
}
