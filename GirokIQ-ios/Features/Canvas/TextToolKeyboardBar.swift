import SwiftUI

/// Horizontal 46pt toolbar that replaces the vertical PropertiesPanel when
/// the text tool is active and the keyboard is visible. Sits between the
/// canvas and the system keyboard.
struct TextToolKeyboardBar: View {
    @ObservedObject var viewModel: CanvasViewModel

    @State private var showColorPicker = false
    @State private var showFontPicker  = false
    @State private var showMore        = false

    // MARK: - Helpers

    private var selectedElement: CanvasElement? {
        guard let id = viewModel.selectedElementIds.first,
              let el = viewModel.currentPage.elements.first(where: { $0.id == id }),
              el.type == "text" else { return nil }
        return el
    }

    private func applyStyle(_ mutation: (inout ElementStyle) -> Void) {
        guard let id = viewModel.selectedElementIds.first,
              let idx = viewModel.currentPage.elements.firstIndex(where: { $0.id == id }) else { return }
        var el = viewModel.currentPage.elements[idx]
        var style = el.style ?? ElementStyle()
        mutation(&style)
        el.style = style
        el.updatedAt = Date()
        viewModel.updateElement(el)
    }

    private var currentColor: Color {
        Color(hex: selectedElement?.style?.textColor ?? "#000000")
    }

    private var currentFontName: String {
        guard let name = selectedElement?.style?.fontName else { return "System" }
        let map: [String: String] = [
            "InstrumentSerif-Regular": "Serif",
            "PlusJakartaSans-Regular": "Jakarta",
            "Georgia": "Georgia",
            "Courier New": "Courier"
        ]
        return map[name] ?? "System"
    }

