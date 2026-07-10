import Foundation
import Combine
import PencilKit

extension Notification.Name {
    static let syncEngineRequestPush = Notification.Name("girokiq.syncEngineRequestPush")
}

// MARK: - Sync Engine

/// Reconciles local GRDB database with remote Supabase.
/// Observes local changes and pushes them in the background.
///
/// ## Performance: Non-blocking sync
/// SyncEngine runs **off the main actor**. All network I/O and database queries
/// execute on background threads so they never block the UI. Published state
/// properties are updated on `@MainActor` to safely drive SwiftUI.
///
/// Flow:
///   User Action → ViewModel writes to LocalDatabase (instant) →
///   SyncEngine detects pending changes → pushes to Supabase →
///   On success: mark local record as synced
///   On conflict: last-write-wins for drawing data, merge for metadata
final class SyncEngine: ObservableObject {
    nonisolated private static let fullBackfillDefaultsKeyPrefix = "SyncEngine.fullBackfillEnqueued"

    enum SyncState: Equatable, Sendable {
        case idle
        case syncing
        case paused(String)
        case error(String)
    }

    @MainActor @Published private(set) var state: SyncState = .idle
    @MainActor @Published private(set) var pendingCount: Int = 0

    private let local: LocalDatabase
    private let remote: SupabaseService
    private let quota = CloudStorageQuotaService.shared
    private let network = NetworkMonitor.shared
    private var syncTask: Task<Void, Never>?
    private var requestPushTask: Task<Void, Never>?
    private var requestPushObserver: NSObjectProtocol?

    init(local: LocalDatabase, remote: SupabaseService) {
        self.local = local
        self.remote = remote
        self.requestPushObserver = NotificationCenter.default.addObserver(
            forName: .syncEngineRequestPush,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.requestPush()
        }
    }

    convenience init() {
        self.init(local: .shared, remote: .shared)
    }

    deinit {
        syncTask?.cancel()
        requestPushTask?.cancel()
        if let requestPushObserver {
            NotificationCenter.default.removeObserver(requestPushObserver)
        }
    }

    // MARK: - Public API

    nonisolated private static func fullBackfillDefaultsKey(for userId: UUID) -> String {
        fullBackfillDefaultsKeyPrefix + "." + userId.uuidString
    }

    @MainActor
    private func setStateIfNeeded(_ newState: SyncState) {
        if state != newState {
            state = newState
        }
    }

    @MainActor
    private func setPendingCountIfNeeded(_ newCount: Int) {
        if pendingCount != newCount {
            pendingCount = newCount
        }
    }

    /// Pull all user data from Supabase into local DB (used after sign-in).
    /// Runs network + DB work on background threads.
    func pullAll(userId: UUID) async {
        guard Configuration.cloudSyncEnabled else {
            await MainActor.run { self.setStateIfNeeded(.idle) }
            return
        }
        await MainActor.run { self.setStateIfNeeded(.syncing) }
        do {
            let notebooks = try await remote.fetchNotebooks(userId: userId)
            let folders = try await remote.fetchFolders(userId: userId)
            let chats = (try? await remote.fetchChats(userId: userId)) ?? []

            for folder in folders {
                try await local.saveFolder(folder, syncStatus: .synced)
            }

            for notebook in notebooks {
                try await local.saveNotebook(notebook, syncStatus: .synced)

                // Pull pages for each notebook and hydrate native page drawing blobs.
                let pages = try await remote.fetchPages(notebookId: notebook.id)
                for page in pages {
                    try await local.savePage(page, syncStatus: .synced)
                    // Pull elements from the dedicated table (more reliable than relying on page.settings)
                    if let remoteElements = try? await remote.fetchCanvasElements(pageId: page.id) {
                        try await local.saveCanvasElements(remoteElements, forPageId: page.id, syncStatus: .synced)
                    }
                    
                    if let base64 = page.settings?.drawingData,
                       let data = Data(base64Encoded: base64) {
                        // Page has native PKDrawing data — save directly
                        try await local.savePageDrawing(data, pageId: page.id, syncStatus: .synced)
                    }
                }
            }

            // Pull chats + messages (offline availability + history restore)
            for chat in chats {
                // Only persist chats that belong to the current user's notebooks (or global chats)
                try? await local.saveChat(chat, syncStatus: .synced)
                if let messages = try? await remote.fetchMessages(chatId: chat.id) {
                    for message in messages {
                        try? await local.saveMessage(message, syncStatus: .synced)
                    }
                }
            }
            await MainActor.run { self.setStateIfNeeded(.idle) }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run { self.setStateIfNeeded(.error(msg)) }
        }
    }

