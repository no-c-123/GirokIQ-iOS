import SwiftUI
import PencilKit
import Photos
internal import UniformTypeIdentifiers

/// Compact tool settings shown from the left tool rail.
/// Text formatting is intentionally excluded (handled by `TextToolKeyboardBar`).
struct ToolQuickSettingsPopover: View {
    let tool: DrawingTool
    @ObservedObject var viewModel: CanvasViewModel

    @State private var pickedColor: Color = .white
    @State private var showColorPickerPopover = false
    @State private var draggedColorHex: String?
    @State private var isSeedingPickedColor = true

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
                    HStack {
                        label("Width")
                        Spacer()
                        // Live width readout so the current stroke size is visible
                        // while dragging, independent of the presets.
                        Text(formatPx(viewModel.strokeWidth))
                            .font(.gMonoCaption)
                            .monospacedDigit()
                            .foregroundColor(.gTextSecondary)
                    }
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
                label("Mode")
                HStack(spacing: 8) {
                    eraserTypeButton(.fixedWidthBitmap, label: "Precise")
                    eraserTypeButton(.vector, label: "Object")
                }

                if viewModel.eraserType != .vector {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            label("Width")
                            Spacer()
                            Text(formatPx(viewModel.eraserWidth))
                                .font(.gMonoCaption)
                                .monospacedDigit()
                                .foregroundColor(.gTextSecondary)
                        }
                        eraserWidthPresetRow
                        Slider(
                            value: $viewModel.eraserWidth,
                            in: PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange.lowerBound...PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange.upperBound
                        )
                        .tint(.gPrimary)
                    }
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
                    VStack(alignment: .leading, spacing: GSpacing.xs) {
                        Button("Allow GirokIQ to access photos") {
                            viewModel.requestPhotoAccessAndFetch()
                        }
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(.gPrimary)
                        .padding(.horizontal, GSpacing.sm)
                        .padding(.vertical, GSpacing.xxs)
                        .background(Color.gPrimaryMuted)
                        .clipShape(Capsule())

                        if viewModel.shouldShowPhotoSettingsPrompt {
                            Button("Open Settings") {
                                viewModel.openPhotoSettings()
                            }
                            .font(.gCaption.weight(.medium))
                            .foregroundColor(.gTextSecondary)
                            .padding(.horizontal, GSpacing.sm)
                            .padding(.vertical, GSpacing.xxs)
                            .background(Color.gElevated.opacity(0.7))
                            .clipShape(Capsule())
                        }
                    }
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
                    viewModel.removeSelectedCustomColor(for: tool)
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
                    // Treat this as a seed value, not as a new user-picked color.
                    isSeedingPickedColor = true
                    pickedColor = viewModel.strokeColor
                    DispatchQueue.main.async { isSeedingPickedColor = false }
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
                .popover(
                    isPresented: $showColorPickerPopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .leading
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextSecondary)

                        ColorPicker("Color", selection: $pickedColor, supportsOpacity: false)
                            .tint(.gPrimary)

                        Divider().opacity(0.2)

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
                    .frame(width: 260)
                    .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel("Add color")
            }

            let paletteHexes = viewModel.paletteColorHexes(for: tool)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(paletteHexes, id: \.self) { hex in
                    colorCircle(hex: hex, color: Color(hex: hex))
                }
            }
            .onDrop(of: [UTType.text], delegate: PaletteGridDropDelegate(activeHex: $draggedColorHex))
        }
        .onAppear {
            // Seed the picker with the current stroke color without treating it as a "new" user pick.
            pickedColor = viewModel.strokeColor
            DispatchQueue.main.async {
                isSeedingPickedColor = false
            }
        }
    }

    private func colorCircle(hex: String, color: Color) -> some View {
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
        .onDrag {
            draggedColorHex = hex
            return NSItemProvider(object: hex as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: PaletteColorDropDelegate(
                targetHex: hex,
                tool: tool,
                viewModel: viewModel,
                activeHex: $draggedColorHex
            )
        )
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

    private var eraserWidthPresetRow: some View {
        let presets = viewModel.widthPresets(for: .eraser)
        return HStack(spacing: 8) {
            ForEach(Array(presets.enumerated()), id: \.offset) { idx, width in
                Button {
                    viewModel.eraserWidth = width
                } label: {
                    Text(formatPx(width))
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(widthMatches(width, viewModel.eraserWidth) ? .white : .gTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(widthMatches(width, viewModel.eraserWidth) ? Color.gPrimary : Color.gElevated.opacity(0.5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !presets.contains(where: { widthMatches($0, viewModel.eraserWidth) }) {
                        Button("Set preset") {
                            viewModel.setWidthPreset(for: .eraser, index: idx, to: viewModel.eraserWidth)
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

private struct PaletteColorDropDelegate: DropDelegate {
    let targetHex: String
    let tool: DrawingTool
    let viewModel: CanvasViewModel
    @Binding var activeHex: String?

    func dropEntered(info: DropInfo) {
        guard let activeHex, activeHex != targetHex else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.movePaletteColor(for: tool, from: activeHex, to: targetHex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        activeHex = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct PaletteGridDropDelegate: DropDelegate {
    @Binding var activeHex: String?

    func performDrop(info: DropInfo) -> Bool {
        activeHex = nil
        return true
    }
}
