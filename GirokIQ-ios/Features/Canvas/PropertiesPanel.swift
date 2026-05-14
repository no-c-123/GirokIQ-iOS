import SwiftUI
import PencilKit

// MARK: - Properties Panel

struct PropertiesPanel: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            scrollContent
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.96))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .stroke(Color.gBorderStrong, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    var panelHeader: some View {
        EmptyView()
    }

    var scrollContent: some View {
        let closeAction = {
            animateMotionSafe(GAnimation.springFast) {
                viewModel.showProperties = false
            }
        }
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                
                if viewModel.selectedTool == .eraser {
                    // ERASER PROPERTIES
                    PropertySection(title: "Eraser Type", showCloseButton: true, onClose: closeAction) {
                        eraserTypeSelector
                    }
                } else if viewModel.selectedTool == .lasso || viewModel.selectedTool == .selection {
                    // LASSO PROPERTIES
                    PropertySection(title: "Lasso Actions", showCloseButton: true, onClose: closeAction) {
                        lassoActions
                    }
                } else if viewModel.selectedTool == .text {
                    // TEXT PROPERTIES
                    PropertySection(title: "Text Color", showCloseButton: true, onClose: closeAction) {
                        colorGrid
                    }
                    Divider().opacity(0.1)
                    PropertySection(title: "Opacity") {
                        opacitySlider
                    }
                    Divider().opacity(0.1)
                    PropertySection(title: "Actions") {
                        blockActions
                    }
                } else if viewModel.selectedTool == .image {
                    // IMAGE PROPERTIES
                    PropertySection(title: "Opacity", showCloseButton: true, onClose: closeAction) {
                        opacitySlider
                    }
                    Divider().opacity(0.1)
                    PropertySection(title: "Actions") {
                        blockActions
                    }
                } else {
                    // INKING TOOLS PROPERTIES
                    if viewModel.selectedTool == .pen {
                        PropertySection(title: "Pen Style", showCloseButton: true, onClose: closeAction) {
                            penStyleSelector
                        }
                        Divider().opacity(0.1)
                        PropertySection(title: "Stroke Color") {
                            colorGrid
                        }
                    } else {
                        PropertySection(title: "Stroke Color", showCloseButton: true, onClose: closeAction) {
                            colorGrid
                        }
                    }

                    Divider().opacity(0.1)

                    PropertySection(title: "Stroke Width") {
                        strokeWidthSelector
                    }

                    Divider().opacity(0.1)

                    PropertySection(title: "Opacity") {
                        opacitySlider
                    }
                }

                // ASSISTANTS (Hide for lasso, text, image, and eraser tools)
                if viewModel.selectedTool == .pen || viewModel.selectedTool == .pencil || viewModel.selectedTool == .marker {
                    Divider().opacity(0.1)

                    PropertySection(title: "Assistants") {
                        HStack {
                            Text("Palm Rejection")
                                .font(.gFootnote)
                                .foregroundColor(.gTextSecondary)
                            Spacer()
                            Toggle("Palm Rejection", isOn: $viewModel.palmRejectionEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .gPrimary))
                                .labelsHidden()
                                .scaleEffect(0.8)
                        }
                        .accessibilityLabel("Palm rejection")
                        .accessibilityHint(viewModel.palmRejectionEnabled ? "On. Double tap to allow finger drawing" : "Off. Double tap to enable palm rejection")

                        HStack {
                            Text("Shape Snap")
                                .font(.gFootnote)
                                .foregroundColor(.gTextSecondary)
                            Spacer()
                            Toggle("Shape Snapping", isOn: $viewModel.isShapeSnappingEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .gPrimary))
                                .labelsHidden()
                                .scaleEffect(0.8)
                        }
                        .accessibilityLabel("Shape snapping")
                        .accessibilityHint(viewModel.isShapeSnappingEnabled ? "On. Double tap to disable" : "Off. Double tap to enable shape snapping")
                    }
                }
            }
        }
        .padding(GSpacing.md)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Divider().opacity(0.15)
                
                HStack(spacing: 0) {
                    Button { viewModel.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.gIconMedium)
                            .foregroundColor(!viewModel.canUndo ? Color.gTextTertiary : Color.gTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!viewModel.canUndo)
                    .accessibilityLabel("Undo")
                    .keyboardShortcut("z", modifiers: .command)

                    Divider()
                        .frame(width: 0.5, height: 24)
                        .background(Color.gBorder.opacity(0.3))

                    Button { viewModel.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.gIconMedium)
                            .foregroundColor(!viewModel.canRedo ? Color.gTextTertiary : Color.gTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!viewModel.canRedo)
                    .accessibilityLabel("Redo")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                .padding(.vertical, 4)
                .background(Color.gSurface.opacity(0.96))
            }
        }
    }

    // MARK: - Color Grid

    var colorGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 22), spacing: GRadius.xs)]
        let isCustomColorSelected = !Color.strokePresets.contains(where: { colorMatches(viewModel.strokeColor, $0) })
        
        return LazyVGrid(columns: cols, alignment: .leading, spacing: GRadius.xs) {
            ForEach(Color.strokePresets, id: \.hashValue) { color in
                ColorSwatch(
                    color: color,
                    isSelected: colorMatches(viewModel.strokeColor, color)
                ) {
                    viewModel.strokeColor = color
                }
            }

            // Custom color via system ColorPicker disguised as a rainbow swatch
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 22, height: 22)
                
                if isCustomColorSelected {
                    Circle()
                        .stroke(Color.gPrimary, lineWidth: 2.5)
                        .frame(width: 26, height: 26) // 2pt gap (22 + 2*2)
                }
                
                ColorPicker("", selection: $viewModel.strokeColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 22, height: 22)
                    .opacity(0.01) // completely transparent but still tappable
            }
        }
    }

    // MARK: - Stroke Width

    var strokeWidthSelector: some View {
        VStack(spacing: GSpacing.xs) {
            HStack(spacing: GRadius.xs) {
                ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { w in
                    strokeWidthButton(width: w)
                }
            }

            // Fine-tune slider
            Slider(value: $viewModel.strokeWidth, in: 0.5...20)
                .tint(.gPrimary)
                .frame(height: 20)
        }
    }

    private func strokeWidthButton(width w: CGFloat) -> some View {
        let isSelected = viewModel.strokeWidth == w
        return Button {
            viewModel.strokeWidth = w
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .fill(isSelected ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                    .frame(width: 34, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.xs)
                            .stroke(isSelected ? Color.gPrimary : .clear, lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: w + 1, height: w + 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(Int(w)) point width")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Pen Style

    var penStyleSelector: some View {
        VStack(spacing: GSpacing.xs) {
            let styles: [(PKInkingTool.InkType, String, String)] = [
                (.pen, "Ball Pen", "pencil.tip"),
                (.fountainPen, "Fountain", "paintbrush.pointed"),
                (.monoline, "Monoline", "minus")
            ]
            
            ForEach(styles, id: \.0) { style in
                Button {
                    viewModel.penStyle = style.0
                } label: {
                    HStack {
                        Image(systemName: style.2)
                            .frame(width: 24)
                        Text(style.1)
                            .font(.gFootnote)
                        Spacer()
                        if viewModel.penStyle == style.0 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(viewModel.penStyle == style.0 ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                    .cornerRadius(GRadius.sm)
                    .foregroundColor(viewModel.penStyle == style.0 ? .gPrimary : .gTextSecondary)
                }
            }
        }
    }

    // MARK: - Eraser Type

    var eraserTypeSelector: some View {
        VStack(spacing: GSpacing.xs) {
            let styles: [(PKEraserTool.EraserType, String, String)] = [
                (.bitmap, "Standard", "eraser"),
                (.vector, "Stroke", "scissors")
            ]
            
            ForEach(styles, id: \.0) { style in
                Button {
                    viewModel.eraserType = style.0
                } label: {
                    HStack {
                        Image(systemName: style.2)
                            .frame(width: 24)
                        Text(style.1)
                            .font(.gFootnote)
                        Spacer()
                        if viewModel.eraserType == style.0 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(viewModel.eraserType == style.0 ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                    .cornerRadius(GRadius.sm)
                    .foregroundColor(viewModel.eraserType == style.0 ? .gPrimary : .gTextSecondary)
                }
            }
        }
    }

    // MARK: - Lasso Actions

    var blockActions: some View {
        HStack(spacing: GSpacing.sm) {
            Button(action: { /* Copy logic */ }) {
                Image(systemName: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.gElevated)
                    .cornerRadius(8)
            }
            Button(action: { /* Paste logic */ }) {
                Image(systemName: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.gElevated)
                    .cornerRadius(8)
            }
            Button(action: { /* Delete logic */ }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.gElevated)
                    .cornerRadius(8)
            }
        }
        .foregroundColor(.gTextPrimary)
    }

    var lassoActions: some View {
        VStack(spacing: GSpacing.xs) {
            Button(action: { viewModel.performLassoAction(NSSelectorFromString("selectAll:")) }) {
                Text("Select All")
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(.gPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.sm)
                            .stroke(Color.gPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            let actions: [(String, String, () -> Void, Bool)] = [
                ("Cut", "scissors", { viewModel.performLassoAction(#selector(UIResponder.cut(_:))) }, false),
                ("Copy", "doc.on.doc", { viewModel.performLassoAction(#selector(UIResponder.copy(_:))) }, false),
                ("Paste", "doc.on.clipboard", { viewModel.performLassoAction(#selector(UIResponder.paste(_:))) }, true),
                ("Duplicate", "plus.square.on.square", { viewModel.performLassoAction(NSSelectorFromString("duplicate:")) }, false),
                ("Delete", "trash", { viewModel.performLassoAction(#selector(UIResponder.delete(_:))) }, false)
            ]
            
            // 3x2 Grid for Lasso Actions
            VStack(spacing: 6) {
                // Top row (3 items)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        lassoActionButton(action: actions[i])
                    }
                }
                
                // Bottom row (2 items)
                HStack(spacing: 6) {
                    ForEach(3..<5, id: \.self) { i in
                        lassoActionButton(action: actions[i])
                    }
                    // Empty spacer slot to keep the 3-column width alignment
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                Text("Make a selection with the lasso tool before using these actions")
                    .font(.custom("PlusJakartaSans-Regular", size: 13))
                    .italic()
            }
            .foregroundColor(.gTextTertiary)
            .padding(.top, 4)
                
            if !viewModel.selectedElementIds.isEmpty || !viewModel.selectedStrokeIndices.isEmpty {
                Divider()

                Text("RESIZE SELECTION")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                    .padding(.top, 8)

                // Slider drives pendingResizeScale — separate from the on-canvas drag handle
                HStack {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Slider(
                        value: $viewModel.pendingResizeScale,
                        in: 0.25...3.0,
                        step: 0.05
                    )
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }

                Text("\(Int(viewModel.pendingResizeScale * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Apply commits pendingResizeScale
                Button {
                    viewModel.applySelectionResize(scale: viewModel.pendingResizeScale)
                } label: {
                    Text("Apply Resize")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func lassoActionButton(action: (String, String, () -> Void, Bool)) -> some View {
        Button(action: action.2) {
            VStack(spacing: 4) {
                Image(systemName: action.1)
                    .font(.system(size: 20))
                Text(action.0)
                    .font(.system(size: 11))
                    .foregroundColor(.gTextSecondary)
            }
            .foregroundColor(action.0 == "Delete" ? .red : .gTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.gElevated)
            .cornerRadius(GRadius.sm)
        }
        .buttonStyle(.plain)
        // Disable paste if no content (simulated check here, update with actual logic)
        .disabled(action.3 && !UIPasteboard.general.hasStrings && !UIPasteboard.general.hasImages)
        .opacity((action.3 && !UIPasteboard.general.hasStrings && !UIPasteboard.general.hasImages) ? 0.35 : 1.0)
    }

    // MARK: - Opacity Slider

    var opacitySlider: some View {
        VStack(spacing: GSpacing.xxs) {
            HStack {
                Text("\(Int(viewModel.strokeOpacity * 100))%")
                    .font(.gMonoCaption)
                    .foregroundColor(.gTextSecondary)
                Spacer()
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.clear, viewModel.strokeColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)

                Slider(value: $viewModel.strokeOpacity, in: 0.05...1.0)
                    .tint(.clear)
            }
        }
    }

    // MARK: - Helper

    private func colorMatches(_ a: Color, _ b: Color) -> Bool {
        a.hexString == b.hexString
    }
}

// MARK: - Sub-Components

struct PropertySection<Content: View>: View {
    let title: String
    var showCloseButton: Bool = false
    var onClose: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.xs) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 11))
                    .foregroundColor(.gTextTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                if showCloseButton {
                    Spacer()
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gTextSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.gElevated))
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Close properties panel")
                    .accessibilityHint("Double tap to hide properties")
                }
            }
            .padding(.top, GSpacing.md)
            .padding(.bottom, 4)
            
            content()
        }
    }
}

struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                let isDark = color.hexString == "#000001" || color == .black
                
                if isDark {
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.gBorderStrong, lineWidth: 0.5)
                        )
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 22, height: 22)
                }

                if isSelected {
                    Circle()
                        .stroke(Color.gPrimary, lineWidth: 2.5)
                        .frame(width: 26, height: 26) // 22 width + 2pt padding on each side
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(color.description) color\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
    }
}
