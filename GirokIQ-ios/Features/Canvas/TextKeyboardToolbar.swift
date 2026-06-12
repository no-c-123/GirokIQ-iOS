import SwiftUI

struct TextKeyboardToolbar: View {
    @ObservedObject var viewModel: CanvasViewModel

    @State private var showColorPicker = false
    @State private var showFontPicker = false
    @State private var showMoreOptions = false

    var body: some View {
        HStack(spacing: 16) {
            // Color Dot
            Button {
                showColorPicker.toggle()
            } label: {
                Circle()
                    .fill(Color(hex: selectedTextElement?.style?.textColor ?? "#000000"))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.gBorder, lineWidth: 1))
            }
            .popover(isPresented: $showColorPicker, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                textColorGrid
                    .padding()
                    .frame(width: 250)
                    .presentationCompactAdaptation(.popover)
            }

            Divider().frame(height: 20)

            // B I U S toggles
            HStack(spacing: 8) {
                let isBold = selectedTextElement?.style?.isBold ?? false
                let isItalic = selectedTextElement?.style?.isItalic ?? false
                let isUnderline = selectedTextElement?.style?.isUnderline ?? false
                let isStrikethrough = selectedTextElement?.style?.isStrikethrough ?? false

                styleToggle(icon: "bold", isActive: isBold) {
                    applyTextStyle { $0.isBold = !isBold }
                }
                styleToggle(icon: "italic", isActive: isItalic) {
                    applyTextStyle { $0.isItalic = !isItalic }
                }
                styleToggle(icon: "underline", isActive: isUnderline) {
                    applyTextStyle { $0.isUnderline = !isUnderline }
                }
                styleToggle(icon: "strikethrough", isActive: isStrikethrough) {
                    applyTextStyle { $0.isStrikethrough = !isStrikethrough }
                }
            }

            Divider().frame(height: 20)

