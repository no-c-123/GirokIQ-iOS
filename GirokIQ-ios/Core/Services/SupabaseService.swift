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

    // MARK: - Pages

    func fetchPages(notebookId: UUID) async throws -> [Page] {
        try await supabase.from("pages")
            .select()
            .eq("notebook_id", value: notebookId.uuidString)
            .order("page_index", ascending: true)
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

    // MARK: - Strokes

    func fetchStrokes(pageId: UUID) async throws -> [RemoteStroke] {
        try await supabase.from("strokes")
            .select()
            .eq("page_id", value: pageId.uuidString)
            .eq("deleted", value: false)
            .execute()
            .value
    }

    func upsertStrokes(_ strokes: [RemoteStroke]) async throws {
        try await supabase.from("strokes")
            .upsert(strokes)
            .execute()
    }

    func softDeleteStroke(id: UUID) async throws {
        struct DeletePayload: Encodable {
            let deleted = true
        }
        try await supabase.from("strokes")
            .update(DeletePayload())
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

    // MARK: - Web Strokes

    /// Fetch web-format strokes for a page from the `strokes_web` table.
    /// Used as fallback when a page has no PKDrawing `drawing_data`.
    func fetchWebStrokes(pageId: UUID) async throws -> [WebStroke] {
        try await supabase.from("strokes_web")
            .select()
            .eq("page_id", value: pageId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
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
            try await channel.subscribeWithError()

            // Track this device in the presence channel
            try? await channel.track(["user_id": userId.uuidString, "platform": platform])
        }

        return channel
    }

    /// Leave a notebook presence channel.
    func leaveNotebookPresence(_ channel: RealtimeChannelV2) async {
        await supabase.realtimeV2.removeChannel(channel)
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
