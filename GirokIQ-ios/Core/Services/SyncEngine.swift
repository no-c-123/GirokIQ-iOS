import Foundation
import Combine

// MARK: - Sync Engine

/// Reconciles local GRDB database with remote Supabase.
/// Observes local changes and pushes them in the background.
///
/// Flow:
///   User Action → ViewModel writes to LocalDatabase (instant) →
///   SyncEngine detects pending changes → pushes to Supabase →
///   On success: mark local record as synced
///   On conflict: last-write-wins for drawing data, merge for metadata
@MainActor
final class SyncEngine: ObservableObject {

    enum SyncState: Equatable {
        case idle
        case syncing
        case error(String)
    }

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var pendingCount: Int = 0

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

    /// Pull all user data from Supabase into local DB (used after sign-in)
    func pullAll(userId: UUID) async {
        state = .syncing
        do {
            let notebooks = try await remote.fetchNotebooks(userId: userId)
            for notebook in notebooks {
                try await local.saveNotebook(notebook)
            }
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Push all pending local changes to Supabase
    func pushPending() async {
        state = .syncing
        do {
            let changes = try await local.pendingChanges()
            pendingCount = changes.count

            for change in changes {
                // TODO: Read the full record from local DB, push to Supabase
                // On success:
                try await local.markSynced(table: change.table, id: change.id)
                pendingCount -= 1
            }
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Start background observation loop for auto-sync
    func startAutoSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pushPending()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
    }
}