    /// Push all pending local changes to Supabase.
    /// Runs on a background thread — never blocks the main thread.
    func pushPending() async {
        if !shouldAttemptSyncNow() {
            await updatePendingCount()
            await MainActor.run { self.setStateIfNeeded(.idle) }
            return
        }

        do {
            let changes = try await local.pendingChanges()
            await MainActor.run { self.setPendingCountIfNeeded(changes.count) }

            guard !changes.isEmpty else {
                await MainActor.run { self.setStateIfNeeded(.idle) }
                return
            }

            await MainActor.run { self.setStateIfNeeded(.syncing) }

            if let blockedMessage = try await quotaPauseMessageIfNeeded(for: changes) {
                await MainActor.run { self.setStateIfNeeded(.paused(blockedMessage)) }
                return
            }

            for change in changes {
                let pushed = try await pushChange(table: change.table, id: change.id)
                if pushed {
                    try await local.markSynced(table: change.table, id: change.id)
                    await MainActor.run {
                        self.setPendingCountIfNeeded(max(0, self.pendingCount - 1))
                    }
                } else {
                    // Leave it pending so it retries later (do NOT lie).
                    await MainActor.run { self.setStateIfNeeded(.idle) }
                    return
                }
            }
            await MainActor.run { self.setStateIfNeeded(.idle) }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run { self.setStateIfNeeded(.error(msg)) }
        }
    }

    /// Enqueues one-time cloud backfill for local-only libraries when full sync is enabled.
    /// Returns true when any pending work exists after enqueueing.
    func enqueueInitialBackfillIfNeeded(userId: UUID) async -> Bool {
        guard Configuration.cloudSyncEnabled else { return false }

        let defaultsKey = Self.fullBackfillDefaultsKey(for: userId)
        do {
            if !UserDefaults.standard.bool(forKey: defaultsKey) {
                _ = try await local.enqueueFullCloudBackfill(userId: userId)
                UserDefaults.standard.set(true, forKey: defaultsKey)
            }
            _ = try await local.enqueuePagesMissingImageAssetPaths(userId: userId)
            let changes = try await local.pendingChanges()
            let pendingAfterEnqueue = changes.count
            await MainActor.run { self.setPendingCountIfNeeded(pendingAfterEnqueue) }
            return pendingAfterEnqueue > 0
        } catch {
            let msg = error.localizedDescription
            await MainActor.run { self.setStateIfNeeded(.error(msg)) }
            return false
        }
    }

    /// Developer/support recovery path for rerunning the one-time backfill after a remote reset.
    func forceReenqueueInitialBackfill(userId: UUID) async throws -> Int {
        guard Configuration.cloudSyncEnabled else { return 0 }

        let defaultsKey = Self.fullBackfillDefaultsKey(for: userId)
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        _ = try await local.enqueueFullCloudBackfill(userId: userId)
        _ = try await local.enqueuePagesMissingImageAssetPaths(userId: userId)
        let changes = try await local.pendingChanges()
        let pendingAfterEnqueue = changes.count
        UserDefaults.standard.set(true, forKey: defaultsKey)
        await MainActor.run { self.setPendingCountIfNeeded(pendingAfterEnqueue) }
        return pendingAfterEnqueue
    }

