import SwiftUI

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
            }
            .minTapTarget()
            .accessibilityLabel("Close properties panel")
            .accessibilityHint("Double tap to hide properties")
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, GSpacing.sm)
    }

    var scrollContent: some View {
        VStack(alignment: .leading, spacing: GSpacing.md) {
            // Stroke Color
            PropertySection(title: "Stroke Color") {
                colorGrid
            }

            Divider().opacity(0.1)

            // Stroke Width
            PropertySection(title: "Stroke Width") {
                strokeWidthSelector
            }

            Divider().opacity(0.1)

            // Stroke Style
            PropertySection(title: "Stroke Style") {
                strokeStyleSelector
            }

            Divider().opacity(0.1)

            // Opacity
            PropertySection(title: "Opacity") {
                opacitySlider
            }

            Divider().opacity(0.1)

            // Palm Rejection
            PropertySection(title: "Palm Rejection") {
                Toggle("Palm Rejection", isOn: $viewModel.palmRejectionEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .gPrimary))
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Palm rejection")
                    .accessibilityHint(viewModel.palmRejectionEnabled ? "On. Double tap to allow finger drawing" : "Off. Double tap to enable palm rejection")
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
        .minTapTarget()
        .accessibilityLabel("\(Int(w)) point width")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Stroke Style

    var strokeStyleSelector: some View {
        HStack(spacing: GRadius.xs) {
            ForEach(StrokeStyle.allCases, id: \.self) { style in
                strokeStyleButton(style: style)
            }
        }
    }

    private func strokeStyleButton(style: StrokeStyle) -> some View {
        let isSelected = viewModel.strokeStyle == style
        return Button {
            viewModel.strokeStyle = style
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .fill(isSelected ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: GRadius.xs)
                            .stroke(isSelected ? Color.gPrimary : .clear, lineWidth: 1)
                    )

                Image(systemName: style.icon)
                    .font(.gFootnote)
                    .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .minTapTarget()
        .accessibilityLabel("\(style.rawValue) stroke style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                if color == .black {
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
                        .foregroundColor(color == .white || color == .yellow ? .black : .white)
                }
            }
        }
        .minTapTarget()
        .accessibilityLabel("\(color.description) color\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
    }
}
