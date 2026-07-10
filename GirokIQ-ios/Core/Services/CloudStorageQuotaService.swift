import Foundation

enum CloudStorageQuotaLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
    case full
}

struct CloudStorageQuotaStatus: Equatable, Sendable {
    static let defaultLimitBytes: Int64 = AppSubscriptionTier.free.storageLimitBytes

    static let localOnlyWriteMessage =
        "This will only be stored on this device until you free up space."
    static let syncPausedMessage =
        "Storage limit reached. New changes are being stored on this device only."

    let usedBytes: Int64
    let limitBytes: Int64

    var progress: Double {
        guard limitBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(limitBytes), 0), 1)
    }

    var level: CloudStorageQuotaLevel {
        if usedBytes >= limitBytes { return .full }
        if usedBytes >= criticalThresholdBytes { return .critical }
        if usedBytes >= warningThresholdBytes { return .warning }
        return .normal
    }

    var canSyncToCloud: Bool { level != .full }
    var usedText: String { Self.byteFormatter.string(fromByteCount: usedBytes) }
    var limitText: String { Self.byteFormatter.string(fromByteCount: limitBytes) }
    var remainingText: String { Self.byteFormatter.string(fromByteCount: max(limitBytes - usedBytes, 0)) }

    var statusMessage: String {
        switch level {
        case .normal:
            return "\(remainingText) available"
        case .warning:
            return "Approaching the \(limitText) storage limit."
        case .critical:
            return "Near the limit. Sync will stop at \(limitText)."
        case .full:
            return "Sync paused. New changes stay on this device."
        }
    }

    nonisolated static let empty = CloudStorageQuotaStatus(usedBytes: 0, limitBytes: defaultLimitBytes)

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private var warningThresholdBytes: Int64 {
        Int64(Double(limitBytes) * 0.85)
    }

    private var criticalThresholdBytes: Int64 {
        Int64(Double(limitBytes) * 0.95)
    }
}

actor CloudStorageQuotaService {
    nonisolated static let shared: CloudStorageQuotaService = {
        CloudStorageQuotaService(localDatabase: MainActor.assumeIsolated { LocalDatabase.shared })
    }()

    private let localDatabase: LocalDatabase
    private var cachedStatus: CloudStorageQuotaStatus?
    private var cachedUserId: UUID?
    private var cacheTimestamp: Date?

    init(localDatabase: LocalDatabase) {
        self.localDatabase = localDatabase
    }

    func status(for userId: UUID?) async -> CloudStorageQuotaStatus {
        guard let userId else { return .empty }
        let tier = await AppSubscriptionTier.persisted
        if cachedUserId == userId,
           let cached = cachedStatus,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < 60,
           await cached.limitBytes == tier.storageLimitBytes {
            return cached
        }

        do {
            let usedBytes = try await localDatabase.notebookStorageUsageBytes(userId: userId)
            let status = await CloudStorageQuotaStatus(
                usedBytes: usedBytes,
                limitBytes: tier.storageLimitBytes
            )
            cachedUserId = userId
            cachedStatus = status
            cacheTimestamp = Date()
            return status
        } catch is CancellationError {
            // Expected when views/tasks are torn down; avoid noisy logs.
            return .empty
        } catch {
            #if DEBUG
            print("[Quota] Failed to calculate storage status: \(error)")
            #endif
            return .empty
        }
    }

    func canSyncToCloud(userId: UUID?) async -> Bool {
        await status(for: userId).canSyncToCloud
    }

    func invalidateCache() {
        cachedStatus = nil
        cachedUserId = nil
        cacheTimestamp = nil
    }
}
