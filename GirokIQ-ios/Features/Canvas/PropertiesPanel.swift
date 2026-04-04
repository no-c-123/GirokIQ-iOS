import SwiftUI
import PencilKit

// MARK: - Properties Panel

struct PropertiesPanel: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider().opacity(0.15)
            scrollContent
        }
        .frame(width: 180)
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
        HStack {
            Text("Properties")
                .font(.gCaption.weight(.semibold))
                .foregroundColor(.gTextSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Button {
                animateMotionSafe(GAnimation.springFast) {
                    viewModel.showProperties = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.gCaption2.weight(.bold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.gBorder))
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close properties panel")
            .accessibilityHint("Double tap to hide properties")
        }
        .padding(.leading, GSpacing.md)
        .padding(.trailing, GSpacing.xs)
        .padding(.vertical, GSpacing.xxs)
    }

    var scrollContent: some View {
        VStack(alignment: .leading, spacing: GSpacing.md) {
            
            if viewModel.selectedTool == .eraser {
                // ERASER PROPERTIES
                PropertySection(title: "Eraser Type") {
                    eraserTypeSelector
                }
            } else if viewModel.selectedTool == .lasso || viewModel.selectedTool == .selection {
                // LASSO PROPERTIES
                PropertySection(title: "Lasso Actions") {
                    lassoActions
                }
            } else {
                // INKING TOOLS PROPERTIES
                if viewModel.selectedTool == .pen {
                    PropertySection(title: "Pen Style") {
                        penStyleSelector
                    }
                    Divider().opacity(0.1)
                }
                
                PropertySection(title: "Stroke Color") {
                    colorGrid
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

            Divider().opacity(0.1)

            // Drawing Assistants
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
        .padding(GSpacing.md)
    }

    // MARK: - Color Grid

    var colorGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 22), spacing: GRadius.xs)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: GRadius.xs) {
            ForEach(Color.strokePresets, id: \.hashValue) { color in
                ColorSwatch(
                    color: color,
                    isSelected: colorMatches(viewModel.strokeColor, color)
                ) {
                    viewModel.strokeColor = color
                }
            }

            // Custom color via system ColorPicker
            ColorPicker("", selection: $viewModel.strokeColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 22, height: 22)
                .scaleEffect(1.2)
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

    var lassoActions: some View {
        VStack(spacing: GSpacing.xs) {
            let actions: [(String, String, () -> Void)] = [
                ("Copy", "doc.on.doc", { viewModel.performLassoAction(#selector(UIResponder.copy(_:))) }),
                ("Paste", "doc.on.clipboard", { viewModel.performLassoAction(#selector(UIResponder.paste(_:))) }),
                ("Duplicate", "plus.square.on.square", { viewModel.performLassoAction(#selector(UIResponder.duplicate(_:))) }),
                ("Delete", "trash", { viewModel.performLassoAction(#selector(UIResponder.delete(_:))) })
            ]
            
            ForEach(actions, id: \.0) { action in
                Button(action: action.2) {
                    HStack {
                        Image(systemName: action.1)
                            .frame(width: 24)
                        Text(action.0)
                            .font(.gFootnote)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gElevated.opacity(0.5))
                    .cornerRadius(GRadius.sm)
                    .foregroundColor(.gTextPrimary)
                }
            }
            Text("Tip: Make a selection with the lasso tool before using these actions.")
                .font(.gMonoCaption)
                .foregroundColor(.gTextSecondary)
                .padding(.top, 4)
        }
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.xs) {
            Text(title)
                .font(.gCaption2.weight(.semibold))
                .foregroundColor(.gTextSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
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
                let isLight = color.hexString == "#FFFFFE" || color == .white
                
                if isDark {
                    RoundedRectangle(cornerRadius: GRadius.xs - 1, style: .continuous)
                        .fill(color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: GRadius.xs - 1)
                                .stroke(Color.gBorderStrong, lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: GRadius.xs - 1, style: .continuous)
                        .fill(color)
                        .frame(width: 22, height: 22)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: GRadius.xs - 1, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(isLight || color == .yellow ? .black : .white)
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
