import SwiftUI

/// Horizontal 46pt toolbar that replaces the vertical PropertiesPanel when
/// the text tool is active. Sits full-width just below the top canvas toolbar.
///
/// Each picker (color / font / more) opens a floating panel anchored directly
/// beneath its trigger button — clamped to stay on-screen — and overlays the
/// canvas instead of pushing it down.
struct TextToolKeyboardBar: View {
    @ObservedObject var viewModel: CanvasViewModel

    @State private var showColorPicker = false
    @State private var showFontPicker  = false
    @State private var showMore        = false

    /// Frames of the trigger buttons (and the strip itself, under "_bar"),
    /// measured in the `barSpace` coordinate space so panels can anchor to them.
    @State private var triggerFrames: [String: CGRect] = [:]

    private let barSpace = "textToolBar"
    private let stripHeight: CGFloat = 46

    // MARK: - Active panel

    private enum Panel: String { case color, font, more }

    private var activePanel: Panel? {
        if showColorPicker { return .color }
        if showFontPicker  { return .font }
        if showMore        { return .more }
        return nil
    }

    private var barWidth: CGFloat { triggerFrames["_bar"]?.width ?? 0 }

    private func panelWidth(_ p: Panel) -> CGFloat {
        switch p {
        case .color: return 248
        case .font:  return 200
        case .more:  return 248
        }
    }

    /// Horizontal offset that places a panel under its trigger, clamped to the bar.
    /// The "more" panel right-aligns to its trigger (it lives on the right edge);
    /// the others left-align.
    private func panelX(_ p: Panel) -> CGFloat {
        let w = panelWidth(p)
        let margin: CGFloat = 12
        guard let t = triggerFrames[p.rawValue], barWidth > 0 else { return margin }
        let desired = (p == .more) ? (t.maxX - w) : t.minX
        let upperBound = max(margin, barWidth - w - margin)
        return min(max(margin, desired), upperBound)
    }

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
            strip
                .zIndex(20)

