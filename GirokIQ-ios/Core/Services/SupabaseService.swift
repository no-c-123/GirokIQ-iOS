import Foundation
import Supabase
import Realtime

// MARK: - Supabase Client

let supabase = SupabaseClient(
    supabaseURL: Configuration.supabaseURL,
    supabaseKey: Configuration.supabaseAnonKey,
    options: SupabaseClientOptions(
        // Opt into the upcoming default (supabase-swift PR #822): the locally stored
        // session is emitted immediately as the initial session, regardless of validity.
        // Callers must therefore guard on `session.isExpired` (see AuthViewModel).
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Supabase Service

final class SupabaseService {
    static let shared = SupabaseService()
    private init() {}

    private struct TrashStatePayload: Encodable {
        let trashedAt: Date?

        enum CodingKeys: String, CodingKey {
            case trashedAt = "trashed_at"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let trashedAt {
                try container.encode(trashedAt, forKey: .trashedAt)
            } else {
                try container.encodeNil(forKey: .trashedAt)
            }
        }
    }

    // MARK: - Notebooks

    func fetchNotebooks(userId: UUID) async throws -> [Notebook] {
        try await supabase.from("notebooks")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func createNotebook(_ notebook: Notebook) async throws -> Notebook {
        try await supabase.from("notebooks")
            .insert(notebook)
            .select()
            .single()
            .execute()
            .value
    }

    func upsertNotebook(_ notebook: Notebook) async throws {
        try await supabase.from("notebooks")
            .upsert(notebook)
            .execute()
    }

    func updateNotebook(_ notebook: Notebook) async throws {
        try await supabase.from("notebooks")
            .update(notebook)
            .eq("id", value: notebook.id.uuidString)
            .execute()
    }

    func deleteNotebook(id: UUID) async throws {
        try await supabase.from("notebooks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func moveNotebookToTrash(id: UUID, trashedAt: Date) async throws {
        try await supabase.from("notebooks")
            .update(TrashStatePayload(trashedAt: trashedAt))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func restoreNotebook(id: UUID) async throws {
        try await supabase.from("notebooks")
            .update(TrashStatePayload(trashedAt: nil))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func fetchExpiredNotebookIDs(userId: UUID, before date: Date) async throws -> [UUID] {
        struct NotebookIDRow: Decodable {
            let id: UUID
        }

        let rows: [NotebookIDRow] = try await supabase.from("notebooks")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .lt("trashed_at", value: ISO8601DateFormatter().string(from: date))
            .execute()
            .value

        return rows.map(\.id)
    }

    // MARK: - Folders

    func fetchFolders(userId: UUID) async throws -> [Folder] {
        try await supabase.from("folders")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createFolder(_ folder: Folder) async throws -> Folder {
        try await supabase.from("folders")
            .insert(folder)
            .select()
            .single()
            .execute()
            .value
    }

    func upsertFolder(_ folder: Folder) async throws {
        try await supabase.from("folders")
            .upsert(folder)
            .execute()
    }

    func updateFolder(_ folder: Folder) async throws {
        try await supabase.from("folders")
            .update(folder)
            .eq("id", value: folder.id.uuidString)
            .execute()
    }

    func deleteFolder(id: UUID) async throws {
        try await supabase.from("folders")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func moveFolderToTrash(id: UUID, trashedAt: Date) async throws {
        try await supabase.from("folders")
            .update(TrashStatePayload(trashedAt: trashedAt))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func restoreFolder(id: UUID) async throws {
        try await supabase.from("folders")
            .update(TrashStatePayload(trashedAt: nil))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func fetchExpiredFolderIDs(userId: UUID, before date: Date) async throws -> [UUID] {
        struct FolderIDRow: Decodable {
            let id: UUID
        }

        let rows: [FolderIDRow] = try await supabase.from("folders")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .lt("trashed_at", value: ISO8601DateFormatter().string(from: date))
            .execute()
            .value

        return rows.map(\.id)
    }

    // MARK: - Pages

    func fetchPages(notebookId: UUID) async throws -> [Page] {
        try await supabase.from("pages")
            .select()
            .eq("notebook_id", value: notebookId.uuidString)
            .order("page_index", ascending: true)
            .execute()
            .value
    }

    func fetchPage(id: UUID) async throws -> Page {
        try await supabase.from("pages")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func createPage(_ page: Page) async throws -> Page {
        try await supabase.from("pages")
            .insert(page)
            .select()
            .single()
            .execute()
            .value
    }

    func upsertPage(_ page: Page) async throws {
        try await supabase.from("pages")
            .upsert(page)
            .execute()
    }

    func updatePage(_ page: Page) async throws {
        try await supabase.from("pages")
            .update(page)
            .eq("id", value: page.id.uuidString)
            .execute()
    }

    func deletePage(id: UUID) async throws {
        try await supabase.from("pages")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Canvas Elements

    func fetchCanvasElements(pageId: UUID) async throws -> [CanvasElement] {
        try await supabase.from("canvas_elements")
            .select()
            .eq("page_id", value: pageId.uuidString)
            .order("z_index", ascending: true)
            .execute()
            .value
    }

    func upsertCanvasElement(_ element: CanvasElement) async throws {
        try await supabase.from("canvas_elements")
            .upsert(element)
            .execute()
    }

    // MARK: - Canvas Images

    func uploadCanvasImage(data: Data, path: String, contentType: String = "image/jpeg") async throws {
        try await supabase.storage
            .from("canvas-images")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: contentType, upsert: true)
            )
    }

    func downloadCanvasImage(path: String) async throws -> Data {
        try await supabase.storage
            .from("canvas-images")
            .download(path: path)
    }

    // MARK: - Chats

    func fetchChats(userId: UUID) async throws -> [Chat] {
        try await supabase.from("chats")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func createChat(_ chat: Chat) async throws -> Chat {
        try await supabase.from("chats")
            .insert(chat)
            .select()
            .single()
            .execute()
            .value
    }

    func upsertChat(_ chat: Chat) async throws {
        try await supabase.from("chats")
            .upsert(chat)
            .execute()
    }

    func deleteChat(id: UUID) async throws {
        try await supabase.from("messages")
            .delete()
            .eq("chat_id", value: id.uuidString)
            .execute()

        try await supabase.from("chats")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Messages

    func fetchMessages(chatId: UUID) async throws -> [Message] {
        try await supabase.from("messages")
            .select()
            .eq("chat_id", value: chatId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func insertMessage(_ message: Message) async throws -> Message {
        try await supabase.from("messages")
            .insert(message)
            .select()
            .single()
            .execute()
            .value
    }

    func upsertMessage(_ message: Message) async throws {
        try await supabase.from("messages")
            .upsert(message)
            .execute()
    }

    func deleteMessage(id: UUID) async throws {
        try await supabase.from("messages")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Presence

    /// Join a Supabase Realtime presence channel for a notebook.
    /// Returns the channel so the caller can track and remove it later.
    func joinNotebookPresence(
        notebookId: UUID,
        userId: UUID,
        platform: String = "ios",
        onPresenceChange: @escaping @Sendable (_ webUsers: [PresenceEntry]) -> Void
    ) -> RealtimeChannelV2 {
        let channel = supabase.realtimeV2.channel("notebook:\(notebookId.uuidString)")

        // Track accumulated web presence state across join/leave events
        let webUsersActor = WebPresenceActor()

        // Subscribe to presence sync events via callback
        _ = channel.onPresenceChange { action in
            let joins = action.joins
            let leaves = action.leaves

            Task {
                // Add joining web users
                for (_, presence) in joins {
                    let state = presence.state
                    if let userIdStr = state["user_id"]?.stringValue,
                       let platformStr = state["platform"]?.stringValue,
                       platformStr == "web",
                       let uid = UUID(uuidString: userIdStr) {
                        await webUsersActor.add(PresenceEntry(userId: uid, platform: platformStr))
                    }
                }

                // Remove leaving web users
                for (_, presence) in leaves {
                    let state = presence.state
                    if let userIdStr = state["user_id"]?.stringValue,
                       let uid = UUID(uuidString: userIdStr) {
                        await webUsersActor.remove(uid)
                    }
                }

                let current = await webUsersActor.entries
                onPresenceChange(current)
            }
        }

        Task {
            do {
                try await channel.subscribeWithError()
                try await trackPresenceWithRetry(
                    on: channel,
                    state: ["user_id": userId.uuidString, "platform": platform]
                )
            } catch {
                #if DEBUG
                print("[Presence] Failed to join notebook presence: \(error)")
                #endif
            }
        }

        return channel
    }

    /// Leave a notebook presence channel.
    func leaveNotebookPresence(_ channel: RealtimeChannelV2) async {
        await supabase.realtimeV2.removeChannel(channel)
    }

    private func trackPresenceWithRetry(
        on channel: RealtimeChannelV2,
        state: [String: String],
        attempts: Int = 5
    ) async throws {
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                try await channel.track(state)
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }

        if let lastError {
            throw lastError
        }
    }

    // MARK: - App State

    func fetchAppState(userId: UUID) async throws -> AppState? {
        try await supabase.from("app_state")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
    }

    func upsertAppState(_ state: AppState) async throws {
        try await supabase.from("app_state")
            .upsert(state)
            .execute()
    }
}

// MARK: - Presence Entry

struct PresenceEntry: Identifiable, Sendable {
    let userId: UUID
    let platform: String

    var id: UUID { userId }
}

// MARK: - Web Presence Actor

/// Thread-safe accumulator for presence state across join/leave events.
actor WebPresenceActor {
    private(set) var entries: [PresenceEntry] = []

    func add(_ entry: PresenceEntry) {
        if !entries.contains(where: { $0.userId == entry.userId }) {
            entries.append(entry)
        }
    }

    func remove(_ userId: UUID) {
        entries.removeAll { $0.userId == userId }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid credentials. Please try again."
        case .notFound: return "Resource not found."
        case .serverError(let msg): return msg
        }
    }
}
