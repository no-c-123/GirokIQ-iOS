import Foundation
import Combine
import SwiftUI

// MARK: - Home ViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    enum ViewMode { case grid, list }
    enum LibrarySection { case library, trash }
    enum NotebookCloudSyncState: Equatable {
        case synced
        case pending
        case localOnly
        case neverSynced
    }

    struct StorageUsage: Equatable {
        let quotaStatus: CloudStorageQuotaStatus

        init(status: CloudStorageQuotaStatus = .empty) {
            self.quotaStatus = status
        }

        var progress: Double { quotaStatus.progress }
        var usedText: String { quotaStatus.usedText }
        var limitText: String { quotaStatus.limitText }
        var remainingText: String { quotaStatus.remainingText }
        var level: CloudStorageQuotaLevel { quotaStatus.level }
        var statusMessage: String { quotaStatus.statusMessage }
        var canSyncToCloud: Bool { quotaStatus.canSyncToCloud }
    }

    struct NotebookStorageBreakdownItem: Identifiable, Equatable {
        let notebook: Notebook
        let usedBytes: Int64
        let limitBytes: Int64
        let percentOfQuota: Double
        let syncState: NotebookCloudSyncState
        let pendingChangeCount: Int
        let lastSyncedAt: Date?

        var id: UUID { notebook.id }
        var usedText: String { Self.byteFormatter.string(fromByteCount: usedBytes) }
        var quotaShareText: String {
            let limitText = Self.byteFormatter.string(fromByteCount: limitBytes)
            return "\(Int((percentOfQuota * 100).rounded()))% of \(limitText)"
        }

        private static let byteFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            formatter.includesUnit = true
            formatter.isAdaptive = true
            return formatter
        }()
    }

    @Published var notebooks: [Notebook] = []
    @Published var folders: [Folder] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var importingNotebookName: String?
    @Published var errorMessage: String?
    @Published var viewMode: ViewMode = .grid
    @Published var searchText: String = ""
    @Published var expandedFolderIds: Set<UUID> = []
    @Published var selectedFolderId: UUID?
    @Published var selectedSection: LibrarySection = .library
    @Published private(set) var storageUsage = StorageUsage()
    @Published private(set) var storageBreakdown: [NotebookStorageBreakdownItem] = []
    @Published var quotaNoticeMessage: String?

    private let service = SupabaseService.shared
    private let quotaService = CloudStorageQuotaService.shared
    private let recentNotebookIDsKey = "home.recentNotebookIDs"
    private let expandedFolderIDsKey = "home.expandedFolderIDs"
    private let trashRetentionInterval: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Derived Data (business logic belongs here, not in Views)

    private func matchesSearch(_ value: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(searchText)
    }

    var activeFolders: [Folder] {
        folders.filter { $0.trashedAt == nil }
    }

    var trashedFolders: [Folder] {
        folders.filter { $0.trashedAt != nil }
    }

    private var trashedFolderIDs: Set<UUID> {
        Set(trashedFolders.map(\.id))
    }

    var activeNotebooks: [Notebook] {
        notebooks.filter { notebook in
            notebook.trashedAt == nil && !trashedFolderIDs.contains(notebook.folderId ?? UUID())
        }
    }

    var trashedNotebooks: [Notebook] {
        notebooks.filter { $0.trashedAt != nil }
    }

    /// Active notebooks filtered by search text
    var filteredNotebooks: [Notebook] {
        activeNotebooks.filter { matchesSearch($0.name) }
    }

    var filteredFolders: [Folder] {
        activeFolders.filter { matchesSearch($0.name) }
    }

    var filteredTrashNotebooks: [Notebook] {
        trashedNotebooks
            .filter { notebook in
                let parentFolderIsAlsoTrashed = notebook.folderId.map { trashedFolderIDs.contains($0) } ?? false
                return !parentFolderIsAlsoTrashed
            }
            .filter { matchesSearch($0.name) }
    }

    var filteredTrashFolders: [Folder] {
        trashedFolders.filter { matchesSearch($0.name) }
    }

    /// Notebooks filtered by both search text and the active folder selection
    var displayedNotebooks: [Notebook] {
        guard selectedSection == .library else { return [] }
        let filtered = filteredNotebooks
        if let folderId = selectedFolderId {
            return filtered.filter { $0.folderId == folderId }
        }
        return filtered
    }

    /// Unfoldered notebooks within the current display set
    var displayedUnfolderedNotebooks: [Notebook] {
        guard selectedSection == .library else { return [] }
        if selectedFolderId != nil {
            return displayedNotebooks  // Already filtered to one folder
        }
        return displayedNotebooks.filter { $0.folderId == nil }
    }

    /// Folders to display (hidden when a specific folder is selected)
    var displayedFolders: [Folder] {
        if selectedSection != .library || selectedFolderId != nil { return [] }
        return filteredFolders
    }

    /// Most recently opened notebooks (falls back to updated order when needed)
    var recentNotebooks: [Notebook] {
        let recents = recentNotebookIDs.compactMap { id in
            activeNotebooks.first(where: { $0.id == id })
        }
        let remaining = activeNotebooks
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

    func trashedNotebooksInFolder(_ folderId: UUID) -> [Notebook] {
        trashedNotebooks
            .filter { $0.folderId == folderId }
            .filter { matchesSearch($0.name) }
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

    private var persistedExpandedFolderIDs: Set<UUID> {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: expandedFolderIDsKey) ?? []
            return Set(strings.compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(Array(newValue).map(\.uuidString), forKey: expandedFolderIDsKey)
        }
    }

    init() {
        expandedFolderIds = persistedExpandedFolderIDs
    }

    func markNotebookOpened(_ notebook: Notebook) {
        guard notebook.trashedAt == nil else { return }
        var ids = recentNotebookIDs.filter { $0 != notebook.id }
        ids.insert(notebook.id, at: 0)
        recentNotebookIDs = Array(ids.prefix(20))
        UserDefaults.standard.set(notebook.id.uuidString, forKey: "home.lastOpenedNotebookID")
        objectWillChange.send()
    }

    func lastOpenedNotebook() -> Notebook? {
        guard let idString = UserDefaults.standard.string(forKey: "home.lastOpenedNotebookID"),
              let id = UUID(uuidString: idString) else { return nil }
        return activeNotebooks.first(where: { $0.id == id })
    }

    // MARK: - Loading

    func loadNotebooks(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        var localNotebooksSnapshot: [Notebook] = []
        var localFoldersSnapshot: [Folder] = []

        // Offline-first: load local cache immediately so the user can open notebooks
        // even when there's no network.
        do {
            let localNotebooks = try await LocalDatabase.shared.fetchNotebooks(userId: userId)
            let localFolders = try await LocalDatabase.shared.fetchFolders(userId: userId)
            localNotebooksSnapshot = localNotebooks
            localFoldersSnapshot = localFolders
            notebooks = localNotebooks
            folders = localFolders
            expandedFolderIds.formIntersection(Set(localFolders.map(\.id)))
            persistedExpandedFolderIDs = expandedFolderIds
            await refreshStorageUsage(userId: userId)
        } catch {
            // If local DB fails, keep going and try remote.
        }

        // Stop blocking the UI. We'll refresh from remote opportunistically.
        isLoading = false

        guard Configuration.cloudSyncEnabled else {
            // Local-only mode: keep the local cache as the source of truth.
            return
        }

        do {
            async let notebooksResult = service.fetchNotebooks(userId: userId)
            async let foldersResult = service.fetchFolders(userId: userId)
            let fetchedNotebooks = try await notebooksResult
            let fetchedFolders = try await foldersResult

            // Merge remote snapshot with any local-only items not present remotely.
            // This avoids a confusing state where the library shows 1 remote notebook
            // but the storage meter still counts many local pending notebooks.
            let remoteNotebookIDs = Set(fetchedNotebooks.map(\.id))
            let remoteFolderIDs = Set(fetchedFolders.map(\.id))
            let mergedNotebooks = (fetchedNotebooks + localNotebooksSnapshot.filter { !remoteNotebookIDs.contains($0.id) })
                .sorted { $0.updatedAt > $1.updatedAt }
            let mergedFolders = (fetchedFolders + localFoldersSnapshot.filter { !remoteFolderIDs.contains($0.id) })
                .sorted { $0.createdAt > $1.createdAt }

            notebooks = mergedNotebooks
            folders = mergedFolders
            expandedFolderIds.formIntersection(Set(fetchedFolders.map(\.id)))
            persistedExpandedFolderIDs = expandedFolderIds
            await cleanupExpiredTrash()

            // Persist the remote snapshot only (NOT the merged list) to avoid accidentally
            // treating local-only notebooks as cloud truth.
            let notebooksToPersist = fetchedNotebooks
            let foldersToPersist = fetchedFolders

            // Save fetched data to local database so foreign keys (like notebook_id on pages) are satisfied
            Task.detached(priority: .utility) {
                // 1) Persist the remote snapshot locally.
                for folder in foldersToPersist {
                    try? await LocalDatabase.shared.saveFolder(folder, syncStatus: .synced)
                }
                for notebook in notebooksToPersist {
                    try? await LocalDatabase.shared.saveNotebook(notebook, syncStatus: .synced)
                }

                // 2) Reconcile: if a notebook/folder was deleted remotely (e.g. via Supabase dashboard),
                // remove the local copy so storage usage drops and the app doesn't try to re-upload it.
                await self.reconcileRemoteDeletions(
                    userId: userId,
                    remoteNotebooks: notebooksToPersist,
                    remoteFolders: foldersToPersist
                )

                // 3) Refresh the storage meter after local DB updates complete.
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    Task { await self.refreshStorageUsage(userId: userId) }
                }
            }
        } catch {
            // Keep offline cache visible; don't clear the library UI.
            errorMessage = nil
        }
    }

    /// When remote data was modified outside the app (e.g. rows deleted in Supabase),
    /// our local-first cache can retain content and keep the quota meter high.
    ///
    /// This routine removes *synced* local folders/notebooks that are no longer present remotely,
    /// but it will not delete items with pending local changes.
    private func reconcileRemoteDeletions(
        userId: UUID,
        remoteNotebooks: [Notebook],
        remoteFolders: [Folder]
    ) async {
        do {
            let remoteNotebookIDs = Set(remoteNotebooks.map(\.id))
            let remoteFolderIDs = Set(remoteFolders.map(\.id))

            let pendingNotebookIDs = try await LocalDatabase.shared.pendingChangeIDs(table: "notebook")
            let pendingFolderIDs = try await LocalDatabase.shared.pendingChangeIDs(table: "folder")
            let pendingNotebooksFromPages = try await LocalDatabase.shared.notebookIDsWithPendingPageChanges(userId: userId)

            let localNotebooks = try await LocalDatabase.shared.fetchNotebooks(userId: userId)
            for notebook in localNotebooks {
                guard !remoteNotebookIDs.contains(notebook.id) else { continue }
                guard !pendingNotebookIDs.contains(notebook.id.uuidString) else { continue }
                guard !pendingNotebooksFromPages.contains(notebook.id) else { continue }
                try? await LocalDatabase.shared.deleteNotebook(id: notebook.id, syncStatus: .synced)
            }

            let localFolders = try await LocalDatabase.shared.fetchFolders(userId: userId)
            for folder in localFolders {
                guard !remoteFolderIDs.contains(folder.id) else { continue }
                guard !pendingFolderIDs.contains(folder.id.uuidString) else { continue }
                try? await LocalDatabase.shared.deleteFolder(id: folder.id, syncStatus: .synced)
            }
        } catch {
            // Best-effort; reconciliation shouldn't break normal loading.
            #if DEBUG
            print("[Home] Remote deletion reconcile failed: \(error)")
            #endif
        }
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
            #if DEBUG
            print("[Home] Failed to save notebook locally: \(error)")
            #endif
        }

        notebooks.insert(notebook, at: 0)
        await quotaService.invalidateCache()
        _ = await refreshStorageUsage(userId: userId)

        guard Configuration.cloudSyncEnabled else {
            return notebook
        }

        do {
            let created = try await service.createNotebook(notebook)
            if let index = notebooks.firstIndex(where: { $0.id == notebook.id }) {
                notebooks[index] = created
            }
            return created
        } catch {
            #if DEBUG
            print("[Home] Failed to create notebook remotely, SyncEngine will retry: \(error)")
            #endif
            return notebook
        }
    }

    @discardableResult
    func importArchive(from url: URL, userId: UUID) async -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            isImporting = true
            importingNotebookName = url.deletingPathExtension().lastPathComponent
            defer {
                isImporting = false
                importingNotebookName = nil
            }

            let data = try Data(contentsOf: url)
            let decoder = makeTransferDecoder()

            if let folderPackage = try? decoder.decode(FolderTransferPackage.self, from: data) {
                importingNotebookName = folderPackage.folder.name
                _ = try await importFolderPackage(folderPackage, userId: userId)
            } else {
                let package = try decoder.decode(NotebookTransferPackage.self, from: data)
                importingNotebookName = package.notebook.name
                let importedNotebook = try await importNotebookPackage(
                    package,
                    userId: userId,
                    folderId: nil,
                    syncToCloud: false
                )
                if Configuration.cloudSyncEnabled {
                    let canSync = await canSyncToCloud(userId: userId, showLocalOnlyNotice: true)
                    if canSync {
                        do {
                            _ = try await syncImportedNotebookToCloud(importedNotebook)
                        } catch {
                            #if DEBUG
                            print("[Home] Failed to create imported notebook remotely, keeping local copy: \(error)")
                            #endif
                        }
                    }
                }
                await quotaService.invalidateCache()
                await refreshStorageUsage(userId: userId)
            }

            return true
        } catch {
            self.errorMessage = error.localizedDescription
            #if DEBUG
            print("[Home] Failed to import archive: \(error)")
            #endif
            return false
        }
    }

    func exportNotebookArchive(_ notebook: Notebook) async -> URL? {
        do {
            let package = try await makeNotebookTransferPackage(for: notebook)
            let data = try makeTransferEncoder().encode(package)
            let safeName = sanitizedArchiveName(notebook.name, fallback: "Notebook")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).girokiq")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            self.errorMessage = error.localizedDescription
            #if DEBUG
            print("[Home] Failed to export notebook archive: \(error)")
            #endif
            return nil
        }
    }

    func exportFolderArchive(_ folder: Folder) async -> URL? {
        do {
            let folderNotebooks = try await exportableNotebooks(in: folder)
            var notebookPackages: [NotebookTransferPackage] = []
            notebookPackages.reserveCapacity(folderNotebooks.count)
            for notebook in folderNotebooks {
                notebookPackages.append(try await makeNotebookTransferPackage(for: notebook))
            }
            let package = FolderTransferPackage(
                version: 1,
                folder: FolderTransferFolder(name: folder.name),
                notebooks: notebookPackages
            )
            let data = try makeTransferEncoder().encode(package)
            let safeName = sanitizedArchiveName(folder.name, fallback: "Folder")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).girokfolder")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            self.errorMessage = error.localizedDescription
            #if DEBUG
            print("[Home] Failed to export folder archive: \(error)")
            #endif
            return nil
        }
    }

    private func importFolderPackage(_ package: FolderTransferPackage, userId: UUID) async throws -> Folder {
        let importedFolder = Folder(
            userId: userId,
            name: package.folder.name.isEmpty ? "Imported Folder" : package.folder.name
        )

        try await LocalDatabase.shared.saveFolder(importedFolder)
        folders.insert(importedFolder, at: 0)
        selectedSection = .library
        selectedFolderId = importedFolder.id

        var importedNotebooks: [Notebook] = []
        for notebookPackage in package.notebooks {
            let notebook = try await importNotebookPackage(
                notebookPackage,
                userId: userId,
                folderId: importedFolder.id,
                syncToCloud: false
            )
            importedNotebooks.append(notebook)
        }

        guard Configuration.cloudSyncEnabled else {
            await quotaService.invalidateCache()
            await refreshStorageUsage(userId: userId)
            return importedFolder
        }

        let canSync = await canSyncToCloud(userId: userId, showLocalOnlyNotice: true)
        guard canSync else {
            await quotaService.invalidateCache()
            await refreshStorageUsage(userId: userId)
            return importedFolder
        }

        do {
            let createdFolder = try await service.createFolder(importedFolder)
            if let index = folders.firstIndex(where: { $0.id == importedFolder.id }) {
                folders[index] = createdFolder
            }
            try await LocalDatabase.shared.saveFolder(createdFolder, syncStatus: .synced)

            for notebook in importedNotebooks {
                do {
                    _ = try await syncImportedNotebookToCloud(notebook)
                } catch {
                    #if DEBUG
                    print("[Home] Failed to sync imported notebook in folder archive: \(error)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("[Home] Failed to create imported folder remotely, keeping local copy: \(error)")
            #endif
        }

        await quotaService.invalidateCache()
        await refreshStorageUsage(userId: userId)
        return importedFolder
    }

    @discardableResult
    private func importNotebookPackage(
        _ package: NotebookTransferPackage,
        userId: UUID,
        folderId: UUID?,
        syncToCloud: Bool
    ) async throws -> Notebook {
        let importedNotebook = Notebook(
            userId: userId,
            folderId: folderId,
            name: package.notebook.name,
            canvasType: package.notebook.canvasType,
            pageDimensions: package.notebook.pageDimensions,
            backgroundPattern: package.notebook.backgroundPattern,
            backgroundColorHex: package.notebook.backgroundColorHex
        )

        try await LocalDatabase.shared.saveNotebook(importedNotebook)

        for entry in package.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            let newPageId = UUID()
            let remappedElements: [CanvasElement] = entry.elements.map { element -> CanvasElement in
                var remappedStyle = element.style
                var remappedContent = element.content

                if element.type == "image",
                   let originalFileName = element.content,
                   let asset = package.assets.first(where: { $0.fileName == originalFileName }),
                   let importedFileName = try? NotebookTransferSupport.writeImportedImageAsset(
                    asset,
                    preservingExtensionFrom: originalFileName
                   ) {
                    remappedContent = importedFileName
                    remappedStyle?.imageAssetPath = "\(userId.uuidString)/\(importedNotebook.id.uuidString)/\(importedFileName)"
                }

                return CanvasElement(
                    pageId: newPageId,
                    userId: userId,
                    type: element.type,
                    content: remappedContent,
                    positionX: element.positionX,
                    positionY: element.positionY,
                    width: element.width,
                    height: element.height,
                    rotation: element.rotation,
                    zIndex: element.zIndex,
                    style: remappedStyle,
                    userResized: element.userResized
                )
            }

            let page = Page(
                id: newPageId,
                userId: userId,
                notebookId: importedNotebook.id,
                title: entry.title,
                pageIndex: entry.pageIndex,
                type: entry.type,
                settings: PageSettings(
                    backgroundPattern: entry.backgroundPattern,
                    zoomScale: nil,
                    drawingData: nil,
                    elements: remappedElements
                )
            )

            try await LocalDatabase.shared.savePage(page)
            if let drawingData = entry.drawingData {
                try await LocalDatabase.shared.savePageDrawing(drawingData, pageId: newPageId)
            }
            if !remappedElements.isEmpty {
                try await LocalDatabase.shared.saveCanvasElements(remappedElements, forPageId: newPageId)
            }
        }

        notebooks.insert(importedNotebook, at: 0)

        if syncToCloud {
            do {
                return try await syncImportedNotebookToCloud(importedNotebook)
            } catch {
                #if DEBUG
                print("[Home] Failed to create imported notebook remotely, keeping local copy: \(error)")
                #endif
            }
        }

        return importedNotebook
    }

    @discardableResult
    private func syncImportedNotebookToCloud(_ notebook: Notebook) async throws -> Notebook {
        guard Configuration.cloudSyncEnabled else { return notebook }
        let createdNotebook = try await service.createNotebook(notebook)
        try await LocalDatabase.shared.saveNotebook(createdNotebook, syncStatus: .synced)
        let pages = try await LocalDatabase.shared.fetchPages(notebookId: notebook.id)

        for tuple in pages.sorted(by: { $0.page.pageIndex < $1.page.pageIndex }) {
            var remotePage = tuple.page
            var remoteSettings = remotePage.settings ?? PageSettings()
            remoteSettings.drawingData = tuple.drawingData?.base64EncodedString()
            remotePage.settings = remoteSettings

            let createdPage = try await service.createPage(remotePage)
            try await LocalDatabase.shared.savePage(createdPage, syncStatus: .synced)

            for element in tuple.page.settings?.elements ?? [] {
                try? await service.upsertCanvasElement(element)
                if element.type == "image",
                   let fileName = element.content,
                   let remotePath = element.style?.imageAssetPath {
                    let localURL = NotebookTransferSupport.localImageURL(for: fileName)
                    if let imageData = try? Data(contentsOf: localURL) {
                        try? await service.uploadCanvasImage(
                            data: imageData,
                            path: remotePath,
                            contentType: NotebookTransferSupport.mimeType(for: fileName)
                        )
                    }
                }
            }
        }

        if let index = notebooks.firstIndex(where: { $0.id == notebook.id }) {
            notebooks[index] = createdNotebook
        }

        return createdNotebook
    }

    private func makeNotebookTransferPackage(for notebook: Notebook) async throws -> NotebookTransferPackage {
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

        return NotebookTransferPackage(
            version: 2,
            notebook: NotebookTransferNotebook(
                name: notebook.name,
                canvasType: notebook.canvasType,
                pageDimensions: notebook.pageDimensions,
                backgroundPattern: notebook.backgroundPattern,
                backgroundColorHex: notebook.backgroundColorHex
            ),
            pages: snapshotPages,
            assets: NotebookTransferSupport.imageAssets(from: snapshotPages)
        )
    }

    private func exportableNotebooks(in folder: Folder) async throws -> [Notebook] {
        let folderNotebookIDs = Set(
            notebooks
                .filter { $0.folderId == folder.id && $0.trashedAt == nil }
                .map(\.id)
        )
        let localNotebooks = try await LocalDatabase.shared.fetchNotebooks(userId: folder.userId)
        return localNotebooks
            .filter { folderNotebookIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func makeTransferEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeTransferDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func sanitizedArchiveName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = (trimmed.isEmpty ? fallback : trimmed)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safeName.isEmpty ? fallback : safeName
    }

    func deleteNotebook(_ notebook: Notebook) async {
        await moveNotebookToTrash(notebook)
    }

    func renameNotebook(_ notebook: Notebook, to newName: String) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].name = newName
        var updated = notebooks[index]
        updated.updatedAt = Date()

        do {
            try await LocalDatabase.shared.saveNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to rename notebook locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else { return }
        do {
            let canSync = await canSyncToCloud(userId: updated.userId)
            guard canSync else { return }
            try await service.updateNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to rename notebook remotely, SyncEngine will retry: \(error)")
            #endif
        }
    }

    func moveNotebookToFolder(_ notebook: Notebook, folderId: UUID?) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].folderId = folderId
        var updated = notebooks[index]
        updated.updatedAt = Date()

        do {
            try await LocalDatabase.shared.saveNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to move notebook locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else { return }
        do {
            let canSync = await canSyncToCloud(userId: updated.userId)
            guard canSync else { return }
            try await service.updateNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to move notebook remotely, SyncEngine will retry: \(error)")
            #endif
        }
    }

    func moveNotebookToTrash(_ notebook: Notebook) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        let timestamp = Date()
        notebooks[index].trashedAt = timestamp
        notebooks[index].updatedAt = timestamp
        let updated = notebooks[index]

        do {
            try await LocalDatabase.shared.saveNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to move notebook to trash locally: \(error)")
            #endif
        }

        await quotaService.invalidateCache()
        _ = await refreshStorageUsage(userId: updated.userId)

        guard Configuration.cloudSyncEnabled else { return }
        do {
            let canSync = await canSyncToCloud(userId: updated.userId)
            guard canSync else { return }
            try await service.moveNotebookToTrash(id: updated.id, trashedAt: timestamp)
        } catch {
            #if DEBUG
            print("[Home] Failed to move notebook to trash remotely, SyncEngine will retry: \(error)")
            #endif
        }
    }

    func restoreNotebook(_ notebook: Notebook) async {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index].trashedAt = nil
        notebooks[index].updatedAt = Date()
        let updated = notebooks[index]

        do {
            try await LocalDatabase.shared.saveNotebook(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to restore notebook locally: \(error)")
            #endif
        }

        await quotaService.invalidateCache()
        _ = await refreshStorageUsage(userId: updated.userId)

        guard Configuration.cloudSyncEnabled else { return }
        do {
            let canSync = await canSyncToCloud(userId: updated.userId)
            guard canSync else { return }
            try await service.restoreNotebook(id: updated.id)
        } catch {
            #if DEBUG
            print("[Home] Failed to restore notebook remotely, SyncEngine will retry: \(error)")
            #endif
        }
    }

    func permanentlyDeleteNotebook(_ notebook: Notebook) async {
        notebooks.removeAll { $0.id == notebook.id }

        do {
            try await LocalDatabase.shared.deleteNotebook(id: notebook.id, syncStatus: .pending)
        } catch {
            #if DEBUG
            print("[Home] Failed to delete notebook locally: \(error)")
            #endif
        }

        await quotaService.invalidateCache()

        guard Configuration.cloudSyncEnabled else {
            _ = await refreshStorageUsage(userId: notebook.userId)
            return
        }

        let canSync = await refreshStorageUsage(userId: notebook.userId).canSyncToCloud
        do {
            guard canSync else { return }
            try await service.deleteNotebook(id: notebook.id)
            try? await LocalDatabase.shared.markSynced(table: "notebook", id: notebook.id.uuidString)
        } catch {
            #if DEBUG
            print("[Home] Failed to permanently delete notebook remotely: \(error)")
            #endif
        }
    }

    // MARK: - Folder CRUD

    func createFolder(userId: UUID, name: String) async -> Folder? {
        let folder = Folder(id: UUID(), userId: userId, name: name)
        
        // Save locally first
        do {
            try await LocalDatabase.shared.saveFolder(folder)
        } catch {
            #if DEBUG
            print("[Home] Failed to save folder locally: \(error)")
            #endif
        }
        
        folders.insert(folder, at: 0)

        guard Configuration.cloudSyncEnabled else { return folder }

        do {
            let canSync = await canSyncToCloud(userId: userId)
            guard canSync else { return folder }

            let created = try await service.createFolder(folder)
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index] = created
            }
            return created
        } catch {
            #if DEBUG
            print("[Home] Failed to create folder remotely, saving locally: \(error)")
            #endif
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
            #if DEBUG
            print("[Home] Failed to rename folder locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else { return }
        do {
            let canSync = await canSyncToCloud(userId: updated.userId)
            guard canSync else { return }
            try await service.updateFolder(updated)
        } catch {
            #if DEBUG
            print("[Home] Failed to rename folder remotely, SyncEngine will retry: \(error)")
            #endif
        }
    }

    func deleteFolder(_ folder: Folder) async {
        await moveFolderToTrash(folder)
    }

    func toggleFolder(_ folderId: UUID) {
        if expandedFolderIds.contains(folderId) {
            expandedFolderIds.remove(folderId)
        } else {
            expandedFolderIds.insert(folderId)
        }
        persistedExpandedFolderIDs = expandedFolderIds
    }

    func moveFolderToTrash(_ folder: Folder) async {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let timestamp = Date()

        folders[index].trashedAt = timestamp
        folders[index].updatedAt = timestamp
        let updatedFolder = folders[index]

        if selectedFolderId == folder.id {
            selectedFolderId = nil
        }
        expandedFolderIds.remove(folder.id)
        persistedExpandedFolderIDs = expandedFolderIds

        do {
            try await LocalDatabase.shared.saveFolder(updatedFolder)
        } catch {
            #if DEBUG
            print("[Home] Failed to move folder to trash locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else {
            let childNotebooks = notebooks.filter { $0.folderId == folder.id && $0.trashedAt == nil }
            for child in childNotebooks {
                await moveNotebookToTrash(child)
            }
            return
        }

        do {
            let canSync = await canSyncToCloud(userId: updatedFolder.userId)
            guard canSync else { return }
            try await service.moveFolderToTrash(id: updatedFolder.id, trashedAt: timestamp)
        } catch {
            #if DEBUG
            print("[Home] Failed to move folder to trash remotely, SyncEngine will retry: \(error)")
            #endif
        }

        let childNotebooks = notebooks.filter { $0.folderId == folder.id && $0.trashedAt == nil }
        for child in childNotebooks {
            await moveNotebookToTrash(child)
        }
    }

    func restoreFolder(_ folder: Folder) async {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].trashedAt = nil
        folders[index].updatedAt = Date()
        let updatedFolder = folders[index]

        do {
            try await LocalDatabase.shared.saveFolder(updatedFolder)
        } catch {
            #if DEBUG
            print("[Home] Failed to restore folder locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else {
            let childNotebooks = notebooks.filter { $0.folderId == folder.id && $0.trashedAt != nil }
            for child in childNotebooks {
                await restoreNotebook(child)
            }
            return
        }

        do {
            let canSync = await canSyncToCloud(userId: updatedFolder.userId)
            guard canSync else { return }
            try await service.restoreFolder(id: updatedFolder.id)
        } catch {
            #if DEBUG
            print("[Home] Failed to restore folder remotely, SyncEngine will retry: \(error)")
            #endif
        }

        let childNotebooks = notebooks.filter { $0.folderId == folder.id && $0.trashedAt != nil }
        for child in childNotebooks {
            await restoreNotebook(child)
        }
    }

    func permanentlyDeleteFolder(_ folder: Folder) async {
        let childNotebooks = notebooks.filter { $0.folderId == folder.id }
        for child in childNotebooks {
            await permanentlyDeleteNotebook(child)
        }

        folders.removeAll { $0.id == folder.id }

        do {
            try await LocalDatabase.shared.deleteFolder(id: folder.id, syncStatus: .pending)
        } catch {
            #if DEBUG
            print("[Home] Failed to delete folder locally: \(error)")
            #endif
        }

        guard Configuration.cloudSyncEnabled else {
            _ = await refreshStorageUsage(userId: folder.userId)
            return
        }

        let canSync = await refreshStorageUsage(userId: folder.userId).canSyncToCloud
        do {
            guard canSync else { return }
            try await service.deleteFolder(id: folder.id)
            try? await LocalDatabase.shared.markSynced(table: "folder", id: folder.id.uuidString)
        } catch {
            #if DEBUG
            print("[Home] Failed to permanently delete folder remotely: \(error)")
            #endif
        }
    }

    private func cleanupExpiredTrash() async {
        let cutoff = Date().addingTimeInterval(-trashRetentionInterval)

        let expiredFolders = trashedFolders.filter { ($0.trashedAt ?? .distantFuture) < cutoff }
        for folder in expiredFolders {
            await permanentlyDeleteFolder(folder)
        }

        let expiredFolderIDs = Set(expiredFolders.map(\.id))
        let expiredNotebooks = trashedNotebooks.filter { notebook in
            !expiredFolderIDs.contains(notebook.folderId ?? UUID()) &&
            (notebook.trashedAt ?? .distantFuture) < cutoff
        }
        for notebook in expiredNotebooks {
            await permanentlyDeleteNotebook(notebook)
        }
    }

    @discardableResult
    private func refreshStorageUsage(userId: UUID) async -> CloudStorageQuotaStatus {
        let status = await quotaService.status(for: userId)
        storageUsage = StorageUsage(status: status)
        do {
            let snapshots = try await LocalDatabase.shared.notebookStorageBreakdown(userId: userId)
            storageBreakdown = snapshots
                .filter { $0.notebook.trashedAt == nil }
                .map { snapshot in
                    let syncState: NotebookCloudSyncState
                    if snapshot.hasPendingSync {
                        syncState = status.canSyncToCloud ? .pending : .localOnly
                    } else if snapshot.lastSyncedAt != nil {
                        syncState = .synced
                    } else {
                        syncState = .neverSynced
                    }

                    return NotebookStorageBreakdownItem(
                        notebook: snapshot.notebook,
                        usedBytes: snapshot.usedBytes,
                        limitBytes: status.limitBytes,
                        percentOfQuota: status.limitBytes > 0
                            ? min(max(Double(snapshot.usedBytes) / Double(status.limitBytes), 0), 1)
                            : 0,
                        syncState: syncState,
                        pendingChangeCount: snapshot.pendingChangeCount,
                        lastSyncedAt: snapshot.lastSyncedAt
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.usedBytes == rhs.usedBytes {
                        return lhs.notebook.updatedAt > rhs.notebook.updatedAt
                    }
                    return lhs.usedBytes > rhs.usedBytes
                }
        } catch is CancellationError {
            // Expected when a new refresh supersedes the old one.
        } catch {
            #if DEBUG
            print("[Home] Failed to calculate storage breakdown: \(error)")
            #endif
        }
        return status
    }

    func refreshQuotaStatus(userId: UUID) async {
        _ = await refreshStorageUsage(userId: userId)
    }

    func refreshSyncSurface(userId: UUID?) async {
        guard let userId else {
            storageUsage = StorageUsage()
            storageBreakdown = []
            return
        }
        _ = await refreshStorageUsage(userId: userId)
    }

    private func canSyncToCloud(userId: UUID, showLocalOnlyNotice: Bool = false) async -> Bool {
        let status = await refreshStorageUsage(userId: userId)
        if !status.canSyncToCloud, showLocalOnlyNotice {
            quotaNoticeMessage = CloudStorageQuotaStatus.localOnlyWriteMessage
        }
        return status.canSyncToCloud
    }

}
