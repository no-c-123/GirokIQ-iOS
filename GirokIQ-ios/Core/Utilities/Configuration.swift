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

    static var anthropicAPIKey: String {
        guard let info = Bundle.main.infoDictionary else { return "" }

        if let key = info["ANTHROPIC_API_KEY"] as? String, !key.isEmpty {
            return key
        }

        if let anthropic = info["ANTHROPIC"] as? [String: Any],
           let api = anthropic["API"] as? [String: Any],
           let key = api["KEY"] as? String,
           !key.isEmpty {
            return key
        }

        func findAnthropicKey(in value: Any) -> String? {
            if let s = value as? String, s.hasPrefix("sk-ant-"), !s.isEmpty {
                return s
            }
            if let dict = value as? [String: Any] {
                for (_, v) in dict {
                    if let found = findAnthropicKey(in: v) { return found }
                }
            }
            if let arr = value as? [Any] {
                for v in arr {
                    if let found = findAnthropicKey(in: v) { return found }
                }
            }
            return nil
        }

        if let found = findAnthropicKey(in: info) {
            return found
        }

        return ""
    }
}