    private var currentSize: Int {
        Int(selectedElement?.style?.fontSize ?? 16)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The strip itself
            strip
                .zIndex(20)

            // Dropdowns — rendered below the strip
            if showColorPicker {
                colorDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
            if showFontPicker {
                fontDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
            if showMore {
                moreDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Strip

    var strip: some View {
        HStack(spacing: 2) {

            // Color dot
            Button {
                closeAll(except: "color")
                withAnimation(GAnimation.springFast) { showColorPicker.toggle() }
            } label: {
                Circle()
                    .fill(currentColor)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.gPrimary, lineWidth: showColorPicker ? 2 : 0).frame(width: 26, height: 26))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)

            separator

            // B I U S
            styleToggle("B", font: .system(size: 15, weight: .bold),
                        active: selectedElement?.style?.isBold ?? false) {
                applyStyle { $0.isBold = !($0.isBold ?? false) }
            }
            styleToggle("I", font: .system(size: 15).italic(),
                        active: selectedElement?.style?.isItalic ?? false) {
                applyStyle { $0.isItalic = !($0.isItalic ?? false) }
            }
            styleToggle("U", underline: true,
                        active: selectedElement?.style?.isUnderline ?? false) {
                applyStyle { $0.isUnderline = !($0.isUnderline ?? false) }
            }
            styleToggle("S", strikethrough: true,
                        active: selectedElement?.style?.isStrikethrough ?? false) {
                applyStyle { $0.isStrikethrough = !($0.isStrikethrough ?? false) }
            }

            separator

            // Font pill
            Button {
                closeAll(except: "font")
                withAnimation(GAnimation.springFast) { showFontPicker.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Text(currentFontName)
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(showFontPicker ? .gPrimary : .gTextSecondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(showFontPicker ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(showFontPicker ? Color.gPrimary : .clear, lineWidth: 0.5))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            separator

            // Size stepper
            HStack(spacing: 1) {
                Button { stepSize(by: -2) } label: {
                    Text("−")
                        .font(.system(size: 18))
                        .foregroundColor(.gTextTertiary)
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)

                Text("\(currentSize)")
                    .font(.system(size: 12))
                    .foregroundColor(.gTextSecondary)
                    .frame(minWidth: 30)
                    .frame(height: 28)
                    .background(Color.gElevated.opacity(0.5))
                    .cornerRadius(5)

                Button { stepSize(by: 2) } label: {
                    Text("+")
                        .font(.system(size: 18))
                        .foregroundColor(.gTextTertiary)
                        .frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // More button
            Button {
                closeAll(except: "more")
                withAnimation(GAnimation.springFast) { showMore.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(showMore ? .gPrimary : .gTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(showMore ? Color.gPrimaryMuted : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(showMore ? Color.gPrimary.opacity(0.4) : .clear, lineWidth: 0.5))
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.gSurface.opacity(0.98))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gBorderStrong), alignment: .bottom)
    }

    // MARK: - Dropdowns

    var colorDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TEXT COLOR")
                    .font(.custom("PlusJakartaSans-Medium", size: 10))
                    .foregroundColor(.gTextTertiary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.bottom, 10)

            let cols = [GridItem(.adaptive(minimum: 26), spacing: 8)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                ForEach(Color.strokePresets, id: \.hashValue) { color in
                    ColorSwatch(
                        color: color,
                        isSelected: currentColor.hexString == color.hexString
                    ) {
                        applyStyle { $0.textColor = color.hexString }
                        withAnimation(GAnimation.springFast) { showColorPicker = false }
                    }
                }
                // Custom color picker
                ZStack {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        ))
                        .frame(width: 26, height: 26)
                    ColorPicker("", selection: Binding(
                        get: { currentColor },
                        set: { newColor in
                            applyStyle { $0.textColor = newColor.hexString }
                        }
                    ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 26, height: 26)
                        .opacity(0.01)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.98))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous).stroke(Color.gBorderStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
        .padding(.horizontal, 12)
        .padding(.top, 4) // clears the strip
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var fontDropdown: some View {
        let fonts: [(String?, String)] = [
            (nil,                        "System"),
            ("InstrumentSerif-Regular",  "Serif"),
            ("PlusJakartaSans-Regular",  "Jakarta"),
            ("Georgia",                  "Georgia"),
            ("Courier New",              "Courier"),
        ]
        let currentFont = selectedElement?.style?.fontName

        return VStack(alignment: .leading, spacing: 0) {
            Text("FONT")
                .font(.custom("PlusJakartaSans-Medium", size: 10))
                .foregroundColor(.gTextTertiary)
                .tracking(0.5)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                ForEach(fonts, id: \.1) { (name, label) in
                    Button {
                        applyStyle { $0.fontName = name }
                        withAnimation(GAnimation.springFast) { showFontPicker = false }
                    } label: {
                        HStack {
                            Text(label)
                                .font(name != nil ? .custom(name!, size: 14) : .system(size: 14))
                                .foregroundColor(currentFont == name ? .gPrimary : .gTextSecondary)
                            Spacer()
                            if currentFont == name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gPrimary)
                            }
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(currentFont == name ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                        .cornerRadius(GRadius.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.98))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous).stroke(Color.gBorderStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
        .frame(maxWidth: 200)
        .padding(.leading, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var moreDropdown: some View {
        let currentAlignment = selectedElement?.style?.textAlignment ?? "left"
        let currentSpacing = selectedElement?.style?.lineSpacing ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            // Alignment
            Text("ALIGNMENT")
                .font(.custom("PlusJakartaSans-Medium", size: 10))
                .foregroundColor(.gTextTertiary)
                .tracking(0.5)
                .padding(.bottom, 8)

            HStack(spacing: 4) {
                let options = [
                    ("left", "text.alignleft"),
                    ("center", "text.aligncenter"),
                    ("right", "text.alignright"),
                    ("justified", "text.justify")
                ]
                ForEach(options, id: \.0) { val, icon in
                    let isSelected = currentAlignment == val
                    Button {
                        applyStyle { $0.textAlignment = val }
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 32)
                            .background(isSelected ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: GRadius.xs).stroke(isSelected ? Color.gPrimary : Color.clear, lineWidth: 0.5))
                            .cornerRadius(GRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)

            Divider().opacity(0.15).padding(.bottom, 12)

            // Line spacing
            Text("LINE SPACING")
                .font(.custom("PlusJakartaSans-Medium", size: 10))
                .foregroundColor(.gTextTertiary)
                .tracking(0.5)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Text("\(String(format: "%.1f", currentSpacing))pt")
                    .font(.gMonoCaption)
                    .foregroundColor(.gTextSecondary)
                    .frame(minWidth: 36)
                Slider(value: Binding(
                    get: { selectedElement?.style?.lineSpacing ?? 0 },
                    set: { newVal in applyStyle { $0.lineSpacing = newVal } }
                ), in: 0...20, step: 0.5)
                    .tint(.gPrimary)
            }
            .padding(.bottom, 12)

            Divider().opacity(0.15).padding(.bottom, 12)

            // Actions
            Text("ACTIONS")
                .font(.custom("PlusJakartaSans-Medium", size: 10))
                .foregroundColor(.gTextTertiary)
                .tracking(0.5)
                .padding(.bottom, 8)

            HStack(spacing: 6) {
                actionBtn(icon: "plus.square.on.square", label: "Duplicate") {
                    if let el = selectedElement {
                        let newId = UUID()
                        let copy = CanvasElement(
                            id: newId,
                            pageId: el.pageId,
                            userId: el.userId,
                            type: el.type,
                            content: el.content,
                            positionX: el.positionX + 20,
                            positionY: el.positionY + 20,
                            width: el.width,
                            height: el.height,
                            rotation: el.rotation,
                            zIndex: el.zIndex,
                            style: el.style,
                            userResized: el.userResized,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        viewModel.pages[viewModel.currentPageIndex].elements.append(copy)
                        viewModel.selectedElementIds = [newId]
                    }
                    withAnimation(GAnimation.springFast) { showMore = false }
                }
                actionBtn(icon: "trash", label: "Delete", tint: .red) {
                    if let id = viewModel.selectedElementIds.first {
                        viewModel.removeElement(id: id)
                    }
                    withAnimation(GAnimation.springFast) { showMore = false }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.98))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous).stroke(Color.gBorderStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
        .frame(maxWidth: 220)
        .padding(.leading, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sub-views

    private var separator: some View {
        Rectangle()
            .fill(Color.gBorderStrong.opacity(0.5))
            .frame(width: 0.5, height: 22)
            .padding(.horizontal, 3)
    }

    private func styleToggle(
        _ label: String,
        font: Font = .system(size: 14),
        underline: Bool = false,
        strikethrough: Bool = false,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .underline(underline)
                .strikethrough(strikethrough)
                .foregroundColor(active ? .gPrimary : .gTextSecondary)
                .frame(width: 34, height: 34)
                .background(active ? Color.gPrimaryMuted : .clear)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Color.gPrimary.opacity(0.4) : .clear, lineWidth: 0.5))
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    private func actionBtn(icon: String, label: String, tint: Color = .gTextSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.gFootnote)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 32)
            .background(Color.gElevated.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: GRadius.xs).stroke(tint == .red ? Color.red.opacity(0.3) : Color.gBorder.opacity(0.3), lineWidth: 0.5))
            .cornerRadius(GRadius.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func stepSize(by delta: Int) {
        let newSize = max(8, min(72, currentSize + delta))
        applyStyle { $0.fontSize = Double(newSize) }
    }

    private func closeAll(except: String) {
        if except != "color" { withAnimation(GAnimation.springFast) { showColorPicker = false } }
        if except != "font"  { withAnimation(GAnimation.springFast) { showFontPicker = false } }
        if except != "more"  { withAnimation(GAnimation.springFast) { showMore = false } }
    }
}
