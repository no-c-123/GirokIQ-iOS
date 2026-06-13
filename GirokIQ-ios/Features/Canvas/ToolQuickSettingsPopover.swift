import SwiftUI
import PencilKit
import Photos

/// Compact tool settings shown from the left tool rail.
/// Text formatting is intentionally excluded (handled by `TextToolKeyboardBar`).
struct ToolQuickSettingsPopover: View {
    let tool: DrawingTool
    @ObservedObject var viewModel: CanvasViewModel

    @State private var pickedColor: Color = .white
    @State private var showColorPickerPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            Text(tool.label)
                .font(.gCaption.weight(.semibold))
                .foregroundColor(.gTextSecondary)
                .textCase(.uppercase)
                .tracking(0.4)

            content
        }
        .padding(GSpacing.md)
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .pen, .pencil, .marker:
            VStack(alignment: .leading, spacing: GSpacing.sm) {
                colorRow

                VStack(alignment: .leading, spacing: 6) {
                    label("Width")
                    widthPresetRow
                    Slider(value: $viewModel.strokeWidth, in: 0.5...20)
                        .tint(.gPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("Opacity")
                    Slider(value: $viewModel.strokeOpacity, in: 0.1...1.0)
                        .tint(.gPrimary)
                }

                if tool == .pen {
                    VStack(alignment: .leading, spacing: 6) {
                        label("Style")
                        HStack(spacing: 6) {
                            penStyleButton(.pen, label: "Pen")
                            penStyleButton(.fountainPen, label: "Fountain")
                            penStyleButton(.monoline, label: "Mono")
                        }
                    }
                }

                if tool != .marker {
                    Toggle("Palm Rejection", isOn: $viewModel.palmRejectionEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .gPrimary))
                    Toggle("Shape Snap", isOn: $viewModel.isShapeSnappingEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .gPrimary))
                }
            }

        case .eraser:
            VStack(alignment: .leading, spacing: GSpacing.sm) {
                label("Type")
                HStack(spacing: 8) {
                    eraserTypeButton(.bitmap, label: "Bitmap")
                    eraserTypeButton(.vector, label: "Vector")
                }
            }

        case .image:
            VStack(alignment: .leading, spacing: GSpacing.sm) {
                if viewModel.hasPhotoAccess {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: GSpacing.xs) {
                            ForEach(viewModel.recentPhotos.indices, id: \.self) { index in
                                let asset = viewModel.recentPhotos[index]
                                if let uiImage = viewModel.recentPhotoImages[asset] {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: GRadius.xs))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: GRadius.xs)
                                                .stroke(Color.gBorder, lineWidth: 0.5)
                                        )
                                        .onTapGesture {
                                            viewModel.insertImage(asset)
                                        }
                                }
                            }
                        }
                    }
                } else {
                    Button("Allow GirokIQ to access photos") {
                        viewModel.requestPhotoAccessAndFetch()
                    }
                    .font(.gCaption.weight(.medium))
                    .foregroundColor(.gPrimary)
                    .padding(.horizontal, GSpacing.sm)
                    .padding(.vertical, GSpacing.xxs)
                    .background(Color.gPrimaryMuted)
                    .clipShape(Capsule())
                }
            }

        default:
            Text("No quick settings for this tool.")
                .font(.gCaption2)
                .foregroundColor(.gTextTertiary)
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                label("Color")
                Spacer()
                Button {
                    viewModel.removeSelectedCustomColorFromColorTools()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.canDeleteSelectedCustomColor(for: tool) ? .gTextTertiary : .gTextTertiary.opacity(0.35))
                        .padding(6)
                        .background(Color.gElevated.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canDeleteSelectedCustomColor(for: tool))

                Button {
                    showColorPickerPopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.gTextSecondary)
                        .padding(6)
                        .background(Color.gElevated.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showColorPickerPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add Color")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextSecondary)

                        ColorPicker("Color", selection: $pickedColor, supportsOpacity: false)
                            .tint(.gPrimary)

                        HStack {
                            Spacer()
                            Button("Cancel") {
                                showColorPickerPopover = false
                            }
                            .buttonStyle(.plain)

                            Button("Add") {
                                viewModel.addExtraColor(pickedColor, for: tool)
                                viewModel.strokeColor = pickedColor
                                showColorPickerPopover = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.gPrimary)
                        }
                    }
                    .padding(GSpacing.md)
                    .frame(width: 220)
                }
            }

            let preset = viewModel.presetColors(for: tool)
            let extras = viewModel.extraColors(for: tool)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(preset, id: \.hashValue) { color in
                    colorCircle(color)
                }
                ForEach(Array(extras.enumerated()), id: \.offset) { _, color in
                    colorCircle(color)
                }
            }
        }
    }

    private func colorCircle(_ color: Color) -> some View {
        Button {
            viewModel.strokeColor = color
        } label: {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().stroke(
                        colorsMatch(viewModel.strokeColor, color) ? Color.gPrimary : Color.clear,
                        lineWidth: 2
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var widthPresetRow: some View {
        let presets = viewModel.widthPresets(for: tool)
        return HStack(spacing: 8) {
            ForEach(Array(presets.enumerated()), id: \.offset) { idx, width in
                Button {
                    viewModel.strokeWidth = width
                } label: {
                    Text(formatPx(width))
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(widthMatches(width, viewModel.strokeWidth) ? .white : .gTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(widthMatches(width, viewModel.strokeWidth) ? Color.gPrimary : Color.gElevated.opacity(0.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !presets.contains(where: { widthMatches($0, viewModel.strokeWidth) }) {
                        Button("Set preset") {
                            viewModel.setWidthPreset(for: tool, index: idx, to: viewModel.strokeWidth)
                        }
                    }
                }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.gCaption2.weight(.medium))
            .foregroundColor(.gTextTertiary)
    }

    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        a.hexString.uppercased() == b.hexString.uppercased()
    }

    private func widthMatches(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < 0.01
    }

    private func formatPx(_ width: CGFloat) -> String {
        String(format: "%.1f px", Double(width))
    }

    private func penStyleButton(_ style: PKInkingTool.InkType, label: String) -> some View {
        Button {
            viewModel.penStyle = style
        } label: {
            Text(label)
                .font(.gCaption)
                .foregroundColor(viewModel.penStyle == style ? .white : .gTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(viewModel.penStyle == style ? Color.gPrimary : Color.gElevated.opacity(0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func eraserTypeButton(_ type: PKEraserTool.EraserType, label: String) -> some View {
        Button {
            viewModel.eraserType = type
        } label: {
            Text(label)
                .font(.gCaption)
                .foregroundColor(viewModel.eraserType == type ? .white : .gTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(viewModel.eraserType == type ? Color.gPrimary : Color.gElevated.opacity(0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
