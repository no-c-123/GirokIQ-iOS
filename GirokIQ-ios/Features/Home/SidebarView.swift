import SwiftUI
internal import UniformTypeIdentifiers

// MARK: - Sidebar View (iPad NavigationSplitView sidebar)

/// Displays folder list and recent notebooks in the sidebar column.
/// Selecting a folder filters the content column; selecting a notebook
/// navigates directly to the detail column.
struct SidebarView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var selectedFolderId: UUID?
    @Binding var selectedNotebook: Notebook?
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSettings = false
    @State private var folderToRename: Folder?
    @State private var renameFolderText = ""
    @State private var showArchiveExporter = false
    @State private var archiveDocument = ExportedBinaryDocument(data: Data())
    @State private var archiveContentType: UTType = .girokIQFolder
    @State private var archiveDefaultFilename = "Folder.girokfolder"

    var body: some View {
        List(selection: $selectedFolderId) {
            // MARK: - All Notebooks
            Section {
                Button {
                    selectedFolderId = nil
                } label: {
                    Label("All Notebooks", systemImage: "book.closed")
                        .foregroundColor(selectedFolderId == nil ? .gPrimary : .gTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("All Notebooks")
                .accessibilityHint("Double tap to show all notebooks")
                .accessibilityAddTraits(selectedFolderId == nil ? .isSelected : [])
            }

            // MARK: - Folders
            if !viewModel.folders.isEmpty {
                Section("Folders") {
                    ForEach(viewModel.folders) { folder in
                        Button {
                            selectedFolderId = folder.id
                        } label: {
                            HStack {
                                Label(folder.name, systemImage: selectedFolderId == folder.id ? "folder.fill" : "folder")
                                Spacer()
                                Text("\(viewModel.notebooksInFolder(folder.id).count)")
                                    .font(.gCaption)
                                    .foregroundColor(.gTextTertiary)
                            }
                            .foregroundColor(selectedFolderId == folder.id ? .gPrimary : .gTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(folder.name) folder, \(viewModel.notebooksInFolder(folder.id).count) notebooks")
                        .accessibilityHint("Double tap to filter by this folder")
                        .accessibilityAddTraits(selectedFolderId == folder.id ? .isSelected : [])
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                renameFolderText = folder.name
                                folderToRename = folder
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.gPrimary)

                            Button {
                                Task { await exportFolderArchive(folder) }
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(Color(hex: "#6FB5A5"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteFolder(folder) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // MARK: - Recents
            Section("Recent") {
                ForEach(viewModel.recentNotebooks) { notebook in
                    Button {
                        viewModel.markNotebookOpened(notebook)
                        selectedNotebook = notebook
                    } label: {
                        HStack(spacing: GSpacing.sm) {
                            recentNotebookIcon(for: notebook)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notebook.name)
                                    .font(.gSubheadline)
                                    .foregroundColor(.gTextPrimary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(notebook.name)")
                    .accessibilityHint("Double tap to open this notebook")
                }
            }

            // MARK: - Actions
            Section {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundColor(.gTextPrimary)
                }
                .accessibilityHint("Double tap to open app settings")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("GirokIQ")
        .fileExporter(
            isPresented: $showArchiveExporter,
            document: archiveDocument,
            contentType: archiveContentType,
            defaultFilename: archiveDefaultFilename
        ) { _ in }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameFolderText)
            Button("Rename") {
                if let folder = folderToRename {
                    let nameToSave = renameFolderText
                    Task { await viewModel.renameFolder(folder, to: nameToSave) }
                }
                folderToRename = nil
                renameFolderText = ""
            }
            Button("Cancel", role: .cancel) { 
                folderToRename = nil
                renameFolderText = ""
            }
        }
    }

    // MARK: - Helpers

    private func exportFolderArchive(_ folder: Folder) async {
        guard let url = await viewModel.exportFolderArchive(folder),
              let data = try? Data(contentsOf: url) else { return }

        let safeName = folder.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        archiveContentType = .girokIQFolder
        archiveDocument = ExportedBinaryDocument(data: data)
        archiveDefaultFilename = "\(safeName.isEmpty ? "Folder" : safeName).girokfolder"
        showArchiveExporter = true
    }

    private func recentNotebookIcon(for notebook: Notebook) -> some View {
        let colors: [Color] = [.gPrimary, Color(hex: "#8B5CF6"), Color(hex: "#06B6D4"), Color(hex: "#10B981"), Color(hex: "#F59E0B"), Color(hex: "#EC4899")]
        let color = colors[abs(notebook.id.hashValue) % colors.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 28, height: 28)
            Text(String(notebook.name.prefix(1)).uppercased())
                .font(.gCaption.weight(.bold))
                .foregroundColor(color)
        }
    }
}
