import Foundation
import GRDB

// MARK: - Sync Status

enum SyncStatus: String, Codable {
    case pending
    case synced
    case conflict
}

// MARK: - Local Database

/// Offline-first persistence layer using GRDB (SQLite).
/// All writes go here first for instant UI response, then SyncEngine pushes to Supabase.
final class LocalDatabase {
    static let shared = LocalDatabase()

    private let dbQueue: DatabaseQueue

    private init() {
        let path = try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("girokiq.sqlite")
            .path
        dbQueue = try! DatabaseQueue(path: path)
        try! migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "notebook") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("user_id", .text).notNull()
                t.column("folder_id", .text)
                t.column("name", .text).notNull().defaults(to: "Untitled")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "folder") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("user_id", .text).notNull()
                t.column("parent_id", .text)
                t.column("name", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "page") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("user_id", .text).notNull()
                t.column("notebook_id", .text).notNull().references("notebook", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "Page")
                t.column("page_index", .integer).notNull().defaults(to: 0)
                t.column("type", .text).notNull().defaults(to: "canvas")
                t.column("settings", .text) // JSON string
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            
            // Separate table for drawing binary blobs to keep 'page' table fast
            try db.create(table: "page_drawing") { t in
                t.column("page_id", .text).notNull().primaryKey()
                t.column("drawing_data", .blob).notNull()
            }
            
            try db.create(table: "sync_change") { t in
                t.column("id", .text).notNull()
                t.column("table", .text).notNull()
                t.column("status", .text).notNull()
                t.primaryKey(["id", "table"])
            }
        }

        return migrator
    }

    // MARK: - Notebooks

    func fetchNotebooks(userId: UUID) async throws -> [Notebook] {
        try await dbQueue.read { db in
            try Notebook.filter(Column("user_id") == userId.uuidString)
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    func saveNotebook(_ notebook: Notebook, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try notebook.save(db)
            try self.recordSyncChange(db: db, table: "notebook", id: notebook.id.uuidString, status: syncStatus)
        }
    }

    func saveFolder(_ folder: Folder, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try folder.save(db)
            try self.recordSyncChange(db: db, table: "folder", id: folder.id.uuidString, status: syncStatus)
        }
    }

    // MARK: - Pages

    func fetchPages(notebookId: UUID) async throws -> [(page: Page, drawingData: Data?)] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.*, pd.drawing_data 
                FROM page p 
                LEFT JOIN page_drawing pd ON p.id = pd.page_id 
                WHERE p.notebook_id = ?
                ORDER BY p.page_index ASC
                """, arguments: [notebookId.uuidString])
            
            return try rows.map { row in
                let page = try Page(row: row)
                let data: Data? = row["drawing_data"]
                return (page, data)
            }
        }
    }

    func savePage(_ page: Page, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try page.save(db)
            try self.recordSyncChange(db: db, table: "page", id: page.id.uuidString, status: syncStatus)
        }
    }

    func savePageDrawing(_ drawingData: Data, pageId: UUID, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO page_drawing (page_id, drawing_data) 
                VALUES (?, ?) 
                ON CONFLICT(page_id) DO UPDATE SET drawing_data = excluded.drawing_data
                """, arguments: [pageId.uuidString, drawingData])
            try self.recordSyncChange(db: db, table: "page", id: pageId.uuidString, status: syncStatus)
        }
    }

    func saveDrawingData(_ data: Data, forPageId pageId: UUID) async throws {
        try await savePageDrawing(data, pageId: pageId)
    }

    // MARK: - Pending Changes (for SyncEngine)

    nonisolated private func recordSyncChange(db: Database, table: String, id: String, status: SyncStatus) throws {
        try db.execute(sql: """
            INSERT INTO sync_change (id, "table", status) 
            VALUES (?, ?, ?) 
            ON CONFLICT(id, "table") DO UPDATE SET status = excluded.status
            """, arguments: [id, table, status.rawValue])
    }

    func pendingChanges() async throws -> [(table: String, id: String)] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, \"table\" FROM sync_change WHERE status = ?", arguments: [SyncStatus.pending.rawValue])
            return rows.map { (table: $0["table"], id: $0["id"]) }
        }
    }

    func markSynced(table: String, id: String) async throws {
        try await dbQueue.write { db in
            try self.recordSyncChange(db: db, table: table, id: id, status: .synced)
        }
    }
}

// MARK: - GRDB Conformances

extension Notebook: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notebook"
    
    nonisolated init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        userId = UUID(uuidString: row["user_id"]) ?? UUID()
        if let folderIdString: String = row["folder_id"] {
            folderId = UUID(uuidString: folderIdString)
        } else {
            folderId = nil
        }
        name = row["name"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }
    
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["folder_id"] = folderId?.uuidString
        container["name"] = name
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

extension Folder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder"
    
    nonisolated init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        userId = UUID(uuidString: row["user_id"]) ?? UUID()
        if let parentIdString: String = row["parent_id"] {
            parentId = UUID(uuidString: parentIdString)
        } else {
            parentId = nil
        }
        name = row["name"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }
    
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["parent_id"] = parentId?.uuidString
        container["name"] = name
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

extension Page: FetchableRecord, PersistableRecord {
    static let databaseTableName = "page"
    
    nonisolated init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        userId = UUID(uuidString: row["user_id"]) ?? UUID()
        notebookId = UUID(uuidString: row["notebook_id"]) ?? UUID()
        title = row["title"]
        pageIndex = row["page_index"]
        type = row["type"]
        settings = row["settings"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }
    
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["notebook_id"] = notebookId.uuidString
        container["title"] = title
        container["page_index"] = pageIndex
        container["type"] = type
        container["settings"] = settings
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

extension PageSettings: DatabaseValueConvertible {
    nonisolated public var databaseValue: DatabaseValue {
        if let data = try? JSONEncoder().encode(self),
           let string = String(data: data, encoding: .utf8) {
            return string.databaseValue
        }
        return .null
    }
    
    nonisolated public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> PageSettings? {
        if let string = String.fromDatabaseValue(dbValue),
           let data = string.data(using: .utf8),
           let settings = try? JSONDecoder().decode(PageSettings.self, from: data) {
            return settings
        }
        return nil
    }
}
