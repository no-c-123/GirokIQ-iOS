import Foundation
import Supabase

// MARK: - Supabase Client

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://bapqxqydqzopbpjrpnna.supabase.co")!,
    supabaseKey: "sb_publishable_423Dnw91Y5cLpTMC7wCuMA_3cAuqY-t"
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
