import Foundation

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

    // MARK: - Supabase

    // MARK: - Cloud Data Mode

    /// Controls which features are allowed to read/write user data to Supabase.
    /// For launch we keep Supabase for authentication (and optionally app_state),
    /// while notebooks/pages/assets remain local-only.
    enum CloudDataMode {
        /// Supabase is used only for authentication.
        case authOnly
        /// Supabase is used for authentication and lightweight app state (e.g. last-opened pointers).
        case authAndAppState
        /// Full sync for notebooks/pages/chats/assets.
        case full
    }

    /// Current migration setting: full cloud sync enabled.
    static let cloudDataMode: CloudDataMode = .full

    /// When false, the app behaves as local-only (offline-first) for notebooks/pages/chats/assets.
    static var cloudSyncEnabled: Bool { cloudDataMode == .full }

    /// When false, AI chats/messages remain local-only.
    static var cloudChatEnabled: Bool { cloudDataMode == .full }

    /// When true, we may read/write `app_state` to Supabase.
    static var cloudAppStateEnabled: Bool { cloudDataMode != .authOnly }

    static var supabaseURL: URL {
        if let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Fallback for development — remove before production
        guard let url = URL(string: "https://bapqxqydqzopbpjrpnna.supabase.co") else {
            preconditionFailure("Invalid fallback Supabase URL")
        }
        return url
    }

    static var supabaseAnonKey: String {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty {
            return key
        }
        // Fallback for development — remove before production
        return "sb_publishable_423Dnw91Y5cLpTMC7wCuMA_3cAuqY-t"
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