    func requestPush() {
        guard Configuration.cloudSyncEnabled else { return }
        guard Self.readAutoSyncEnabled() else { return }
        requestPushTask?.cancel()
        requestPushTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.pushPending()
        }
    }

    private func quotaPauseMessageIfNeeded(for changes: [(table: String, id: String)]) async throws -> String? {
        for change in changes {
            guard let userId = try await local.userIdForSyncChange(table: change.table, id: change.id) else {
                continue
            }
            let quotaStatus = await quota.status(for: userId)
            if !quotaStatus.canSyncToCloud {
                return CloudStorageQuotaStatus.syncPausedMessage
            }
        }
        return nil
    }

    /// Start background observation loop for auto-sync.
    /// Uses `.background` priority to avoid competing with UI work.
    func startAutoSync() {
        guard Configuration.cloudSyncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if Self.readAutoSyncEnabled() {
                    let pendingChanges = (try? await self.local.pendingChanges()) ?? []
                    await MainActor.run {
                        self.setPendingCountIfNeeded(pendingChanges.count)
                    }
                    if !pendingChanges.isEmpty {
                        await self.pushPending()
                    }
                } else {
                    await self.updatePendingCount()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
        requestPushTask?.cancel()
        requestPushTask = nil
    }

    private func remoteImageAssetPath(
        userId: UUID,
        notebookId: UUID,
        fileName: String
    ) -> String {
        "\(userId.uuidString)/\(notebookId.uuidString)/\(fileName)"
    }

    private func normalizedImageElements(
        for page: Page,
        elements: [CanvasElement]
    ) -> [CanvasElement] {
        elements.map { element in
            guard element.type == "image",
                  let fileName = element.content,
                  !fileName.isEmpty
            else {
                return element
            }

            var updatedElement = element
            var style = updatedElement.style ?? ElementStyle()
            if style.imageAssetPath?.isEmpty != false {
                style.imageAssetPath = remoteImageAssetPath(
                    userId: page.userId,
                    notebookId: page.notebookId,
                    fileName: fileName
                )
                updatedElement.style = style
            }
            return updatedElement
        }
    }

    private func pushChange(table: String, id: String) async throws -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }

        switch table {
        case "notebook":
            if let notebook = try await local.fetchNotebook(id: uuid) {
                // Conflict safety: never overwrite newer remote data with older local data.
                if let remoteVersion = try? await remote.fetchNotebooks(userId: notebook.userId).first(where: { $0.id == uuid }),
                   remoteVersion.updatedAt > notebook.updatedAt {
                    try await local.saveNotebook(remoteVersion, syncStatus: .synced)
                    return true
                }
                try await remote.upsertNotebook(notebook)
                return true
            } else {
                // Local row missing but sync_change exists => treat as deletion.
                try await remote.deleteNotebook(id: uuid)
                return true
            }

        case "folder":
            if let folder = try await local.fetchFolder(id: uuid) {
                if let remoteVersion = try? await remote.fetchFolders(userId: folder.userId).first(where: { $0.id == uuid }),
                   remoteVersion.updatedAt > folder.updatedAt {
                    try await local.saveFolder(remoteVersion, syncStatus: .synced)
                    return true
                }
                try await remote.upsertFolder(folder)
                return true
            } else {
                try await remote.deleteFolder(id: uuid)
                return true
            }

        case "page":
            if let tuple = try await local.fetchPage(id: uuid) {
                var page = tuple.page
                var settings = page.settings ?? PageSettings()
                let normalizedElements = normalizedImageElements(for: page, elements: settings.elements ?? [])
                if normalizedElements != (settings.elements ?? []) {
                    settings.elements = normalizedElements
                    try await local.saveCanvasElements(normalizedElements, forPageId: page.id, syncStatus: .pending)
                    page = (try await local.fetchPage(id: uuid))?.page ?? page
                } else {
                    settings.elements = normalizedElements
                }
                settings.drawingData = tuple.drawingData?.base64EncodedString()
                page.settings = settings

                if let remotePage = try? await remote.fetchPage(id: uuid),
                   remotePage.updatedAt > page.updatedAt {
                    // Remote wins (last-write-wins) — pull it locally to avoid blind overwrite.
                    try await local.savePage(remotePage, syncStatus: .synced)
                    if let base64 = remotePage.settings?.drawingData,
                       let data = Data(base64Encoded: base64) {
                        try await local.savePageDrawing(data, pageId: remotePage.id, syncStatus: .synced)
                    }
                    if let remoteElements = try? await remote.fetchCanvasElements(pageId: remotePage.id) {
                        try await local.saveCanvasElements(remoteElements, forPageId: remotePage.id, syncStatus: .synced)
                    }
                    return true
                }

                // Push local version
                try await remote.upsertPage(page)
                for element in normalizedElements {
                    if element.type == "image",
                       let fileName = element.content,
                       !fileName.isEmpty,
                       let remotePath = element.style?.imageAssetPath {
                        let localImageURL = NotebookTransferSupport.localImageURL(for: fileName)
                        if let imageData = try? Data(contentsOf: localImageURL) {
                            try? await remote.uploadCanvasImage(
                                data: imageData,
                                path: remotePath,
                                contentType: NotebookTransferSupport.mimeType(for: fileName)
                            )
                        }
                    }

                    try? await remote.upsertCanvasElement(element)
                }
                return true
            } else {
                try await remote.deletePage(id: uuid)
                return true
            }

        case "chat":
            if let chat = try await local.fetchChat(id: uuid) {
                try await remote.upsertChat(chat)
                return true
            } else {
                try await remote.deleteChat(id: uuid)
                return true
            }

        case "message":
            if let message = try await local.fetchMessage(id: uuid) {
                try await remote.upsertMessage(message)
                return true
            } else {
                try await remote.deleteMessage(id: uuid)
                return true
            }

        default:
            return false
        }
    }

    private func shouldAttemptSyncNow() -> Bool {
        guard network.isConnected else { return false }
        if Self.readSyncWiFiOnlyEnabled() {
            return network.isOnWiFi
        }
        return true
    }

    nonisolated private static func readAutoSyncEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true
    }

    nonisolated private static func readSyncWiFiOnlyEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "syncOnWiFiOnly") as? Bool ?? false
    }

    private func updatePendingCount() async {
        do {
            let changes = try await local.pendingChanges()
            await MainActor.run { self.setPendingCountIfNeeded(changes.count) }
        } catch {
            // ignore
        }
    }
}
