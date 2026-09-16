import Foundation

/// Who the signed-in user is allowed to be, as asserted by the `user_role`
/// claim that Supabase's access-token hook writes into the JWT.
///
/// IMPORTANT: this type decides what the UI *offers*, never what the backend
/// *permits*. The token is issued by the server but held by the client, so a
/// determined user can present whatever they like to this code. Every
/// administrator capability is separately enforced in Postgres by
/// `public.is_admin()`, which reads the same claim from the verified token.
/// Treat a role read here as a hint for presentation only.
enum AppUserRole: String, Codable, Sendable, CaseIterable {
    case user
    case admin

    /// The claim name written by `public.custom_access_token_hook`.
    static let claimKey = "user_role"

    var isAdministrator: Bool { self == .admin }

    var title: String {
        switch self {
        case .user: return "User"
        case .admin: return "Administrator"
        }
    }

    /// Reads the role out of a Supabase access token.
    ///
    /// Fails closed: a malformed token, a missing claim or a role this build
    /// doesn't know about all resolve to `.user`, so a parsing failure can
    /// never hand someone administrator UI.
    static func from(accessToken: String) -> AppUserRole {
        guard let claims = JWTClaims.decode(accessToken),
              let raw = claims[claimKey] as? String,
              let role = AppUserRole(rawValue: raw) else {
            return .user
        }
        return role
    }
}

/// Minimal reader for the payload segment of a JWT.
///
/// This deliberately does NOT verify the signature: verification belongs to
/// the server that issued the token, and doing it here would imply a
/// guarantee this code cannot make. See the note on `AppUserRole`.
enum JWTClaims {
    static func decode(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        guard let data = base64URLDecode(String(segments[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// JWT uses base64url without padding; Foundation needs the padding back
    /// and the two substituted characters restored.
    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}
