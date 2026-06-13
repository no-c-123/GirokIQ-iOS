import SwiftUI

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    let notebook: Notebook
    @ObservedObject var viewModel: CanvasViewModel
    let onBack: () -> Void

    @State private var exportURL: URL? = nil
    @State private var showExportShare = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: GSpacing.xxs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                    Text(notebook.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120)
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

            HStack(spacing: 8) {
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .canvasToolbarIcon()
                        .opacity(viewModel.canUndo ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canUndo)
                .accessibilityLabel("Undo")

                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .canvasToolbarIcon()
                        .opacity(viewModel.canRedo ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canRedo)
                .accessibilityLabel("Redo")

                Menu {
                    Button {
                        exportURL = viewModel.exportNotebookArchive()
                        showExportShare = exportURL != nil
                    } label: {
                        Label("Export Notebook", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportURL = viewModel.exportNotebookPDF()
                        showExportShare = exportURL != nil
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .canvasToolbarIcon()
                }
                .accessibilityLabel("Download")

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
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
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
