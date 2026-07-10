import Foundation

// MARK: - Cloud Sync Configuration

/// Controls which features are allowed to read/write user data to Supabase.
enum CloudDataMode: Sendable {
    /// Supabase is used only for authentication.
    case authOnly
    /// Supabase is used for authentication and lightweight app state (e.g. last-opened pointers).
    case authAndAppState
    /// Full sync for notebooks/pages/chats/assets.
    case full
}

// MARK: - App Configuration

/// Provides build-time configuration values.
///
/// ## Setup (required for xcconfig integration):
/// 1. In Xcode, set the project's Debug/Release configurations to use
///    `Config/Debug.xcconfig` and `Config/Release.xcconfig` respectively.
/// 2. In Info.plist, add:
///    - `SUPABASE_URL` = `$(SUPABASE_URL)`
///    - `SUPABASE_ANON_KEY` = `$(SUPABASE_ANON_KEY)`
///
/// Until xcconfig integration is wired, the hardcoded fallbacks below are used.
enum Configuration {
    /// Current migration setting: full cloud sync enabled.
    nonisolated static let cloudDataMode: CloudDataMode = .full

    nonisolated static let cloudSyncEnabledKey = "sync.cloudSyncEnabled"

    /// Safe to read from any thread/isolation domain, including inside GRDB closures.
    /// Falls back to the current launch-mode default until explicitly overridden.
    nonisolated static var cloudSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: cloudSyncEnabledKey) as? Bool ?? {
            switch cloudDataMode {
            case .full:
                return true
            case .authOnly, .authAndAppState:
                return false
            }
        }()
    }

    /// Persists the current cloud-sync mode so nonisolated readers see a consistent value.
    nonisolated static func setCloudSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: cloudSyncEnabledKey)
    }

    /// When false, AI chats/messages remain local-only.
    nonisolated static var cloudChatEnabled: Bool { cloudSyncEnabled }

    /// When true, we may read/write `app_state` to Supabase.
    nonisolated static var cloudAppStateEnabled: Bool {
        switch cloudDataMode {
        case .authOnly:
            return false
        case .authAndAppState, .full:
            return true
        }
    }

    static var supabaseURL: URL {
        if let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           !urlString.isEmpty,
           !urlString.contains("$("),
           let url = URL(string: urlString),
           url.scheme != nil,
           url.host() != nil {
            return url
        }
        preconditionFailure("Missing or invalid SUPABASE_URL. Set a full https URL in Info.plist or xcconfig.")
    }

    static var supabaseAnonKey: String {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
           !key.isEmpty,
           !key.contains("$(") {
            return key
        }
        preconditionFailure("Missing or invalid SUPABASE_ANON_KEY. Set it in Info.plist or xcconfig.")
    }

    static var supabaseFunctionsBaseURL: URL {
        if let host = supabaseURL.host(),
           host.contains(".supabase.co"),
           let projectRef = host.split(separator: ".").first,
           let url = URL(string: "https://\(projectRef).functions.supabase.co") {
            return url
        }

        return supabaseURL.appendingPathComponent("functions/v1")
    }
}

// MARK: - Performance Bisect (TEMPORARY — remove after diagnosis)
/// Flip exactly ONE flag to true per test run. All false = current behavior.
enum PerfBisect {
    /// Test A: skip the history snapshot captured on every debounced save tick.
    static let disablePerTickHistoryCapture = false
    /// Test B: write drawing files uncompressed (reads already accept both formats).
    static let disableDrawingCompression = false
    /// Test C: never start the 2-second background sync loop.
    static let disableAutoSyncLoop = false
    /// Test D: skip the notebook refresh when the app returns to foreground.
    static let disableSceneRefresh = false
}