            // Font Pill
            Button {
                showFontPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(fontDisplayName(for: selectedTextElement?.style?.fontName))
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gElevated)
                .cornerRadius(16)
            }
            .popover(isPresented: $showFontPicker, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                fontSelector
                    .padding()
                    .frame(width: 220)
                    .presentationCompactAdaptation(.popover)
            }

            Divider().frame(height: 20)

            // Size Stepper
            HStack(spacing: 0) {
                Button {
                    let current = selectedTextElement?.style?.fontSize ?? 16
                    applyTextStyle { $0.fontSize = max(8, current - 1) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                        .background(Color.gElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8).path(in: CGRect(x: 0, y: 0, width: 32, height: 32)))
                }

                Text("\(Int(selectedTextElement?.style?.fontSize ?? 16))")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 36)
                    .multilineTextAlignment(.center)

                Button {
                    let current = selectedTextElement?.style?.fontSize ?? 16
                    applyTextStyle { $0.fontSize = min(144, current + 1) }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                        .background(Color.gElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8).path(in: CGRect(x: 0, y: 0, width: 32, height: 32)))
                }
            }

            Spacer()

            // More Button
            Button {
                showMoreOptions.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
            }
            .popover(isPresented: $showMoreOptions, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                moreOptionsPanel
                    .padding()
                    .frame(width: 250)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.gSurface.opacity(0.96))
        .background(.ultraThinMaterial)
        .overlay(Rectangle().stroke(Color.gBorder.opacity(0.5), lineWidth: 0.5), alignment: .top)
        .foregroundColor(.gTextPrimary)
    }

    private func styleToggle(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? .gPrimary : .gTextPrimary)
                .frame(width: 32, height: 32)
                .background(isActive ? Color.gPrimaryMuted : Color.clear)
                .cornerRadius(6)
        }
    }

    private func fontDisplayName(for fontName: String?) -> String {
        switch fontName {
        case "InstrumentSerif-Regular": return "Serif"
        case "PlusJakartaSans-Regular": return "Jakarta"
        case "Georgia": return "Georgia"
        case "Courier New": return "Courier"
        default: return "System"
        }
    }

    // MARK: - Panels

    var textColorGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 28), spacing: 12)]
        let currentHex = selectedTextElement?.style?.textColor ?? "#000000"
        let currentColor = Color(hex: currentHex)
        let isCustom = !Color.strokePresets.contains(where: { $0.hexString == currentColor.hexString })

        return VStack(alignment: .leading, spacing: 12) {
            Text("Text Color").font(.caption).foregroundColor(.gTextSecondary)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
                ForEach(Color.strokePresets, id: \.hashValue) { color in
                    ColorSwatch(
                        color: color,
                        isSelected: color.hexString == currentColor.hexString
                    ) {
                        applyTextStyle { $0.textColor = color.hexString }
                    }
                }
                ZStack {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        ))
                        .frame(width: 22, height: 22)
                    if isCustom {
                        Circle().stroke(Color.gPrimary, lineWidth: 2.5).frame(width: 26, height: 26)
                    }
                    ColorPicker("", selection: Binding(
                        get: { currentColor },
                        set: { newColor in applyTextStyle { $0.textColor = newColor.hexString } }
                    ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 22, height: 22)
                        .opacity(0.01)
                }
            }
        }
    }

    var fontSelector: some View {
        let fonts: [(String?, String)] = [
            (nil,                        "System"),
            ("InstrumentSerif-Regular",  "Serif"),
            ("PlusJakartaSans-Regular",  "Jakarta"),
            ("Georgia",                  "Georgia"),
            ("Courier New",              "Courier"),
        ]
        let currentFont = selectedTextElement?.style?.fontName

        return VStack(alignment: .leading, spacing: 12) {
            Text("Font Family").font(.caption).foregroundColor(.gTextSecondary)
            VStack(spacing: 4) {
                ForEach(fonts, id: \.0.debugDescription) { (name, label) in
                    Button {
                        applyTextStyle { $0.fontName = name }
                        showFontPicker = false
                    } label: {
                        HStack {
                            Text(label)
                                .font(name != nil ? .custom(name!, size: 16) : .system(size: 16))
                                .foregroundColor(currentFont == name ? .gPrimary : .gTextPrimary)
                            Spacer()
                            if currentFont == name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.gPrimary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(currentFont == name ? Color.gPrimaryMuted : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var moreOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Alignment
            VStack(alignment: .leading, spacing: 8) {
                Text("Alignment").font(.caption).foregroundColor(.gTextSecondary)
                let currentAlign = selectedTextElement?.style?.textAlignment ?? "left"
                let options: [(String, String)] = [
                    ("left",   "text.alignleft"),
                    ("center", "text.aligncenter"),
                    ("right",  "text.alignright"),
                    ("justified", "text.justify")
                ]
                HStack(spacing: 8) {
                    ForEach(options, id: \.0) { (value, icon) in
                        Button {
                            applyTextStyle { $0.textAlignment = value }
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(currentAlign == value ? .gPrimary : .gTextPrimary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(currentAlign == value ? Color.gPrimaryMuted : Color.gElevated)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Line Spacing
            VStack(alignment: .leading, spacing: 8) {
                Text("Line Spacing").font(.caption).foregroundColor(.gTextSecondary)
                let spacing = selectedTextElement?.style?.lineSpacing ?? 0
                HStack {
                    Text("\(String(format: "%.1f", spacing))pt")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gTextSecondary)
                        .frame(width: 45, alignment: .leading)
                    Slider(value: Binding(
                        get: { spacing },
                        set: { newVal in applyTextStyle { $0.lineSpacing = newVal } }
                    ), in: 0...20, step: 0.5)
                        .tint(.gPrimary)
                }
            }
        }
    }

    // MARK: - Text Style Helpers

    private var selectedTextElement: CanvasElement? {
        guard viewModel.selectedTool == .text,
              let id = viewModel.selectedElementIds.first,
              let el = viewModel.currentPage.elements.first(where: { $0.id == id }),
              el.type == "text" else { return nil }
        return el
    }

    private func applyTextStyle(_ mutation: (inout ElementStyle) -> Void) {
        guard let id = viewModel.selectedElementIds.first,
              let idx = viewModel.currentPage.elements.firstIndex(where: { $0.id == id }) else { return }
        var element = viewModel.currentPage.elements[idx]
        var style = element.style ?? ElementStyle()
        mutation(&style)
        element.style = style
        element.updatedAt = Date()
        viewModel.updateElement(element)
    }
}
