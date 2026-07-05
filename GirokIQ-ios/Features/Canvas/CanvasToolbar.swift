import SwiftUI
internal import UniformTypeIdentifiers

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    let notebook: Notebook
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var syncEngine: SyncEngine
    let onBack: () -> Void

    @State private var archiveDocument = ExportedBinaryDocument(data: Data())
    @State private var archiveDefaultFilename = "Notebook.girokiq"
    @State private var showArchiveExporter = false
    @State private var pdfDocument = ExportedBinaryDocument(data: Data())
    @State private var pdfDefaultFilename = "Notebook.pdf"
    @State private var showPDFExporter = false
    @State private var showPDFPageSelector = false

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
                        exportNotebookArchive()
                    } label: {
                        Label("Export Notebook", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        if viewModel.pages.count <= 1 {
                            exportPDF(pageIndices: [0])
                        } else {
                            showPDFPageSelector = true
                        }
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

                if Configuration.cloudSyncEnabled {
                    syncStatusBadge
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
        .fileExporter(
            isPresented: $showArchiveExporter,
            document: archiveDocument,
            contentType: .girokIQNotebook,
            defaultFilename: archiveDefaultFilename
        ) { _ in }
        .sheet(isPresented: $showPDFPageSelector) {
            PDFPageSelectionSheet(
                pages: viewModel.pages,
                onExportAll: {
                    showPDFPageSelector = false
                    exportPDF(pageIndices: nil)
                },
                onExportSingle: { index in
                    showPDFPageSelector = false
                    exportPDF(pageIndices: [index])
                }
            )
        }
        .fileExporter(
            isPresented: $showPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: pdfDefaultFilename
        ) { _ in }
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        let pending = syncEngine.pendingCount
        let state = syncEngine.state

        if viewModel.isSaving {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Saving")
                    .font(.gCaption2.weight(.medium))
                    .foregroundColor(.gTextSecondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.gElevated))
            .accessibilityLabel("Saving locally")
        } else if case .syncing = state {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Syncing")
                    .font(.gCaption2.weight(.medium))
                    .foregroundColor(.gTextSecondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.gElevated))
            .accessibilityLabel("Syncing to cloud")
        } else if case .paused = state {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Local only")
                    .font(.gCaption2.weight(.medium))
                    .foregroundColor(.gTextSecondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.gElevated))
            .accessibilityLabel("Cloud sync paused. Saving on this device only.")
        } else if pending > 0 {
            HStack(spacing: 6) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gPrimary)
                Text("\(pending) pending")
                    .font(.gCaption2.weight(.medium))
                    .foregroundColor(.gTextSecondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.gElevated))
            .accessibilityLabel("\(pending) changes pending cloud sync")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
                Text("Synced")
                    .font(.gCaption2.weight(.medium))
                    .foregroundColor(.gTextSecondary)
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.gElevated))
            .accessibilityLabel("Synced to cloud")
        }
    }

    private func exportPDF(pageIndices: [Int]?) {
        guard let url = viewModel.exportNotebookPDF(pageIndices: pageIndices),
              let data = try? Data(contentsOf: url) else { return }

        let selectionLabel: String
        if let pageIndices, pageIndices.count == 1, let first = pageIndices.first {
            selectionLabel = "-Page-\(first + 1)"
        } else {
            selectionLabel = ""
        }

        let safeName = notebook.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        pdfDocument = ExportedBinaryDocument(data: data)
        pdfDefaultFilename = "\(safeName)\(selectionLabel).pdf"
        showPDFExporter = true
    }

    private func exportNotebookArchive() {
        guard let url = viewModel.exportNotebookArchive(),
              let data = try? Data(contentsOf: url) else { return }

        let safeName = notebook.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        archiveDocument = ExportedBinaryDocument(data: data)
        archiveDefaultFilename = "\(safeName).girokiq"
        showArchiveExporter = true
    }
}

private struct PDFPageSelectionSheet: View {
    let pages: [DrawingPage]
    let onExportAll: () -> Void
    let onExportSingle: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onExportAll()
                } label: {
                    Label("All Pages", systemImage: "square.stack.3d.up")
                }

                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    Button {
                        onExportSingle(index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(index + 1)")
                            if !page.title.isEmpty {
                                Text(page.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Export PDF")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
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
