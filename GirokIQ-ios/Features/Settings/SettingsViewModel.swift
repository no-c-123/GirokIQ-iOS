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

    // MARK: - Appearance

    @AppStorage("appTheme") var appearance: AppTheme = .dark
    @AppStorage("reducedMotion") var reducedMotion: Bool = false

    // MARK: - Canvas Defaults

    @AppStorage("defaultBackground") var defaultBackground: String = "grid"
    @AppStorage("palmRejection") var palmRejection: Bool = true
    @AppStorage("fingerDrawing") var fingerDrawingEnabled: Bool = false
    @AppStorage("defaultStrokeWidth") var defaultStrokeWidth: Double = 2.0

    // MARK: - Sync

    @AppStorage("autoSync") var autoSync: Bool = true
    @AppStorage("syncOnWiFiOnly") var syncOnWiFiOnly: Bool = false

    // MARK: - AI

    @AppStorage("aiEnabled") var aiEnabled: Bool = true
    @AppStorage("aiPanelDockSide") var aiPanelDockSide: AIChatPanelSide = .right

    // MARK: - Security

    @AppStorage("biometricLockEnabled") var biometricLockEnabled: Bool = false

    // MARK: - Account

    @Published var storageUsed: Int64 = 0
    @Published var notebookCount: Int = 0

    private let biometricAuth = BiometricAuthService()

    var canUseBiometrics: Bool { biometricAuth.canUseBiometrics() }
    var biometricName: String {
        biometricAuth.biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    init() {
    }

    // MARK: - Data Export

    func exportAllData(userId: UUID) async -> URL? {
        // Export all notebooks as JSON for backup
        do {
            let notebooks = try await SupabaseService.shared.fetchNotebooks(userId: userId)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(notebooks)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("GirokIQ_Export_\(Date().timeIntervalSince1970).json")
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("[Settings] Failed to export data: \(error)")
            return nil
        }
    }
}
