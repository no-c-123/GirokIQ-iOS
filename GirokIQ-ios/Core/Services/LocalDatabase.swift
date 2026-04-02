import Foundation
// import GRDB  // Uncomment after adding GRDB.swift via File → Add Package Dependencies

// MARK: - Sync Status

enum SyncStatus: String, Codable {
    case pending
    case synced
    case conflict
}

// MARK: - Local Database

/// Offline-first persistence layer using GRDB (SQLite).
/// All writes go here first for instant UI response, then SyncEngine pushes to Supabase.
///
/// ## Setup
/// Add GRDB.swift via SPM: https://github.com/groue/GRDB.swift
/// Then uncomment the GRDB import and implementation below.
final class LocalDatabase {
    static let shared = LocalDatabase()

    // private let dbQueue: DatabaseQueue  // Uncomment with GRDB

    private init() {
        // TODO: Initialize GRDB DatabaseQueue
        // let path = try! FileManager.default
        //     .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        //     .appendingPathComponent("girokiq.sqlite")
        //     .path
        // dbQueue = try! DatabaseQueue(path: path)
        // try! migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    // private var migrator: DatabaseMigrator {
    //     var migrator = DatabaseMigrator()
    //
    //     migrator.registerMigration("v1") { db in
    //         try db.create(table: "notebook") { t in
    //             t.column("id", .text).notNull().primaryKey()
    //             t.column("userId", .text).notNull()
    //             t.column("title", .text).notNull()
    //             t.column("emoji", .text).notNull().defaults(to: "📓")
    //             t.column("coverColor", .text).notNull().defaults(to: "#6366F1")
    //             t.column("pageCount", .integer).notNull().defaults(to: 1)
    //             t.column("folderId", .text)
    //             t.column("syncStatus", .text).notNull().defaults(to: SyncStatus.pending.rawValue)
    //             t.column("createdAt", .datetime).notNull()
    //             t.column("updatedAt", .datetime).notNull()
    //         }
    //
    //         try db.create(table: "page") { t in
    //             t.column("id", .text).notNull().primaryKey()
    //             t.column("notebookId", .text).notNull()
    //                 .references("notebook", onDelete: .cascade)
    //             t.column("title", .text).notNull().defaults(to: "Page")
    //             t.column("drawingData", .blob)  // PKDrawing dataRepresentation
    //             t.column("backgroundPattern", .text).notNull().defaults(to: "grid")
    //             t.column("pageOrder", .integer).notNull().defaults(to: 0)
    //             t.column("syncStatus", .text).notNull().defaults(to: SyncStatus.pending.rawValue)
    //             t.column("updatedAt", .datetime).notNull()
    //         }
    //
    //         try db.create(table: "folder") { t in
    //             t.column("id", .text).notNull().primaryKey()
    //             t.column("userId", .text).notNull()
    //             t.column("title", .text).notNull()
    //             t.column("emoji", .text)
    //             t.column("syncStatus", .text).notNull().defaults(to: SyncStatus.pending.rawValue)
    //             t.column("createdAt", .datetime).notNull()
    //         }
    //     }
    //
    //     return migrator
    // }

    // MARK: - Notebooks

    func fetchNotebooks(userId: UUID) async throws -> [Notebook] {
        // TODO: Implement with GRDB
        // try await dbQueue.read { db in
        //     try Notebook.filter(Column("userId") == userId)
        //         .order(Column("updatedAt").desc)
        //         .fetchAll(db)
        // }
        return []
    }

    func saveNotebook(_ notebook: Notebook) async throws {
        // TODO: Implement with GRDB
        // try await dbQueue.write { db in
        //     try notebook.save(db)
        // }
    }

    // MARK: - Pages

    func fetchPages(notebookId: UUID) async throws -> [Data] {
        // TODO: Returns PKDrawing data blobs
        return []
    }

    func savePageDrawing(_ drawingData: Data, pageId: UUID) async throws {
        // TODO: Implement with GRDB
    }

    func saveDrawingData(_ data: Data, forPageId pageId: UUID) async throws {
        try await savePageDrawing(data, pageId: pageId)
    }

    // MARK: - Pending Changes (for SyncEngine)

    func pendingChanges() async throws -> [(table: String, id: String)] {
        // TODO: Query all records with syncStatus == .pending
        return []
    }

    func markSynced(table: String, id: String) async throws {
        // TODO: Update syncStatus to .synced
    }
}
