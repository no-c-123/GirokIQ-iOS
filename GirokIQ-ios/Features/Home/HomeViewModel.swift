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
    private let recentNotebookIDsKey = "home.recentNotebookIDs"

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

    /// Most recently opened notebooks (falls back to updated order when needed)
    var recentNotebooks: [Notebook] {
        let recents = recentNotebookIDs.compactMap { id in
            notebooks.first(where: { $0.id == id })
        }
        let remaining = notebooks
            .filter { notebook in !recentNotebookIDs.contains(notebook.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return Array((recents + remaining).prefix(5))
    }

    /// Notebooks not in any folder
    var unfolderedNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderId == nil }
    }

    /// Notebooks belonging to a specific folder
    func notebooksInFolder(_ folderId: UUID) -> [Notebook] {
        filteredNotebooks.filter { $0.folderId == folderId }
    }

    private var recentNotebookIDs: [UUID] {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: recentNotebookIDsKey) ?? []
            return strings.compactMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: recentNotebookIDsKey)
        }
    }

    func markNotebookOpened(_ notebook: Notebook) {
        var ids = recentNotebookIDs.filter { $0 != notebook.id }
        ids.insert(notebook.id, at: 0)
        recentNotebookIDs = Array(ids.prefix(20))
        objectWillChange.send()
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

    func createNotebook(
        userId: UUID,
        name: String,
        canvasType: String = "infinite",
        pageDimensions: PageDimensions? = nil,
        backgroundPattern: BackgroundPattern = .blank,
        backgroundColorHex: String = "#0F0F0E"
    ) async -> Notebook? {
        let notebook = Notebook(
            userId: userId,
            name: name,
            canvasType: canvasType,
            pageDimensions: pageDimensions,
            backgroundPattern: backgroundPattern.rawValue,
            backgroundColorHex: backgroundColorHex
        )
        
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

    func importNotebook(from url: URL, userId: UUID) async -> Notebook? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let package = try decoder.decode(NotebookTransferPackage.self, from: data)

            let importedNotebook = Notebook(
                userId: userId,
                name: package.notebook.name,
                canvasType: package.notebook.canvasType,
                pageDimensions: package.notebook.pageDimensions,
                backgroundPattern: package.notebook.backgroundPattern,
                backgroundColorHex: package.notebook.backgroundColorHex
            )

            try await LocalDatabase.shared.saveNotebook(importedNotebook)
            var persistedNotebook: Notebook
            do {
                persistedNotebook = try await service.createNotebook(importedNotebook)
                try await LocalDatabase.shared.saveNotebook(persistedNotebook, syncStatus: .synced)
            } catch {
                print("[Home] Failed to create imported notebook remotely, keeping local copy: \(error)")
                persistedNotebook = importedNotebook
            }

            for entry in package.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
                let newPageId = UUID()
                let remappedElements = entry.elements.map { element in
                    CanvasElement(
                        pageId: newPageId,
                        userId: userId,
                        type: element.type,
                        content: element.content,
                        positionX: element.positionX,
                        positionY: element.positionY,
                        width: element.width,
                        height: element.height,
                        rotation: element.rotation,
                        zIndex: element.zIndex,
                        style: element.style,
                        userResized: element.userResized
                    )
                }

                let page = Page(
                    id: newPageId,
                    userId: userId,
                    notebookId: persistedNotebook.id,
                    title: entry.title,
                    pageIndex: entry.pageIndex,
                    type: entry.type,
                    settings: PageSettings(
                        backgroundPattern: entry.backgroundPattern,
                        zoomScale: nil,
                        drawingData: entry.drawingData?.base64EncodedString(),
                        elements: remappedElements
                    )
                )

                try await LocalDatabase.shared.savePage(page)
                do {
                    let createdPage = try await service.createPage(page)
                    try await LocalDatabase.shared.savePage(createdPage, syncStatus: .synced)
                } catch {
                    print("[Home] Failed to create imported page remotely, keeping local copy: \(error)")
                }
                if let drawingData = entry.drawingData {
                    try await LocalDatabase.shared.savePageDrawing(drawingData, pageId: newPageId)
                }
                if !remappedElements.isEmpty {
                    try await LocalDatabase.shared.saveCanvasElements(remappedElements, forPageId: newPageId)
                    for element in remappedElements {
                        try? await service.upsertCanvasElement(element)
                    }
                }
            }

            notebooks.insert(persistedNotebook, at: 0)
            return persistedNotebook
        } catch {
            self.errorMessage = error.localizedDescription
            print("[Home] Failed to import notebook: \(error)")
            return nil
        }
    }

    func exportNotebookArchive(_ notebook: Notebook) async -> URL? {
        do {
            let fetchedPages = try await LocalDatabase.shared.fetchPages(notebookId: notebook.id)
            let snapshotPages = fetchedPages.enumerated().map { index, tuple in
                NotebookTransferPage(
                    title: tuple.page.title,
                    pageIndex: index,
                    type: tuple.page.type,
                    backgroundPattern: tuple.page.settings?.backgroundPattern ?? notebook.backgroundPattern,
                    drawingData: tuple.drawingData,
                    elements: tuple.page.settings?.elements ?? []
                )
            }

            let package = NotebookTransferPackage(
                version: 1,
                notebook: NotebookTransferNotebook(
                    name: notebook.name,
                    canvasType: notebook.canvasType,
                    pageDimensions: notebook.pageDimensions,
                    backgroundPattern: notebook.backgroundPattern,
                    backgroundColorHex: notebook.backgroundColorHex
                ),
                pages: snapshotPages
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(package)
            let safeName = notebook.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).girokiq")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            self.errorMessage = error.localizedDescription
            print("[Home] Failed to export notebook archive: \(error)")
            return nil
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

    func renameFolder(_ folder: Folder, to newName: String) async {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].name = newName
        var updated = folders[index]
        updated.updatedAt = Date()
        
        do {
            try await LocalDatabase.shared.saveFolder(updated)
        } catch {
            print("[Home] Failed to rename folder locally: \(error)")
        }

        do {
            try await service.updateFolder(updated)
        } catch {
            print("[Home] Failed to rename folder remotely, SyncEngine will retry: \(error)")
        }
    }

    func deleteFolder(_ folder: Folder) async {
        folders.removeAll { $0.id == folder.id }
        
        do {
            try await LocalDatabase.shared.deleteFolder(id: folder.id)
        } catch {
            print("[Home] Failed to delete folder locally: \(error)")
        }
        
        do {
            try await service.deleteFolder(id: folder.id)
        } catch {
            print("[Home] Failed to delete folder remotely, SyncEngine will retry: \(error)")
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
