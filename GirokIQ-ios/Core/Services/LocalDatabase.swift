import Foundation
import GRDB

// MARK: - Sync Status

enum SyncStatus: String, Codable {
    case pending
    case synced
    case conflict
}

struct NotebookStorageBreakdownSnapshot: Sendable {
    let notebook: Notebook
    let drawingBytes: Int64
    let imageBytes: Int64
    let otherBytes: Int64
    let pendingChangeCount: Int
    let lastSyncedAt: Date?

    var usedBytes: Int64 { drawingBytes + imageBytes + otherBytes }
    var hasPendingSync: Bool { pendingChangeCount > 0 }
}

struct DeviceStorageSnapshot: Sendable, Equatable {
    let databaseBytes: Int64
    let drawingBytes: Int64
    let imageBytes: Int64
    let reclaimableImageBytes: Int64

    var totalBytes: Int64 { databaseBytes + drawingBytes + imageBytes }
}

// MARK: - Local Database

/// Offline-first persistence layer using GRDB (SQLite).
/// All writes go here first for instant UI response, then SyncEngine pushes to Supabase.
final class LocalDatabase: Sendable {
    static let shared = LocalDatabase()

    private let dbQueue: DatabaseQueue
    nonisolated private static let drawingsDirectoryName = "Drawings"
    nonisolated private static let didRunVacuumKey = "LocalDatabase.didRunDrawingVacuum.v1"
    nonisolated private static let lastCanvasMaintenanceKey = "LocalDatabase.lastCanvasMaintenanceAt"

    private init() {
        do {
            let path = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("girokiq.sqlite")
                .path
            let queue = try DatabaseQueue(path: path)
            try Self.migrator.migrate(queue)
            dbQueue = queue
            configureVacuumIfNeeded(queue)
            scheduleCanvasAssetMaintenanceIfNeeded()
            #if DEBUG
            print("[LocalDatabase] Opened successfully at \(path)")
            #endif
        } catch {
            #if DEBUG
            print("[LocalDatabase] CRITICAL: Failed to open or migrate database: \(error)")
            print("[LocalDatabase] Falling back to in-memory database. Data will not persist this session.")
            #endif
            // In-memory DatabaseQueue cannot fail to open
            let fallback = try! DatabaseQueue()
            // Migrations must run so table schema exists for subsequent queries
            try? Self.migrator.migrate(fallback)
            dbQueue = fallback
        }
    }

    nonisolated private static func drawingsDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let drawingsURL = baseURL.appendingPathComponent(drawingsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: drawingsURL.path) {
            try FileManager.default.createDirectory(
                at: drawingsURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return drawingsURL
    }

    nonisolated private static func databaseFileURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("girokiq.sqlite")
    }

    nonisolated private static func drawingFileURL(for pageId: UUID) throws -> URL {
        try drawingsDirectoryURL().appendingPathComponent("\(pageId.uuidString).drawing.lzfse")
    }

    nonisolated private static func readDrawingFile(for pageId: UUID) -> Data? {
        guard
            let fileURL = try? drawingFileURL(for: pageId),
            let persistedData = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return (try? PencilKitBridge.decompressForPersistence(persistedData)) ?? persistedData
    }

    nonisolated private static func writeDrawingFile(_ data: Data, for pageId: UUID) throws {
        let fileURL = try drawingFileURL(for: pageId)
        let persistedData = PerfBisect.disableDrawingCompression
            ? data
            : try PencilKitBridge.compressForPersistence(data)
        try persistedData.write(to: fileURL, options: .atomic)
    }

    nonisolated private static func deleteDrawingFile(for pageId: UUID) {
        guard let fileURL = try? drawingFileURL(for: pageId) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    nonisolated private static func drawingFileSize(for pageId: UUID) -> Int64 {
        guard
            let fileURL = try? drawingFileURL(for: pageId),
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }

        return size.int64Value
    }

    nonisolated private static func directorySize(at url: URL) -> Int64 {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return fileURLs.reduce(into: Int64(0)) { total, fileURL in
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else { return }
            total += Int64(values.fileSize ?? 0)
        }
    }

    nonisolated private static func fileSizes(for fileNames: Set<String>) -> Int64 {
        fileNames.reduce(into: Int64(0)) { total, fileName in
            let fileURL = NotebookTransferSupport.localImageURL(for: fileName)
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize
            else { return }
            total += Int64(fileSize)
        }
    }

