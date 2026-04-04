import SwiftUI

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    let notebook: Notebook
    @ObservedObject var viewModel: CanvasViewModel
    let onBack: () -> Void
    let onShowPages: () -> Void
    let onShowPatterns: () -> Void
    var onShowAI: (() -> Void)?
    var isAIPanelVisible: Bool = false

    var body: some View {
        HStack(spacing: GSpacing.xxs) {
            // Back
            Button(action: onBack) {
                HStack(spacing: GSpacing.xxs) {
                    Image(systemName: "chevron.left")
                        .font(.gIconSmall)
                    Text(notebook.name)
                        .font(.gSubheadline.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundColor(.gTextPrimary)
            }
            .minTapTarget()
            .padding(.leading, GSpacing.xs)
            .accessibilityLabel("Back to \(notebook.name)")
            .accessibilityHint("Double tap to return to notebooks")
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            // Center: Drawing tools
            HStack(spacing: 2) {
                ForEach([DrawingTool.pen, .pencil, .marker, .eraser, .lasso], id: \.self) { tool in
                    ToolbarToolButton(
                        tool: tool,
                        isSelected: viewModel.selectedTool == tool,
                        onTap: { viewModel.selectTool(tool) }
                    )
                }

                Divider()
                    .frame(height: 20)
                    .background(Color.gBorderStrong)
                    .padding(.horizontal, GSpacing.xxs)

                ToolbarIconButton(icon: "arrow.up.left.and.arrow.down.right", label: "Select") {
                    viewModel.selectTool(.selection)
                }
            }

            Spacer()

            // Right actions
            HStack(spacing: GSpacing.xxs) {
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .canvasToolbarIcon()
                }
                .minTapTarget()
                .disabled(!viewModel.canUndo)
                .opacity(!viewModel.canUndo ? 0.4 : 1)
                .accessibilityLabel("Undo")
                .accessibilityHint(viewModel.canUndo ? "Double tap to undo last action" : "Nothing to undo")
                .keyboardShortcut("z", modifiers: .command)

                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .canvasToolbarIcon()
                }
                .minTapTarget()
                .disabled(!viewModel.canRedo)
                .opacity(!viewModel.canRedo ? 0.4 : 1)
                .accessibilityLabel("Redo")
                .accessibilityHint(viewModel.canRedo ? "Double tap to redo last action" : "Nothing to redo")
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button(action: onShowPages) {
                    Image(systemName: "doc.on.doc")
                        .canvasToolbarIcon()
                }
                .minTapTarget()
                .accessibilityLabel("Pages")
                .accessibilityHint("Double tap to show page strip")

                Button(action: onShowPatterns) {
                    Image(systemName: "grid")
                        .canvasToolbarIcon()
                }
                .minTapTarget()
                .accessibilityLabel("Background pattern")
                .accessibilityHint("Double tap to change background pattern")

                Button {
                    animateMotionSafe {
                        viewModel.showProperties.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .canvasToolbarIcon(active: viewModel.showProperties)
                }
                .minTapTarget()
                .accessibilityLabel("Properties panel")
                .accessibilityHint(viewModel.showProperties ? "Double tap to hide properties" : "Double tap to show properties")
                .accessibilityAddTraits(viewModel.showProperties ? .isSelected : [])

                if let onShowAI {
                    Button(action: onShowAI) {
                        Image(systemName: "sparkles")
                            .canvasToolbarIcon(active: isAIPanelVisible)
                    }
                    .minTapTarget()
                    .accessibilityLabel("AI Assistant")
                    .accessibilityHint(isAIPanelVisible ? "Double tap to hide AI panel" : "Double tap to show AI panel")
                    .accessibilityAddTraits(isAIPanelVisible ? .isSelected : [])
                }

                // Open in Web deep link
                if let webURL = viewModel.webURL(notebookId: notebook.id) {
                    Link(destination: webURL) {
                        Image(systemName: "globe")
                            .canvasToolbarIcon()
                    }
                    .minTapTarget()
                    .accessibilityLabel("Open in web")
                    .accessibilityHint("Opens this notebook in the web app")
                }

                // Presence badge — shown when notebook is also open on web
                if viewModel.isOpenOnWeb {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Web")
                            .font(.gCaption2.weight(.medium))
                            .foregroundColor(.gTextSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5))
                    )
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Also open on web")
                }

                if viewModel.isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "checkmark.icloud")
                        .canvasToolbarIcon()
                        .opacity(0.5)
                        .accessibilityLabel("Synced")
                }
            }
            .padding(.trailing, GSpacing.xs)
        }
        .frame(height: 48)
        .background(
            Color.gBackground.opacity(0.96)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }
}

// MARK: - Tool Button

struct ToolbarToolButton: View {
    let tool: DrawingTool
    let isSelected: Bool
    let onTap: () -> Void
    var onLongPress: (() -> Void)?

    @State private var showPopover = false

    var body: some View {
        Image(systemName: tool.icon)
            .font(.gIconLarge.weight(isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
            .frame(width: 32, height: 28)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .fill(isSelected ? Color.gPrimaryMuted : .clear)
            )
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.4) {
                HapticEngine.light()
                showPopover = true
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ToolPopoverView(tool: tool)
                    .frame(width: 180)
            }
            .animation(GAnimation.motionSafe(GAnimation.springFast), value: isSelected)
            .accessibilityLabel(tool.label)
            .accessibilityHint(isSelected ? "Selected. Long press for options" : "Double tap to select \(tool.label). Long press for options")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Tool Popover (shown on long-press)

struct ToolPopoverView: View {
    let tool: DrawingTool

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            Text(tool.label)
                .font(.gCaption.weight(.semibold))
                .foregroundColor(.gTextSecondary)
                .textCase(.uppercase)
                .tracking(0.4)

            Text("Default width: \(String(format: "%.1f", tool.defaultWidth))pt")
                .font(.gCaption)
                .foregroundColor(.gTextTertiary)

            if tool != .eraser && tool != .lasso && tool != .selection {
                Text("Tip: Adjust width and color in the Properties panel.")
                    .font(.gCaption2)
                    .foregroundColor(.gTextTertiary)
            }
        }
        .padding(GSpacing.md)
    }
}

// MARK: - Icon Button

struct ToolbarIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.gIconLarge)
                .foregroundColor(.gTextSecondary)
                .frame(width: 32, height: 28)
        }
        .minTapTarget()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Canvas Toolbar Icon Modifier

extension Image {
    func canvasToolbarIcon(active: Bool = false) -> some View {
        self
            .font(.gIconMedium)
            .foregroundColor(active ? .gPrimary : .gTextSecondary)
            .frame(width: 30, height: 30)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: GRadius.xs)
                    .fill(active ? Color.gPrimaryMuted : Color.gElevated)
                    .frame(width: 30, height: 30)
            )
    }
}
