import Foundation

enum CloudStorageQuotaLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
    case full
}

struct CloudStorageQuotaStatus: Equatable, Sendable {
    static let defaultLimitBytes: Int64 = 1_073_741_824
    static let warningBytes: Int64 = 850 * 1_048_576
    static let criticalBytes: Int64 = 950 * 1_048_576

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
        if usedBytes >= Self.criticalBytes { return .critical }
        if usedBytes >= Self.warningBytes { return .warning }
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
            return "Approaching the 1 GB storage limit."
        case .critical:
            return "Near the limit. Sync will stop at 1 GB."
        case .full:
            return "Sync paused. New changes stay on this device."
        }
    }

    static let empty = CloudStorageQuotaStatus(usedBytes: 0, limitBytes: defaultLimitBytes)

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

final class CloudStorageQuotaService {
    static let shared = CloudStorageQuotaService()

    private let localDatabase: LocalDatabase

    init(localDatabase: LocalDatabase = .shared) {
        self.localDatabase = localDatabase
    }

    func status(for userId: UUID?) async -> CloudStorageQuotaStatus {
        guard let userId else { return .empty }

        do {
            let usedBytes = try await localDatabase.notebookStorageUsageBytes(userId: userId)
            return CloudStorageQuotaStatus(usedBytes: usedBytes, limitBytes: CloudStorageQuotaStatus.defaultLimitBytes)
        } catch is CancellationError {
            // Expected when views/tasks are torn down; avoid noisy logs.
            return .empty
        } catch {
            print("[Quota] Failed to calculate storage status: \(error)")
            return .empty
        }
    }

    func canSyncToCloud(userId: UUID?) async -> Bool {
        await status(for: userId).canSyncToCloud
    }
}
