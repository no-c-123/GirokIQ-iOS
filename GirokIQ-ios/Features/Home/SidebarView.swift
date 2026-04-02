import SwiftUI

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

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showSettings = false

    var body: some View {
        List(selection: $selectedFolderId) {
            // MARK: - All Notebooks
            Section {
                Button {
                    selectedFolderId = nil
                } label: {
                    Label("All Notebooks", systemImage: "book.closed")
                        .foregroundColor(selectedFolderId == nil ? .gPrimary : .gTextPrimary(for: colorScheme))
                }
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
                                    .foregroundColor(.gTextTertiary(for: colorScheme))
                            }
                            .foregroundColor(selectedFolderId == folder.id ? .gPrimary : .gTextPrimary(for: colorScheme))
                        }
                    }
                }
            }

            // MARK: - Recents
            Section("Recent") {
                ForEach(recentNotebooks) { notebook in
                    Button {
                        selectedNotebook = notebook
                    } label: {
                        HStack(spacing: GSpacing.sm) {
                            recentNotebookIcon(for: notebook)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notebook.name)
                                    .font(.gSubheadline)
                                    .foregroundColor(.gTextPrimary(for: colorScheme))
                                    .lineLimit(1)
                                Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.gCaption2)
                                    .foregroundColor(.gTextTertiary(for: colorScheme))
                            }
                        }
                    }
                }
            }

            // MARK: - Actions
            Section {
                Button {
                    showNewFolderAlert = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .foregroundColor(.gPrimary)
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundColor(.gTextPrimary(for: colorScheme))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("GirokIQ")
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let userId = authViewModel.currentUserId, !newFolderName.isEmpty {
                    Task { await viewModel.createFolder(userId: userId, name: newFolderName) }
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Helpers

    /// Most recently updated 5 notebooks
    private var recentNotebooks: [Notebook] {
        Array(viewModel.notebooks.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
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
