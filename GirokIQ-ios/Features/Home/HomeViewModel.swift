import Foundation
import Combine
import SwiftUI

// MARK: - Home ViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var notebooks: [Notebook] = []
    @Published var folders: [Folder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var viewMode: ViewMode = .grid
    @Published var searchText: String = ""
    @Published var expandedFolderIds: Set<UUID> = []
    @Published var selectedFolderId: UUID?

    enum ViewMode { case grid, list }

    private let service = SupabaseService.shared

    // MARK: - Derived Data (business logic belongs here, not in Views)

    /// Notebooks filtered by search text
    var filteredNotebooks: [Notebook] {
        if searchText.isEmpty { return notebooks }
        let query = searchText.lowercased()
        return notebooks.filter { $0.name.lowercased().contains(query) }
    }

    /// Notebooks filtered by both search text and the active folder selection
    var displayedNotebooks: [Notebook] {
        let filtered = filteredNotebooks
        if let folderId = selectedFolderId {
            return filtered.filter { $0.folderId == folderId }
        }
        return filtered
    }

    /// Unfoldered notebooks within the current display set
    var displayedUnfolderedNotebooks: [Notebook] {
        if selectedFolderId != nil {
            return displayedNotebooks  // Already filtered to one folder
        }
        return displayedNotebooks.filter { $0.folderId == nil }
    }

    /// Folders to display (hidden when a specific folder is selected)
    var displayedFolders: [Folder] {
        if selectedFolderId != nil { return [] }
        return folders
    }

    /// Most recently updated notebooks (for sidebar "Recents" section)
    var recentNotebooks: [Notebook] {
        Array(notebooks.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }

    /// Notebooks not in any folder
    var unfolderedNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderId == nil }
    }

    /// Notebooks belonging to a specific folder
    func notebooksInFolder(_ folderId: UUID) -> [Notebook] {
        filteredNotebooks.filter { $0.folderId == folderId }
    }

    // MARK: - Loading

    func loadNotebooks(userId: UUID) async {
        isLoading = true
        do {
            async let notebooksResult = service.fetchNotebooks(userId: userId)
            async let foldersResult = service.fetchFolders(userId: userId)
            let fetchedNotebooks = try await notebooksResult
            let fetchedFolders = try await foldersResult
            
            notebooks = fetchedNotebooks
            folders = fetchedFolders
            
            // Save fetched data to local database so foreign keys (like notebook_id on pages) are satisfied
            Task.detached(priority: .utility) {
                for notebook in fetchedNotebooks {
                    try? await LocalDatabase.shared.saveNotebook(notebook, syncStatus: .synced)
                }
                for folder in fetchedFolders {
                    try? await LocalDatabase.shared.saveFolder(folder, syncStatus: .synced)
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
            // Fallback to local mock data for offline/demo
            notebooks = Self.mockNotebooks(userId: userId)
        }
        isLoading = false
    }

    // MARK: - Notebook CRUD

    func createNotebook(userId: UUID, name: String) async -> Notebook? {
        let notebook = Notebook(userId: userId, name: name)
        
        // Save locally first so pages can safely reference it via Foreign Key
        do {
            try await LocalDatabase.shared.saveNotebook(notebook)
        } catch {
            print("[Home] Failed to save notebook locally: \(error)")
        }
        
        do {
            let created = try await service.createNotebook(notebook)
            notebooks.insert(created, at: 0)
            return created
        } catch {
            print("[Home] Failed to create notebook remotely, SyncEngine will retry: \(error)")
            notebooks.insert(notebook, at: 0)
            return notebook
        }
    }

    func deleteNotebook(_ notebook: Notebook) async {
        notebooks.removeAll { $0.id == notebook.id }
        do {
            try await service.deleteNotebook(id: notebook.id)
        } catch {
            print("[Home] Failed to delete notebook remotely, SyncEngine will retry: \(error)")
        }
    }

    func renameNotebook(_ notebook: Notebook, to newName: String) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].name = newName
        var updated = notebooks[index]
        updated.updatedAt = Date()
        do {
            try await service.updateNotebook(updated)
        } catch {
            print("[Home] Failed to rename notebook remotely, SyncEngine will retry: \(error)")
        }
    }

    func moveNotebookToFolder(_ notebook: Notebook, folderId: UUID?) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].folderId = folderId
        var updated = notebooks[index]
        updated.updatedAt = Date()
        do {
            try await service.updateNotebook(updated)
        } catch {
            print("[Home] Failed to move notebook remotely, SyncEngine will retry: \(error)")
        }
    }

    // MARK: - Folder CRUD

    func createFolder(userId: UUID, name: String) async -> Folder? {
        let folder = Folder(id: UUID(), userId: userId, name: name)
        
        // Save locally first
        do {
            try await LocalDatabase.shared.saveFolder(folder)
        } catch {
            print("[Home] Failed to save folder locally: \(error)")
        }
        
        do {
            let created = try await service.createFolder(folder)
            folders.insert(created, at: 0)
            return created
        } catch {
            print("[Home] Failed to create folder remotely, saving locally: \(error)")
            folders.insert(folder, at: 0)
            return folder
        }
    }

    func toggleFolder(_ folderId: UUID) {
        if expandedFolderIds.contains(folderId) {
            expandedFolderIds.remove(folderId)
        } else {
            expandedFolderIds.insert(folderId)
        }
    }

    // MARK: - Mock Data

    static func mockNotebooks(userId: UUID) -> [Notebook] {
        let names = ["Design System", "Meeting Notes", "Project Alpha", "Research"]
        return names.map { name in
            Notebook(userId: userId, name: name)
        }
    }
}
