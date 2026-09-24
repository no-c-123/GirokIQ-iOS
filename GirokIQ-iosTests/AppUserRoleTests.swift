import XCTest
@testable import GirokIQ_ios

/// The role claim decides which administrator affordances the UI shows, so the
/// decoder has to fail closed on every malformed input rather than throwing or
/// guessing. These tests are the record of that contract.
final class AppUserRoleTests: XCTestCase {

    // MARK: - Happy path

    func testReadsTheAdminClaim() {
        let token = Self.token(claims: ["user_role": "admin", "sub": UUID().uuidString])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .admin)
        XCTAssertTrue(AppUserRole.from(accessToken: token).isAdministrator)
    }

    func testReadsTheUserClaim() {
        let token = Self.token(claims: ["user_role": "user"])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .user)
        XCTAssertFalse(AppUserRole.from(accessToken: token).isAdministrator)
    }

    func testDecodesAPayloadThatNeedsBase64Padding() {
        // Payload lengths that aren't a multiple of four exercise the padding
        // path; without it Data(base64Encoded:) returns nil and everyone is a
        // plain user. Vary the claim length to hit each remainder.
        for filler in ["a", "aa", "aaa", "aaaa"] {
            let token = Self.token(claims: ["user_role": "admin", "pad": filler])
            XCTAssertEqual(
                AppUserRole.from(accessToken: token), .admin,
                "padding remainder for filler \"\(filler)\" was mishandled"
            )
        }
    }

    func testDecodesBase64URLSubstitutions() {
        // '+' and '/' are illegal in a JWT segment and appear as '-' and '_'.
        // A claim containing bytes that encode to those characters proves the
        // substitution is reversed before decoding.
        let token = Self.token(claims: ["user_role": "admin", "note": "??~~??>>???"])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .admin)
    }

    // MARK: - Fails closed

    func testUnknownRoleFallsBackToUser() {
        // A role added by a newer backend must not be treated as privileged.
        let token = Self.token(claims: ["user_role": "superadmin"])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .user)
    }

    func testMissingClaimFallsBackToUser() {
        let token = Self.token(claims: ["sub": UUID().uuidString])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .user)
    }

    func testNonStringClaimFallsBackToUser() {
        let token = Self.token(claims: ["user_role": 1])
        XCTAssertEqual(AppUserRole.from(accessToken: token), .user)
    }

    func testMalformedTokensFallBackToUser() {
        let malformed = [
            "",
            "not-a-token",
            "only.two",                       // too few segments
            "a.b.c.d",                        // too many segments
            "header..signature",              // empty payload
            "header.!!!not-base64!!!.sig"     // undecodable payload
        ]
        for token in malformed {
            XCTAssertEqual(
                AppUserRole.from(accessToken: token), .user,
                "\"\(token)\" should resolve to .user"
            )
        }
    }

    func testPayloadThatIsValidBase64ButNotJSONFallsBackToUser() {
        let payload = Data("this is not json".utf8).base64EncodedString()
        XCTAssertEqual(AppUserRole.from(accessToken: "header.\(payload).sig"), .user)
    }

    func testPayloadThatIsAJSONArrayFallsBackToUser() {
        let payload = Data("[\"admin\"]".utf8).base64EncodedString()
        XCTAssertEqual(AppUserRole.from(accessToken: "header.\(payload).sig"), .user)
    }

    // MARK: - Claim decoding

    func testDecodeReturnsAllClaims() throws {
        let subject = UUID().uuidString
        let token = Self.token(claims: ["user_role": "admin", "sub": subject, "exp": 1_900_000_000])

        let claims = try XCTUnwrap(JWTClaims.decode(token))

        XCTAssertEqual(claims["user_role"] as? String, "admin")
        XCTAssertEqual(claims["sub"] as? String, subject)
        XCTAssertEqual(claims["exp"] as? Int, 1_900_000_000)
    }

    func testDecodeReturnsNilForAStructurallyInvalidToken() {
        XCTAssertNil(JWTClaims.decode("one.two"))
        XCTAssertNil(JWTClaims.decode(""))
    }

    // MARK: - Metadata

    func testClaimKeyMatchesTheDatabaseHook() {
        // Changing this string requires changing custom_access_token_hook in
        // supabase/migrations/20260916_add_user_roles.sql.
        XCTAssertEqual(AppUserRole.claimKey, "user_role")
    }

    func testRawValuesMatchThePostgresEnum() {
        XCTAssertEqual(AppUserRole.user.rawValue, "user")
        XCTAssertEqual(AppUserRole.admin.rawValue, "admin")
        XCTAssertEqual(AppUserRole.allCases.count, 2)
    }

    func testTitlesAreNonEmpty() {
        for role in AppUserRole.allCases {
            XCTAssertFalse(role.title.isEmpty)
        }
    }

    func testRoleSurvivesCodableRoundTrip() throws {
        for role in AppUserRole.allCases {
            let data = try JSONEncoder().encode(role)
            XCTAssertEqual(try JSONDecoder().decode(AppUserRole.self, from: data), role)
        }
    }

    // MARK: - Helpers

    /// Builds an unsigned token with a real base64url payload. The signature is
    /// filler: nothing in this code path verifies it, by design.
    private static func token(claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
    }
}
