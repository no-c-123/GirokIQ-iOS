import SwiftUI
import Combine
import LocalAuthentication

/// Manages user preferences and app settings
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Appearance

    @AppStorage("appearance") var appearance: AppearanceMode = .system
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
    @Published var apiKeyText: String = ""
    @Published var hasAPIKey: Bool = false

    // MARK: - Security

    @AppStorage("biometricLockEnabled") var biometricLockEnabled: Bool = false

    // MARK: - Account

    @Published var storageUsed: Int64 = 0
    @Published var notebookCount: Int = 0

    private let aiService = AIService()
    private let biometricAuth = BiometricAuthService()

    var canUseBiometrics: Bool { biometricAuth.canUseBiometrics() }
    var biometricName: String {
        biometricAuth.biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    init() {
        hasAPIKey = aiService.hasAPIKey
    }

    // MARK: - AI Key Management

    func saveAPIKey() {
        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        aiService.setAPIKey(key)
        apiKeyText = ""
        hasAPIKey = true
    }

    func removeAPIKey() {
        aiService.removeAPIKey()
        hasAPIKey = false
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

    // MARK: - Types

    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
}