    nonisolated private static func clearAllDrawingFiles() throws {
        let drawingsURL = try drawingsDirectoryURL()
        if FileManager.default.fileExists(atPath: drawingsURL.path) {
            try FileManager.default.removeItem(at: drawingsURL)
        }
        try FileManager.default.createDirectory(
            at: drawingsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    nonisolated private static func sanitizedLocalPage(_ page: Page) -> Page {
        var sanitizedPage = page
        if sanitizedPage.settings != nil {
            sanitizedPage.settings?.drawingData = nil
        }
        return sanitizedPage
    }

    private func configureVacuumIfNeeded(_ queue: DatabaseQueue) {
        guard !UserDefaults.standard.bool(forKey: Self.didRunVacuumKey) else { return }

        do {
            try queue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
                try db.execute(sql: "VACUUM")
                try db.execute(sql: "PRAGMA incremental_vacuum")
            }
            UserDefaults.standard.set(true, forKey: Self.didRunVacuumKey)
        } catch {
            #if DEBUG
            print("[LocalDatabase] Failed to compact database after drawing migration: \(error)")
            #endif
        }
    }

    private func scheduleCanvasAssetMaintenanceIfNeeded() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            try? await self.runCanvasAssetMaintenanceIfNeeded()
        }
    }

    func runCanvasAssetMaintenanceIfNeeded(force: Bool = false) async throws {
        let now = Date()
        if !force,
           let lastRun = UserDefaults.standard.object(forKey: Self.lastCanvasMaintenanceKey) as? Date,
           now.timeIntervalSince(lastRun) < 24 * 60 * 60 {
            return
        }

        let referencedFiles = try await referencedImageFileNames()
        try NotebookTransferSupport.runCanvasImageMaintenance(referencedFileNames: referencedFiles)
        UserDefaults.standard.set(now, forKey: Self.lastCanvasMaintenanceKey)
    }

    private func referencedImageFileNames() async throws -> Set<String> {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT settings FROM page WHERE settings IS NOT NULL")
            var fileNames = Set<String>()

            for row in rows {
                let settings: PageSettings? = row["settings"]
                for element in settings?.elements ?? [] where element.type == "image" {
                    guard let fileName = element.content, !fileName.isEmpty else { continue }
                    fileNames.insert(fileName)
                }
            }

            return fileNames
        }
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
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

        migrator.registerMigration("v2_trash_state") { db in
            try db.alter(table: "notebook") { t in
                t.add(column: "trashed_at", .datetime)
            }
            try db.alter(table: "folder") { t in
                t.add(column: "trashed_at", .datetime)
            }
        }

        migrator.registerMigration("v3_notebook_metadata") { db in
            try db.alter(table: "notebook") { t in
                t.add(column: "canvas_type", .text).notNull().defaults(to: "infinite")
                t.add(column: "page_dimensions", .blob)
                t.add(column: "background_pattern", .text).notNull().defaults(to: "blank")
                t.add(column: "background_color_hex", .text).notNull().defaults(to: "#0F0F0E")
            }
        }

        migrator.registerMigration("v4_chat_messages") { db in
            try db.create(table: "chat") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("user_id", .text).notNull()
                t.column("notebook_id", .text)
                t.column("title", .text).notNull().defaults(to: "New Chat")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "message") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("chat_id", .text).notNull().references("chat", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("token_count", .integer)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(index: "idx_message_chat_id", on: "message", columns: ["chat_id"])
        }

        migrator.registerMigration("v5_sync_last_synced_at") { db in
            try db.alter(table: "sync_change") { t in
                t.add(column: "last_synced_at", .datetime)
            }
        }

        migrator.registerMigration("v6_strip_embedded_drawings") { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, settings FROM page WHERE settings IS NOT NULL")

            for row in rows {
                let pageId: String = row["id"]
                let storedSettings: PageSettings? = row["settings"]
                guard var settings = storedSettings else { continue }
                guard let base64Drawing = settings.drawingData else { continue }

                if let drawingData = Data(base64Encoded: base64Drawing) {
                    let existingRow: Int? = try Int.fetchOne(
                        db,
                        sql: "SELECT 1 FROM page_drawing WHERE page_id = ? LIMIT 1",
                        arguments: [pageId]
                    )

                    if existingRow == nil {
                        try db.execute(
                            sql: """
                                INSERT INTO page_drawing (page_id, drawing_data)
                                VALUES (?, ?)
                                ON CONFLICT(page_id) DO NOTHING
                                """,
                            arguments: [pageId, drawingData]
                        )
                    }
                }

                settings.drawingData = nil
                try db.execute(
                    sql: "UPDATE page SET settings = ? WHERE id = ?",
                    arguments: [settings, pageId]
                )
            }
        }

        migrator.registerMigration("v7_drawings_to_files") { db in
            let rows = try Row.fetchAll(db, sql: "SELECT page_id, drawing_data FROM page_drawing")

            for row in rows {
                let pageIdString: String = row["page_id"]
                let drawingData: Data = row["drawing_data"]
                guard let pageId = UUID(uuidString: pageIdString) else { continue }
                try Self.writeDrawingFile(drawingData, for: pageId)
            }

            try db.execute(sql: "DELETE FROM page_drawing")
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

    func notebookStorageBreakdown(userId: UUID) async throws -> [NotebookStorageBreakdownSnapshot] {
        let snapshot = try await dbQueue.read { db -> (items: [UUID: NotebookStorageBreakdownSnapshot], imageFileNamesByNotebookId: [UUID: Set<String>]) in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let notebooks = try Notebook
                .filter(Column("user_id") == userId.uuidString)
                .fetchAll(db)

            var items = Dictionary(uniqueKeysWithValues: notebooks.map { notebook in
                (notebook.id, NotebookStorageBreakdownSnapshot(
                    notebook: notebook,
                    drawingBytes: 0,
                    imageBytes: 0,
                    otherBytes: 0,
                    pendingChangeCount: 0,
                    lastSyncedAt: nil
                ))
            })
            var imageFileNamesByNotebookId: [UUID: Set<String>] = [:]

            for notebook in notebooks {
                let notebookData = try? JSONSerialization.data(withJSONObject: [
                    "id": notebook.id.uuidString,
                    "user_id": notebook.userId.uuidString,
                    "folder_id": notebook.folderId?.uuidString as Any,
                    "name": notebook.name,
                    "canvas_type": notebook.canvasType,
                    "background_pattern": notebook.backgroundPattern,
                    "background_color_hex": notebook.backgroundColorHex,
                    "created_at": ISO8601DateFormatter().string(from: notebook.createdAt),
                    "updated_at": ISO8601DateFormatter().string(from: notebook.updatedAt),
                    "trashed_at": notebook.trashedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
                ])
                if let data = notebookData {
                    guard let current = items[notebook.id] else { continue }
                    items[notebook.id] = NotebookStorageBreakdownSnapshot(
                        notebook: current.notebook,
                        drawingBytes: current.drawingBytes,
                        imageBytes: current.imageBytes,
                        otherBytes: current.otherBytes + Int64(data.count),
                        pendingChangeCount: current.pendingChangeCount,
                        lastSyncedAt: current.lastSyncedAt
                    )
                }
            }

            let pageRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT p.*
                    FROM page p
                    INNER JOIN notebook n ON n.id = p.notebook_id
                    WHERE n.user_id = ?
                    """,
                arguments: [userId.uuidString]
            )

            for row in pageRows {
                let page = try Page(row: row)
                guard var current = items[page.notebookId] else { continue }

                var payloadPage = page
                if payloadPage.settings != nil {
                    payloadPage.settings?.drawingData = nil
                }

                let pageData = try? JSONSerialization.data(withJSONObject: [
                    "id": payloadPage.id.uuidString,
                    "user_id": payloadPage.userId.uuidString,
                    "notebook_id": payloadPage.notebookId.uuidString,
                    "title": payloadPage.title,
                    "page_index": payloadPage.pageIndex,
                    "type": payloadPage.type,
                    "created_at": ISO8601DateFormatter().string(from: payloadPage.createdAt),
                    "updated_at": ISO8601DateFormatter().string(from: payloadPage.updatedAt)
                ])
                if let data = pageData {
                    current = NotebookStorageBreakdownSnapshot(
                        notebook: current.notebook,
                        drawingBytes: current.drawingBytes,
                        imageBytes: current.imageBytes,
                        otherBytes: current.otherBytes + Int64(data.count),
                        pendingChangeCount: current.pendingChangeCount,
                        lastSyncedAt: current.lastSyncedAt
                    )
                }

                current = NotebookStorageBreakdownSnapshot(
                    notebook: current.notebook,
                    drawingBytes: current.drawingBytes + Self.drawingFileSize(for: page.id),
                    imageBytes: current.imageBytes,
                    otherBytes: current.otherBytes,
                    pendingChangeCount: current.pendingChangeCount,
                    lastSyncedAt: current.lastSyncedAt
                )
                items[page.notebookId] = current

                for element in page.settings?.elements ?? [] where element.type == "image" {
                    guard let fileName = element.content, !fileName.isEmpty else { continue }
                    imageFileNamesByNotebookId[page.notebookId, default: []].insert(fileName)
                }
            }

            let chats = (try? Chat
                .filter(Column("user_id") == userId.uuidString)
                .fetchAll(db)) ?? []
            var chatNotebookMap: [UUID: UUID] = [:]

            for chat in chats {
                guard let notebookId = chat.notebookId, let current = items[notebookId] else { continue }
                chatNotebookMap[chat.id] = notebookId
                let chatData = try? JSONSerialization.data(withJSONObject: [
                    "id": chat.id.uuidString,
                    "user_id": chat.userId.uuidString,
                    "notebook_id": chat.notebookId?.uuidString as Any,
                    "title": chat.title,
                    "created_at": ISO8601DateFormatter().string(from: chat.createdAt),
                    "updated_at": ISO8601DateFormatter().string(from: chat.updatedAt)
                ])
                if let data = chatData {
                    items[notebookId] = NotebookStorageBreakdownSnapshot(
                        notebook: current.notebook,
                        drawingBytes: current.drawingBytes,
                        imageBytes: current.imageBytes,
                        otherBytes: current.otherBytes + Int64(data.count),
                        pendingChangeCount: current.pendingChangeCount,
                        lastSyncedAt: current.lastSyncedAt
                    )
                }
            }

            let messageRows = (try? Row.fetchAll(
                db,
                sql: """
                    SELECT m.*
                    FROM message m
                    INNER JOIN chat c ON c.id = m.chat_id
                    WHERE c.user_id = ?
                      AND c.notebook_id IS NOT NULL
                    """,
                arguments: [userId.uuidString]
            )) ?? []

            for row in messageRows {
                let idString: String? = row["id"]
                let chatIdString: String? = row["chat_id"]
                let roleRaw: String? = row["role"]
                let content: String? = row["content"]
                let tokenCount: Int? = row["token_count"]
                let createdAt: Date? = row["created_at"]

                guard
                    let idString,
                    let chatIdString,
                    let roleRaw,
                    let content,
                    let createdAt,
                    let chatId = UUID(uuidString: chatIdString),
                    let notebookId = chatNotebookMap[chatId],
                    let current = items[notebookId],
                    let id = UUID(uuidString: idString),
                    let role = Message.Role(rawValue: roleRaw)
                else { continue }

                let messageData = try? JSONSerialization.data(withJSONObject: [
                    "id": id.uuidString,
                    "chat_id": chatId.uuidString,
                    "role": role.rawValue,
                    "content": content,
                    "token_count": tokenCount as Any,
                    "created_at": ISO8601DateFormatter().string(from: createdAt)
                ])

                if let data = messageData {
                    items[notebookId] = NotebookStorageBreakdownSnapshot(
                        notebook: current.notebook,
                        drawingBytes: current.drawingBytes,
                        imageBytes: current.imageBytes,
                        otherBytes: current.otherBytes + Int64(data.count),
                        pendingChangeCount: current.pendingChangeCount,
                        lastSyncedAt: current.lastSyncedAt
                    )
                }
            }

            let syncRows = (try? Row.fetchAll(
                db,
                sql: """
                    SELECT
                        sc.status,
                        sc.last_synced_at,
                        CASE
                            WHEN sc."table" = 'notebook' THEN n.id
                            WHEN sc."table" = 'page' THEN p.notebook_id
                            WHEN sc."table" = 'chat' THEN c.notebook_id
                            WHEN sc."table" = 'message' THEN mc.notebook_id
                            ELSE NULL
                        END AS notebook_id
                    FROM sync_change sc
                    LEFT JOIN notebook n
                        ON sc."table" = 'notebook' AND n.id = sc.id
                    LEFT JOIN page p
                        ON sc."table" = 'page' AND p.id = sc.id
                    LEFT JOIN chat c
                        ON sc."table" = 'chat' AND c.id = sc.id
                    LEFT JOIN message m
                        ON sc."table" = 'message' AND m.id = sc.id
                    LEFT JOIN chat mc
                        ON sc."table" = 'message' AND mc.id = m.chat_id
                    WHERE
                        (sc."table" = 'notebook' AND n.user_id = ?)
                        OR
                        (sc."table" = 'page' AND p.user_id = ?)
                        OR
                        (sc."table" = 'chat' AND c.user_id = ?)
                        OR
                        (sc."table" = 'message' AND mc.user_id = ?)
                    """,
                arguments: [userId.uuidString, userId.uuidString, userId.uuidString, userId.uuidString]
            )) ?? []

            for row in syncRows {
                let notebookIdString: String? = row["notebook_id"]
                guard
                    let notebookIdString,
                    let notebookId = UUID(uuidString: notebookIdString),
                    let current = items[notebookId]
                else { continue }

                let statusRaw: String = row["status"]
                let syncStatus = SyncStatus(rawValue: statusRaw) ?? .pending
                let lastSyncedAt: Date? = row["last_synced_at"]
                let newestSyncedAt = max(current.lastSyncedAt ?? .distantPast, lastSyncedAt ?? .distantPast)

                items[notebookId] = NotebookStorageBreakdownSnapshot(
                    notebook: current.notebook,
                    drawingBytes: current.drawingBytes,
                    imageBytes: current.imageBytes,
                    otherBytes: current.otherBytes,
                    pendingChangeCount: current.pendingChangeCount + (syncStatus == .pending ? 1 : 0),
                    lastSyncedAt: newestSyncedAt == .distantPast ? current.lastSyncedAt : newestSyncedAt
                )
            }

            return (items, imageFileNamesByNotebookId)
        }

        let hydratedItems = await Task.detached(priority: .utility) { [snapshot] in
            var hydratedItems = snapshot.items
            for (notebookId, fileNames) in snapshot.imageFileNamesByNotebookId {
                var imageBytes: Int64 = 0
                for fileName in fileNames {
                    let url = NotebookTransferSupport.localImageURL(for: fileName)
                    if
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                        let size = attrs[.size] as? NSNumber
                    {
                        imageBytes += size.int64Value
                    }
                }

                if let current = hydratedItems[notebookId] {
                    hydratedItems[notebookId] = NotebookStorageBreakdownSnapshot(
                        notebook: current.notebook,
                        drawingBytes: current.drawingBytes,
                        imageBytes: current.imageBytes + imageBytes,
                        otherBytes: current.otherBytes,
                        pendingChangeCount: current.pendingChangeCount,
                        lastSyncedAt: current.lastSyncedAt
                    )
                }
            }
            return hydratedItems
        }.value

        return hydratedItems.values.sorted { lhs, rhs in
            if lhs.usedBytes == rhs.usedBytes {
                return lhs.notebook.updatedAt > rhs.notebook.updatedAt
            }
            return lhs.usedBytes > rhs.usedBytes
        }
    }

    func notebookStorageUsageBytes(userId: UUID) async throws -> Int64 {
        let items = try await notebookStorageBreakdown(userId: userId)
        return items.reduce(into: Int64(0)) { total, item in
            total += item.usedBytes
        }
    }

    func deviceStorageSnapshot() async throws -> DeviceStorageSnapshot {
        let referencedFiles = try await referencedImageFileNames()
        let imageFilesOnDisk = NotebookTransferSupport.localCanvasImageFileNamesOnDisk()
        let unusedImageFiles = imageFilesOnDisk.subtracting(referencedFiles)

        let databaseBytes: Int64 = {
            guard
                let databaseURL = try? Self.databaseFileURL(),
                let values = try? databaseURL.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = values.fileSize
            else { return 0 }
            return Int64(fileSize)
        }()

        let drawingBytes = (try? Self.drawingsDirectoryURL()).map(Self.directorySize(at:)) ?? 0
        let referencedImageBytes = Self.fileSizes(for: referencedFiles)
        let reclaimableImageBytes = Self.fileSizes(for: unusedImageFiles)

        return DeviceStorageSnapshot(
            databaseBytes: databaseBytes,
            drawingBytes: drawingBytes,
            imageBytes: referencedImageBytes + reclaimableImageBytes,
            reclaimableImageBytes: reclaimableImageBytes
        )
    }

    func clearUnusedCanvasImages() async throws -> Int64 {
        let referencedFiles = try await referencedImageFileNames()
        let imageFilesOnDisk = NotebookTransferSupport.localCanvasImageFileNamesOnDisk()
        let unusedImageFiles = imageFilesOnDisk.subtracting(referencedFiles)
        let reclaimableBytes = Self.fileSizes(for: unusedImageFiles)

        try NotebookTransferSupport.runCanvasImageMaintenance(
            referencedFileNames: referencedFiles,
            olderThan: 0
        )
        return reclaimableBytes
    }

    func saveNotebook(_ notebook: Notebook, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try notebook.save(db)
            try self.recordSyncChange(db: db, table: "notebook", id: notebook.id.uuidString, status: syncStatus)
        }
    }

    func fetchNotebook(id: UUID) async throws -> Notebook? {
        try await dbQueue.read { db in
            try Notebook.fetchOne(db, key: id.uuidString)
        }
    }

    func deleteNotebook(id: UUID, syncStatus: SyncStatus = .pending) async throws {
        let pageIDs = try await dbQueue.write { db -> [String] in
            let pageIDs: [String] = try String.fetchAll(
                db,
                sql: "SELECT id FROM page WHERE notebook_id = ?",
                arguments: [id.uuidString]
            )
            if !pageIDs.isEmpty {
                let placeholders = Array(repeating: "?", count: pageIDs.count).joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM page_drawing WHERE page_id IN (\(placeholders))",
                    arguments: StatementArguments(pageIDs)
                )
            }

            _ = try Page.filter(Column("notebook_id") == id.uuidString).deleteAll(db)
            _ = try Notebook.filter(Column("id") == id.uuidString).deleteAll(db)
            try self.recordSyncChange(db: db, table: "notebook", id: id.uuidString, status: syncStatus)
            return pageIDs
        }

        for pageID in pageIDs {
            guard let uuid = UUID(uuidString: pageID) else { continue }
            Self.deleteDrawingFile(for: uuid)
        }
    }

    func saveFolder(_ folder: Folder, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try folder.save(db)
            try self.recordSyncChange(db: db, table: "folder", id: folder.id.uuidString, status: syncStatus)
        }
    }

    func fetchFolder(id: UUID) async throws -> Folder? {
        try await dbQueue.read { db in
            try Folder.fetchOne(db, key: id.uuidString)
        }
    }

    func fetchFolders(userId: UUID) async throws -> [Folder] {
        try await dbQueue.read { db in
            try Folder
                .filter(Column("user_id") == userId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    func deleteFolder(id: UUID, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            _ = try Folder.filter(Column("id") == id.uuidString).deleteAll(db)
            try self.recordSyncChange(db: db, table: "folder", id: id.uuidString, status: syncStatus)
        }
    }

    // MARK: - Pages

    func fetchPages(notebookId: UUID) async throws -> [(page: Page, drawingData: Data?)] {
        let pages = try await dbQueue.read { db in
            try Page
                .filter(Column("notebook_id") == notebookId.uuidString)
                .order(Column("page_index").asc)
                .fetchAll(db)
        }

        return pages.map { page in
            (page, Self.readDrawingFile(for: page.id))
        }
    }

    func savePage(_ page: Page, syncStatus: SyncStatus = .pending) async throws {
        let sanitizedPage = Self.sanitizedLocalPage(page)
        try await dbQueue.write { db in
            try sanitizedPage.save(db)
            try self.recordSyncChange(db: db, table: "page", id: sanitizedPage.id.uuidString, status: syncStatus)
        }
    }

    func fetchPage(id: UUID) async throws -> (page: Page, drawingData: Data?)? {
        try await dbQueue.read { db in
            guard let page = try Page.fetchOne(db, key: id.uuidString) else {
                return nil
            }
            return (page, Self.readDrawingFile(for: id))
        }
    }

    func savePageDrawing(_ drawingData: Data, pageId: UUID, syncStatus: SyncStatus = .pending) async throws {
        try Self.writeDrawingFile(drawingData, for: pageId)
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM page_drawing WHERE page_id = ?", arguments: [pageId.uuidString])
            try db.execute(
                sql: "UPDATE page SET updated_at = ? WHERE id = ?",
                arguments: [Date(), pageId.uuidString]
            )
            try self.recordSyncChange(db: db, table: "page", id: pageId.uuidString, status: syncStatus)
        }
    }

    func deletePage(id: UUID, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            _ = try Page.filter(Column("id") == id.uuidString).deleteAll(db)
            try db.execute(sql: "DELETE FROM page_drawing WHERE page_id = ?", arguments: [id.uuidString])
            try self.recordSyncChange(db: db, table: "page", id: id.uuidString, status: syncStatus)
        }
        Self.deleteDrawingFile(for: id)
    }

    func saveCanvasElements(_ elements: [CanvasElement], forPageId pageId: UUID) async throws {
        try await saveCanvasElements(elements, forPageId: pageId, syncStatus: .pending)
    }

    func saveCanvasElements(_ elements: [CanvasElement], forPageId pageId: UUID, syncStatus: SyncStatus) async throws {
        try await dbQueue.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM page WHERE id = ?", arguments: [pageId.uuidString]) {
                var page = try Page(row: row)
                if page.settings == nil {
                    page.settings = PageSettings()
                }
                page.settings?.drawingData = nil
                page.settings?.elements = elements
                page.updatedAt = Date()
                try page.save(db)
                try self.recordSyncChange(db: db, table: "page", id: pageId.uuidString, status: syncStatus)
            }
        }
    }

    func saveDrawingData(_ data: Data, forPageId pageId: UUID) async throws {
        try await savePageDrawing(data, pageId: pageId)
    }

    // MARK: - Pending Changes (for SyncEngine)

    nonisolated private func recordSyncChange(db: Database, table: String, id: String, status: SyncStatus) throws {
        // In local-only mode we do not track pending sync changes because nothing will ever
        // be pushed to the cloud. Treat all writes as synced to prevent "Pending sync" UI
        // and runaway local queues.
        let effectiveStatus: SyncStatus = Configuration.cloudSyncEnabled ? status : .synced
        let lastSyncedAt: Date? = effectiveStatus == .synced ? Date() : nil
        try db.execute(sql: """
            INSERT INTO sync_change (id, "table", status, last_synced_at) 
            VALUES (?, ?, ?, ?) 
            ON CONFLICT(id, "table") DO UPDATE SET
                status = excluded.status,
                last_synced_at = CASE
                    WHEN excluded.status = ? THEN excluded.last_synced_at
                    ELSE sync_change.last_synced_at
                END
            """, arguments: [id, table, effectiveStatus.rawValue, lastSyncedAt, SyncStatus.synced.rawValue])
    }

    func pendingChanges() async throws -> [(table: String, id: String)] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, \"table\" FROM sync_change WHERE status = ?", arguments: [SyncStatus.pending.rawValue])
            return rows.map { (table: $0["table"], id: $0["id"]) }
        }
    }

    func pendingChangeIDs(table: String) async throws -> Set<String> {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM sync_change WHERE status = ? AND \"table\" = ?",
                arguments: [SyncStatus.pending.rawValue, table]
            )
            return Set(rows.map { ($0["id"] as String) })
        }
    }

    /// Returns notebook IDs that have at least one pending page change.
    /// Used to avoid deleting notebooks during remote-reconcile when the user has local unsynced edits.
    func notebookIDsWithPendingPageChanges(userId: UUID) async throws -> Set<UUID> {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT p.notebook_id AS notebook_id
                    FROM sync_change sc
                    INNER JOIN page p ON p.id = sc.id
                    INNER JOIN notebook n ON n.id = p.notebook_id
                    WHERE
                        sc.status = ?
                        AND sc."table" = 'page'
                        AND n.user_id = ?
                    """,
                arguments: [SyncStatus.pending.rawValue, userId.uuidString]
            )
            let ids = rows.compactMap { row -> UUID? in
                let idString: String = row["notebook_id"]
                return UUID(uuidString: idString)
            }
            return Set(ids)
        }
    }

    func userIdForSyncChange(table: String, id: String) async throws -> UUID? {
        try await dbQueue.read { db in
            let sql: String
            switch table {
            case "notebook":
                sql = "SELECT user_id FROM notebook WHERE id = ?"
            case "folder":
                sql = "SELECT user_id FROM folder WHERE id = ?"
            case "page":
                sql = "SELECT user_id FROM page WHERE id = ?"
            case "chat":
                sql = "SELECT user_id FROM chat WHERE id = ?"
            case "message":
                sql = """
                    SELECT c.user_id
                    FROM message m
                    INNER JOIN chat c ON c.id = m.chat_id
                    WHERE m.id = ?
                    """
            default:
                return nil
            }

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id]) else { return nil }
            let userIdString: String = row["user_id"]
            return UUID(uuidString: userIdString)
        }
    }

    func markSynced(table: String, id: String) async throws {
        try await dbQueue.write { db in
            try self.recordSyncChange(db: db, table: table, id: id, status: .synced)
        }
    }

    /// Local-only launch mode helper: clears "pending sync" backlog so the UI doesn't show
    /// hundreds of pending items when cloud sync is disabled.
    func markAllSyncChangesAsSynced() async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE sync_change
                    SET status = ?, last_synced_at = COALESCE(last_synced_at, ?)
                    """,
                arguments: [SyncStatus.synced.rawValue, Date()]
            )
        }
    }

    /// One-time migration helper for switching from local-only mode to full cloud sync.
    /// Existing rows were previously stamped as `.synced`, so explicitly enqueue them.
    func enqueueFullCloudBackfill(userId: UUID, includeChats: Bool = true) async throws -> Int {
        try await dbQueue.write { db in
            func enqueue(sql: String, arguments: StatementArguments) throws {
                try db.execute(sql: sql, arguments: arguments)
            }

            try enqueue(
                sql: """
                    INSERT INTO sync_change (id, "table", status, last_synced_at)
                    SELECT id, 'folder', ?, NULL
                    FROM folder
                    WHERE user_id = ?
                    ON CONFLICT(id, "table") DO UPDATE SET
                        status = excluded.status,
                        last_synced_at = excluded.last_synced_at
                    """,
                arguments: [SyncStatus.pending.rawValue, userId.uuidString]
            )

            try enqueue(
                sql: """
                    INSERT INTO sync_change (id, "table", status, last_synced_at)
                    SELECT id, 'notebook', ?, NULL
                    FROM notebook
                    WHERE user_id = ?
                    ON CONFLICT(id, "table") DO UPDATE SET
                        status = excluded.status,
                        last_synced_at = excluded.last_synced_at
                    """,
                arguments: [SyncStatus.pending.rawValue, userId.uuidString]
            )

            try enqueue(
                sql: """
                    INSERT INTO sync_change (id, "table", status, last_synced_at)
                    SELECT id, 'page', ?, NULL
                    FROM page
                    WHERE user_id = ?
                    ON CONFLICT(id, "table") DO UPDATE SET
                        status = excluded.status,
                        last_synced_at = excluded.last_synced_at
                    """,
                arguments: [SyncStatus.pending.rawValue, userId.uuidString]
            )

            if includeChats {
                try enqueue(
                    sql: """
                        INSERT INTO sync_change (id, "table", status, last_synced_at)
                        SELECT id, 'chat', ?, NULL
                        FROM chat
                        WHERE user_id = ?
                        ON CONFLICT(id, "table") DO UPDATE SET
                            status = excluded.status,
                            last_synced_at = excluded.last_synced_at
                        """,
                    arguments: [SyncStatus.pending.rawValue, userId.uuidString]
                )

                try enqueue(
                    sql: """
                        INSERT INTO sync_change (id, "table", status, last_synced_at)
                        SELECT m.id, 'message', ?, NULL
                        FROM message m
                        INNER JOIN chat c ON c.id = m.chat_id
                        WHERE c.user_id = ?
                        ON CONFLICT(id, "table") DO UPDATE SET
                            status = excluded.status,
                            last_synced_at = excluded.last_synced_at
                        """,
                    arguments: [SyncStatus.pending.rawValue, userId.uuidString]
                )
            }

            let pendingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_change WHERE status = ?",
                arguments: [SyncStatus.pending.rawValue]
            ) ?? 0
            return pendingCount
        }
    }

    /// Repairs local-only image pages created before cloud paths existed by requeueing
    /// any page whose image elements still lack a remote asset path.
    func enqueuePagesMissingImageAssetPaths(userId: UUID) async throws -> Int {
        try await dbQueue.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, settings FROM page WHERE user_id = ? AND settings IS NOT NULL",
                arguments: [userId.uuidString]
            )

            var affectedPageIDs: [String] = []
            for row in rows {
                let pageId: String = row["id"]
                let settings: PageSettings? = row["settings"]
                let hasImageMissingPath = (settings?.elements ?? []).contains { element in
                    guard element.type == "image" else { return false }
                    return element.style?.imageAssetPath?.isEmpty != false
                }
                if hasImageMissingPath {
                    affectedPageIDs.append(pageId)
                }
            }

            for pageId in affectedPageIDs {
                try db.execute(
                    sql: """
                        INSERT INTO sync_change (id, "table", status, last_synced_at)
                        VALUES (?, 'page', ?, NULL)
                        ON CONFLICT(id, "table") DO UPDATE SET
                            status = excluded.status,
                            last_synced_at = excluded.last_synced_at
                        """,
                    arguments: [pageId, SyncStatus.pending.rawValue]
                )
            }

            return affectedPageIDs.count
        }
    }

    func resetAllData() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM message")
            try db.execute(sql: "DELETE FROM chat")
            try db.execute(sql: "DELETE FROM page_drawing")
            try db.execute(sql: "DELETE FROM page")
            try db.execute(sql: "DELETE FROM folder")
            try db.execute(sql: "DELETE FROM notebook")
            try db.execute(sql: "DELETE FROM sync_change")
        }
        try? Self.clearAllDrawingFiles()
        try? NotebookTransferSupport.runCanvasImageMaintenance(referencedFileNames: [], olderThan: 0)
    }

    // MARK: - Chats (offline-first)

    func saveChat(_ chat: Chat, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try chat.save(db)
            try self.recordSyncChange(db: db, table: "chat", id: chat.id.uuidString, status: syncStatus)
        }
    }

    func fetchChat(id: UUID) async throws -> Chat? {
        try await dbQueue.read { db in
            try Chat.fetchOne(db, key: id.uuidString)
        }
    }

    func fetchChats(userId: UUID, notebookId: UUID? = nil) async throws -> [Chat] {
        try await dbQueue.read { db in
            var request = Chat
                .filter(Column("user_id") == userId.uuidString)
                .order(Column("updated_at").desc)
            if let notebookId {
                request = request.filter(Column("notebook_id") == notebookId.uuidString)
            }
            return try request.fetchAll(db)
        }
    }

    func deleteChat(id: UUID, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            _ = try Message.filter(Column("chat_id") == id.uuidString).deleteAll(db)
            _ = try Chat.filter(Column("id") == id.uuidString).deleteAll(db)
            try self.recordSyncChange(db: db, table: "chat", id: id.uuidString, status: syncStatus)
        }
    }

    func saveMessage(_ message: Message, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            try message.save(db)
            try self.recordSyncChange(db: db, table: "message", id: message.id.uuidString, status: syncStatus)
        }
    }

    func deleteMessage(id: UUID, syncStatus: SyncStatus = .pending) async throws {
        try await dbQueue.write { db in
            _ = try Message.filter(Column("id") == id.uuidString).deleteAll(db)
            try self.recordSyncChange(db: db, table: "message", id: id.uuidString, status: syncStatus)
        }
    }

    func fetchMessage(id: UUID) async throws -> Message? {
        try await dbQueue.read { db in
            try Message.fetchOne(db, key: id.uuidString)
        }
    }

    func fetchMessages(chatId: UUID) async throws -> [Message] {
        try await dbQueue.read { db in
            try Message
                .filter(Column("chat_id") == chatId.uuidString)
                .order(Column("created_at").asc)
                .fetchAll(db)
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
        canvasType = row["canvas_type"] ?? "infinite"
        if let dimsData: Data = row["page_dimensions"] {
            pageDimensions = try? JSONDecoder().decode(PageDimensions.self, from: dimsData)
        } else {
            pageDimensions = nil
        }
        backgroundPattern = row["background_pattern"] ?? "blank"
        backgroundColorHex = row["background_color_hex"] ?? "#0F0F0E"
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
        trashedAt = row["trashed_at"]
    }
    
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["folder_id"] = folderId?.uuidString
        container["name"] = name
        container["canvas_type"] = canvasType
        if let pageDimensions = pageDimensions, let data = try? JSONEncoder().encode(pageDimensions) {
            container["page_dimensions"] = data
        } else {
            container["page_dimensions"] = nil
        }
        container["background_pattern"] = backgroundPattern
        container["background_color_hex"] = backgroundColorHex
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["trashed_at"] = trashedAt
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
        trashedAt = row["trashed_at"]
    }
    
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["parent_id"] = parentId?.uuidString
        container["name"] = name
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["trashed_at"] = trashedAt
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

extension Chat: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat"

    nonisolated init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        userId = UUID(uuidString: row["user_id"]) ?? UUID()
        if let nb: String = row["notebook_id"] {
            notebookId = UUID(uuidString: nb)
        } else {
            notebookId = nil
        }
        title = row["title"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["user_id"] = userId.uuidString
        container["notebook_id"] = notebookId?.uuidString
        container["title"] = title
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

extension Message: FetchableRecord, PersistableRecord {
    static let databaseTableName = "message"

    nonisolated init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        chatId = UUID(uuidString: row["chat_id"]) ?? UUID()
        role = Role(rawValue: row["role"]) ?? .user
        content = row["content"]
        tokenCount = row["token_count"]
        createdAt = row["created_at"]
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["chat_id"] = chatId.uuidString
        container["role"] = role.rawValue
        container["content"] = content
        container["token_count"] = tokenCount
        container["created_at"] = createdAt
    }
}

nonisolated extension PageSettings: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        if let data = try? JSONEncoder().encode(self),
           let string = String(data: data, encoding: .utf8) {
            return string.databaseValue
        }
        return .null
    }
    
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> PageSettings? {
        if let string = String.fromDatabaseValue(dbValue),
           let data = string.data(using: .utf8),
           let settings = try? JSONDecoder().decode(PageSettings.self, from: data) {
            return settings
        }
        return nil
    }
}
