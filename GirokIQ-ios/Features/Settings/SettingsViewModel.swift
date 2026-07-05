import SwiftUI
import Combine
import LocalAuthentication

enum AIChatPanelSide: String, CaseIterable, Identifiable {
    case left
    case right
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// Manages user preferences and app settings
@MainActor
final class SettingsViewModel: ObservableObject {
    private struct FullExportPackage: Codable {
        var version: Int
        var exportedAt: Date
        var folders: [Folder]
        var notebooks: [ExportedNotebook]
    }

    private struct ExportedNotebook: Codable {
        var notebook: Notebook
        var archive: NotebookTransferPackage
    }

    enum AIAvailabilityStatus {
        case available
        case unavailable
        case disabled

        var title: String {
            switch self {
            case .available: return "Available"
            case .unavailable: return "Unavailable"
            case .disabled: return "Disabled"
            }
        }

        var tintColor: Color {
            switch self {
            case .available: return .green
            case .unavailable: return .red
            case .disabled: return .gTextTertiary
            }
        }
    }

    // MARK: - Appearance

    @AppStorage("appTheme") var appearance: AppTheme = .dark
    @AppStorage("reducedMotion") var reducedMotion: Bool = false

    // MARK: - Canvas Defaults

    @AppStorage("defaultBackground") var defaultBackground: String = "grid"
    @AppStorage("palmRejection") var palmRejection: Bool = true
    @AppStorage("fingerDrawing") var fingerDrawingEnabled: Bool = false
    @AppStorage("defaultStrokeWidth") var defaultStrokeWidth: Double = 2.0 {
        didSet {
            // Keep canvas' active "last used" width in sync with the default so the
            // setting has an immediate visible effect across the app.
            UserDefaults.standard.set(defaultStrokeWidth, forKey: "savedStrokeWidth")
        }
    }

    // MARK: - Sync

    @AppStorage("autoSync") var autoSync: Bool = true
    @AppStorage("syncOnWiFiOnly") var syncOnWiFiOnly: Bool = false

    // MARK: - AI

    @AppStorage("aiEnabled") var aiEnabled: Bool = true {
        didSet { refreshAIAvailabilityStatus() }
    }
    @AppStorage("aiPanelDockSide") var aiPanelDockSide: AIChatPanelSide = .right
    @Published private(set) var aiAvailabilityStatus: AIAvailabilityStatus = .available

    // MARK: - Security

    @AppStorage("biometricLockEnabled") var biometricLockEnabled: Bool = false

    // MARK: - Account

    @Published var storageUsed: Int64 = 0
    @Published var notebookCount: Int = 0

    private let biometricAuth = BiometricAuthService()
    private let localDatabase = LocalDatabase.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()

    var canUseBiometrics: Bool { biometricAuth.canUseBiometrics() }
    var biometricName: String {
        biometricAuth.biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    init() {
        // First launch: seed the canvas width with the default value so the
        // "Default Stroke Width" setting actually defines the starting width.
        if UserDefaults.standard.object(forKey: "savedStrokeWidth") == nil {
            UserDefaults.standard.set(defaultStrokeWidth, forKey: "savedStrokeWidth")
        }

        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAIAvailabilityStatus()
            }
            .store(in: &cancellables)

        refreshAIAvailabilityStatus()
    }

    // MARK: - Data Export

    func exportAllData(userId: UUID) async -> URL? {
        do {
            let package = try await makeFullExportPackage(userId: userId)
            let data = try makeTransferEncoder().encode(package)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GirokIQ_Backup_\(Int(Date().timeIntervalSince1970)).girokbackup")
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("[Settings] Failed to export data: \(error)")
            return nil
        }
    }

    private func makeFullExportPackage(userId: UUID) async throws -> FullExportPackage {
        let folders = try await localDatabase.fetchFolders(userId: userId)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        let notebooks = try await localDatabase.fetchNotebooks(userId: userId)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        var notebookArchives: [ExportedNotebook] = []
        notebookArchives.reserveCapacity(notebooks.count)
        for notebook in notebooks {
            notebookArchives.append(
                ExportedNotebook(
                    notebook: notebook,
                    archive: try await makeNotebookTransferPackage(for: notebook)
                )
            )
        }

        return FullExportPackage(
            version: 1,
            exportedAt: Date(),
            folders: folders,
            notebooks: notebookArchives
        )
    }

    private func makeNotebookTransferPackage(for notebook: Notebook) async throws -> NotebookTransferPackage {
        let fetchedPages = try await localDatabase.fetchPages(notebookId: notebook.id)
        let snapshotPages = fetchedPages.enumerated().map { index, tuple in
            NotebookTransferPage(
                title: tuple.page.title,
                pageIndex: index,
                type: tuple.page.type,
                backgroundPattern: tuple.page.settings?.backgroundPattern ?? notebook.backgroundPattern,
                drawingData: tuple.drawingData,
                elements: tuple.page.settings?.elements ?? []
            )
        }

        return NotebookTransferPackage(
            version: 2,
            notebook: NotebookTransferNotebook(
                name: notebook.name,
                canvasType: notebook.canvasType,
                pageDimensions: notebook.pageDimensions,
                backgroundPattern: notebook.backgroundPattern,
                backgroundColorHex: notebook.backgroundColorHex
            ),
            pages: snapshotPages,
            assets: NotebookTransferSupport.imageAssets(from: snapshotPages)
        )
    }

    private func makeTransferEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func refreshAIAvailabilityStatus() {
        if !aiEnabled {
            aiAvailabilityStatus = .disabled
        } else if !networkMonitor.isConnected {
            aiAvailabilityStatus = .unavailable
        } else {
            aiAvailabilityStatus = .available
        }
    }
}
