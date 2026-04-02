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

    enum ViewMode { case grid, list }

    private let service = SupabaseService.shared

    /// Notebooks filtered by search text
    var filteredNotebooks: [Notebook] {
        if searchText.isEmpty { return notebooks }
        let query = searchText.lowercased()
        return notebooks.filter { $0.name.lowercased().contains(query) }
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
            notebooks = try await notebooksResult
            folders = try await foldersResult
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
        do {
            let created = try await service.createNotebook(notebook)
            notebooks.insert(created, at: 0)
            return created
        } catch {
            // Offline-first: save locally
            notebooks.insert(notebook, at: 0)
            return notebook
        }
    }

    func deleteNotebook(_ notebook: Notebook) async {
        notebooks.removeAll { $0.id == notebook.id }
        do {
            try await service.deleteNotebook(id: notebook.id)
        } catch {
            // Silently fail — SyncEngine will retry
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
            // Offline — SyncEngine will retry
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
            // Offline — SyncEngine will retry
        }
    }

    // MARK: - Folder CRUD

    func createFolder(userId: UUID, name: String) async -> Folder? {
        let folder = Folder(id: UUID(), userId: userId, name: name)
        do {
            let created = try await service.createFolder(folder)
            folders.insert(created, at: 0)
            return created
        } catch {
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
