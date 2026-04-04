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
}
