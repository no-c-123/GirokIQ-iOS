import Foundation
import Combine
import PencilKit

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

    enum SyncState: Equatable, Sendable {
        case idle
        case syncing
        case error(String)
    }

    @MainActor @Published private(set) var state: SyncState = .idle
    @MainActor @Published private(set) var pendingCount: Int = 0

    private let local: LocalDatabase
    private let remote: SupabaseService
    private var syncTask: Task<Void, Never>?

    init(local: LocalDatabase, remote: SupabaseService) {
        self.local = local
        self.remote = remote
    }

    convenience init() {
        self.init(local: .shared, remote: .shared)
    }

    // MARK: - Public API

    /// Pull all user data from Supabase into local DB (used after sign-in).
    /// Runs network + DB work on background threads.
    ///
    /// Includes web stroke fallback: if a page has no `drawing_data` but the
    /// `strokes_web` table has entries, converts them to PKDrawing and saves
    /// the resulting binary data locally.
    func pullAll(userId: UUID) async {
        await MainActor.run { state = .syncing }
        do {
            let notebooks = try await remote.fetchNotebooks(userId: userId)
            for notebook in notebooks {
                try await local.saveNotebook(notebook, syncStatus: .synced)

                // Pull pages for each notebook and apply web stroke fallback
                let pages = try await remote.fetchPages(notebookId: notebook.id)
                for page in pages {
                    try await local.savePage(page, syncStatus: .synced)
                    
                    let hasDrawingData = page.settings?.drawingData != nil
                    if hasDrawingData, let base64 = page.settings?.drawingData,
                       let data = Data(base64Encoded: base64) {
                        // Page has native PKDrawing data — save directly
                        try await local.savePageDrawing(data, pageId: page.id, syncStatus: .synced)
                    } else {
                        // Web stroke fallback: convert strokes_web → PKDrawing
                        let webStrokes = try await remote.fetchWebStrokes(pageId: page.id)
                        if !webStrokes.isEmpty {
                            let drawing = PencilKitBridge.convertWebStrokes(webStrokes)
                            let data = PencilKitBridge.serialize(drawing)
                            try await local.savePageDrawing(data, pageId: page.id, syncStatus: .synced)
                        }
                    }
                }
            }
            await MainActor.run { state = .idle }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run { state = .error(msg) }
        }
    }

    /// Push all pending local changes to Supabase.
    /// Runs on a background thread — never blocks the main thread.
    func pushPending() async {
        await MainActor.run { state = .syncing }
        do {
            let changes = try await local.pendingChanges()
            await MainActor.run { pendingCount = changes.count }

            for change in changes {
                // TODO: Read the full record from local DB, push to Supabase
                // On success:
                try await local.markSynced(table: change.table, id: change.id)
                await MainActor.run { pendingCount -= 1 }
            }
            await MainActor.run { state = .idle }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run { state = .error(msg) }
        }
    }

    /// Start background observation loop for auto-sync.
    /// Uses `.background` priority to avoid competing with UI work.
    @MainActor
    func startAutoSync() {
        syncTask?.cancel()
        syncTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pushPending()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @MainActor
    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
    }
}