            // Floating picker panel, anchored horizontally under its trigger.
            // Kept in normal flow (not an overflowing overlay) so every control
            // inside stays reliably hit-testable.
            if let panel = activePanel {
                panelContent(panel)
                    .frame(width: panelWidth(panel))
                    .fixedSize(horizontal: false, vertical: true)
                    .panelCardStyle()
                    .padding(.leading, panelX(panel))
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top)
                            .combined(with: .opacity)
                            .combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                    .zIndex(10)
            }
        }
        .coordinateSpace(name: barSpace)
        .onPreferenceChange(TextBarFrameKey.self) { triggerFrames = $0 }
    }

    // MARK: - Strip

    /// The toolbar adapts to available width. When the bar is wide enough (iPad,
    /// most landscape layouts) the alignment + line-spacing controls live directly
    /// in the bar. On narrow devices they collapse into the "•••" overflow panel.
    var strip: some View {
        ViewThatFits(in: .horizontal) {
            expandedRow
            compactRow
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: stripHeight)
        .background(Color.gSurface.opacity(0.98))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gBorderStrong), alignment: .bottom)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: TextBarFrameKey.self, value: ["_bar": g.frame(in: .named(barSpace))])
            }
        )
    }

    /// Wide layout: formatting + alignment + spacing all inline, left-packed.
    /// Duplicate/Delete stay reachable from the pill above the selected block.
    private var expandedRow: some View {
        HStack(spacing: 2) {
            colorButton
            separator
            styleToggles
            separator
            fontButton
            separator
            sizeStepper
            separator
            alignmentInline
            separator
            spacingInline
        }
    }

    /// Narrow layout: formatting inline, everything else behind "•••".
    private var compactRow: some View {
        HStack(spacing: 2) {
            colorButton
            separator
            styleToggles
            separator
            fontButton
            separator
            sizeStepper
            Spacer(minLength: 8)
            moreButton
        }
    }

    // MARK: - Strip controls

    private var colorButton: some View {
        Button {
            closeAll(except: "color")
            withAnimation(GAnimation.springFast) { showColorPicker.toggle() }
        } label: {
            Circle()
                .fill(currentColor)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.gBorderStrong.opacity(0.4), lineWidth: 0.5))
                .overlay(Circle().stroke(Color.gPrimary, lineWidth: showColorPicker ? 2 : 0).frame(width: 28, height: 28))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .textBarFrame("color", in: barSpace)
    }

    private var styleToggles: some View {
        HStack(spacing: 2) {
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
        }
    }

    private var fontButton: some View {
        Button {
            closeAll(except: "font")
            withAnimation(GAnimation.springFast) { showFontPicker.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(currentFontName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showFontPicker ? 180 : 0))
            }
            .foregroundColor(showFontPicker ? .gPrimary : .gTextSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(showFontPicker ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(showFontPicker ? Color.gPrimary : .clear, lineWidth: 1))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .textBarFrame("font", in: barSpace)
    }

    private var sizeStepper: some View {
        HStack(spacing: 0) {
            Button { stepSize(by: -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(currentSize)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.gTextPrimary)
                .frame(minWidth: 26)

            Button { stepSize(by: 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
        .background(Color.gElevated.opacity(0.5))
        .cornerRadius(7)
    }

    /// Inline alignment segmented control (wide layouts only).
    private var alignmentInline: some View {
        let current = selectedElement?.style?.textAlignment ?? "left"
        let options = [
            ("left", "text.alignleft"),
            ("center", "text.aligncenter"),
            ("right", "text.alignright"),
            ("justified", "text.justify")
        ]
        return HStack(spacing: 2) {
            ForEach(options, id: \.0) { val, icon in
                let isSelected = current == val
                Button {
                    applyStyle { $0.textAlignment = val }
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
                        .frame(width: 32, height: 30)
                        .background(isSelected ? Color.gPrimaryMuted : .clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Inline line-spacing stepper (wide layouts only).
    private var spacingInline: some View {
        let spacing = selectedElement?.style?.lineSpacing ?? 0
        return HStack(spacing: 0) {
            Button { stepSpacing(by: -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gTextTertiary)
                Text("\(String(format: "%.0f", spacing))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.gTextPrimary)
            }
            .frame(minWidth: 34)

            Button { stepSpacing(by: 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
        .background(Color.gElevated.opacity(0.5))
        .cornerRadius(7)
    }

    private var moreButton: some View {
        Button {
            closeAll(except: "more")
            withAnimation(GAnimation.springFast) { showMore.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(showMore ? .gPrimary : .gTextSecondary)
                .frame(width: 36, height: 36)
                .background(showMore ? Color.gPrimaryMuted : .clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(showMore ? Color.gPrimary.opacity(0.4) : .clear, lineWidth: 1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .textBarFrame("more", in: barSpace)
    }

    // MARK: - Panels (inner content only — positioning/card handled by body)

    @ViewBuilder
    private func panelContent(_ panel: Panel) -> some View {
        switch panel {
        case .color: colorPanel
        case .font:  fontPanel
        case .more:  morePanel
        }
    }

    var colorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader("TEXT COLOR")
                .padding(.bottom, 10)

            let cols = [GridItem(.adaptive(minimum: 28), spacing: 10)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
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
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    ColorPicker("", selection: Binding(
                        get: { currentColor },
                        set: { newColor in
                            applyStyle { $0.textColor = newColor.hexString }
                        }
                    ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 28, height: 28)
                        .opacity(0.02)
                }
            }
        }
        .padding(14)
    }

    var fontPanel: some View {
        let fonts: [(String?, String)] = [
            (nil,                        "System"),
            ("InstrumentSerif-Regular",  "Serif"),
            ("PlusJakartaSans-Regular",  "Jakarta"),
            ("Georgia",                  "Georgia"),
            ("Courier New",              "Courier"),
        ]
        let currentFont = selectedElement?.style?.fontName

        return VStack(alignment: .leading, spacing: 0) {
            panelHeader("FONT")
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(fonts, id: \.1) { (name, label) in
                    Button {
                        applyStyle { $0.fontName = name }
                        withAnimation(GAnimation.springFast) { showFontPicker = false }
                    } label: {
                        HStack {
                            Text(label)
                                .font(name != nil ? .custom(name!, size: 15) : .system(size: 15))
                                .foregroundColor(currentFont == name ? .gPrimary : .gTextPrimary)
                            Spacer()
                            if currentFont == name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gPrimary)
                            }
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(currentFont == name ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                        .cornerRadius(GRadius.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }

    var morePanel: some View {
        let currentAlignment = selectedElement?.style?.textAlignment ?? "left"
        let currentSpacing = selectedElement?.style?.lineSpacing ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            // Alignment
            panelHeader("ALIGNMENT")
                .padding(.bottom, 8)

            HStack(spacing: 6) {
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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(isSelected ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: GRadius.sm).stroke(isSelected ? Color.gPrimary : Color.clear, lineWidth: 1))
                            .cornerRadius(GRadius.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            // Line spacing
            HStack {
                panelHeader("LINE SPACING")
                Spacer()
                Text("\(String(format: "%.1f", currentSpacing))pt")
                    .font(.gMonoCaption)
                    .foregroundColor(.gTextSecondary)
            }
            .padding(.bottom, 4)

            Slider(value: Binding(
                get: { selectedElement?.style?.lineSpacing ?? 0 },
                set: { newVal in applyStyle { $0.lineSpacing = newVal } }
            ), in: 0...20, step: 0.5)
                .tint(.gPrimary)
                .padding(.bottom, 14)

            // Actions
            HStack(spacing: 8) {
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
    }

    // MARK: - Sub-views

    private func panelHeader(_ text: String) -> some View {
        Text(text)
            .font(.custom("PlusJakartaSans-Medium", size: 10))
            .foregroundColor(.gTextTertiary)
            .tracking(0.6)
    }

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
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Color.gPrimary.opacity(0.4) : .clear, lineWidth: 1))
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
                    .font(.gFootnote.weight(.medium))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(tint == .red ? Color.red.opacity(0.08) : Color.gElevated.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: GRadius.sm).stroke(tint == .red ? Color.red.opacity(0.3) : Color.gBorder.opacity(0.3), lineWidth: 0.5))
            .cornerRadius(GRadius.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func stepSize(by delta: Int) {
        let newSize = max(8, min(72, currentSize + delta))
        applyStyle { $0.fontSize = Double(newSize) }
    }

    private func stepSpacing(by delta: Double) {
        let current = selectedElement?.style?.lineSpacing ?? 0
        let newSpacing = max(0, min(20, current + delta))
        applyStyle { $0.lineSpacing = newSpacing }
    }

    private func closeAll(except: String) {
        if except != "color" { withAnimation(GAnimation.springFast) { showColorPicker = false } }
        if except != "font"  { withAnimation(GAnimation.springFast) { showFontPicker = false } }
        if except != "more"  { withAnimation(GAnimation.springFast) { showMore = false } }
    }
}

// MARK: - Panel anchoring support

/// Collects the frames of the toolbar's trigger buttons (and the strip itself)
/// so floating panels can be positioned directly beneath their trigger.
private struct TextBarFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    /// Records this view's frame (in the given coordinate space) under `id`.
    func textBarFrame(_ id: String, in space: String) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: TextBarFrameKey.self, value: [id: g.frame(in: .named(space))])
            }
        )
    }

    /// Shared floating-panel chrome: material card, border, drop shadow.
    func panelCardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .fill(Color.gSurface.opacity(0.98))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
            )
            .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous).stroke(Color.gBorderStrong, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}
