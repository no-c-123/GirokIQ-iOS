import SwiftUI

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    let notebook: Notebook
    @ObservedObject var viewModel: CanvasViewModel
    let onBack: () -> Void

    var body: some View {
        ZStack {
            // Background & Left/Right Elements
            HStack(spacing: 0) {
                // Back
                Button(action: onBack) {
                    HStack(spacing: GSpacing.xxs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text(notebook.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 80)
                    }
                    .foregroundColor(.gTextPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.gElevated))
                }
                .buttonStyle(.plain)
                .minTapTarget()
                .padding(.leading, GSpacing.xs)
                .accessibilityLabel("Back to \(notebook.name)")
                .accessibilityHint("Double tap to return to notebooks")
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                // Presence & Sync Status (compact)
                HStack(spacing: 8) {
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

            // Center: Drawing tools (ZStack keeps it perfectly centered relative to the screen)
            HStack(spacing: 6) {
                ForEach([DrawingTool.pen, .pencil, .marker, .eraser, .lasso, .text, .image], id: \.self) { tool in
                    ToolbarToolButton(
                        tool: tool,
                        isSelected: viewModel.selectedTool == tool,
                        onTap: { viewModel.selectTool(tool) }
                    )
                }

                if viewModel.selectedTool == .image {
                    Divider()
                        .frame(height: 20)
                        .background(Color.gBorderStrong)
                        .padding(.horizontal, GSpacing.xxs)
                        
                    if viewModel.hasPhotoAccess {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: GSpacing.xs) {
                                ForEach(viewModel.recentPhotos.indices, id: \.self) { index in
                                    let asset = viewModel.recentPhotos[index]
                                    if let uiImage = viewModel.recentPhotoImages[asset] {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 38, height: 38)
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
                        .frame(maxWidth: 200)
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
            }
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
            .font(.gIconMedium.weight(isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .white : .gTextSecondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .fill(isSelected ? Color.gPrimary : Color.gElevated.opacity(0.5))
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

            if tool != .eraser && tool != .lasso && tool != .selection && tool != .text && tool != .image {
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
            .foregroundColor(active ? .white : .gTextSecondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: GRadius.xs)
                    .fill(active ? Color.gPrimary : Color.gElevated)
            )
    }
}
