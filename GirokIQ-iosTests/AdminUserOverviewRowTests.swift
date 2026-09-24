import XCTest
@testable import GirokIQ_ios

/// The administrator listing decodes rows straight from a Postgres function,
/// so the decoder has to survive nulls and unfamiliar values without dropping
/// the whole listing -- and without ever inventing an administrator.
final class AdminUserOverviewRowTests: XCTestCase {

    private func decode(_ json: String) throws -> AdminUserOverviewRow {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AdminUserOverviewRow.self, from: Data(json.utf8))
    }

    func testDecodesACompleteRow() throws {
        let id = UUID()
        let row = try decode("""
        {
          "user_id": "\(id.uuidString)",
          "role": "admin",
          "notebook_count": 12,
          "page_count": 140,
          "last_updated": 1700000000
        }
        """)

        XCTAssertEqual(row.userId, id)
        XCTAssertEqual(row.role, .admin)
        XCTAssertTrue(row.role.isAdministrator)
        XCTAssertEqual(row.notebookCount, 12)
        XCTAssertEqual(row.pageCount, 140)
        XCTAssertEqual(row.lastUpdated?.timeIntervalSince1970, 1_700_000_000)
    }

    func testIdMirrorsTheUserId() throws {
        let id = UUID()
        let row = try decode("""
        {"user_id": "\(id.uuidString)", "role": "user", "notebook_count": 0, "page_count": 0, "last_updated": null}
        """)
        XCTAssertEqual(row.id, id)
    }

    func testAnAccountWithNoActivityDecodes() throws {
        // max(updated_at) over zero notebooks is SQL NULL.
        let row = try decode("""
        {"user_id": "\(UUID().uuidString)", "role": "user", "notebook_count": 0, "page_count": 0, "last_updated": null}
        """)
        XCTAssertNil(row.lastUpdated)
        XCTAssertEqual(row.notebookCount, 0)
    }

    func testMissingCountsDefaultToZero() throws {
        let row = try decode("""
        {"user_id": "\(UUID().uuidString)", "role": "user"}
        """)
        XCTAssertEqual(row.notebookCount, 0)
        XCTAssertEqual(row.pageCount, 0)
        XCTAssertNil(row.lastUpdated)
    }

    func testAnUnknownRoleDecodesAsAPlainUser() throws {
        // A role added by a newer backend must never be read as privileged.
        let row = try decode("""
        {"user_id": "\(UUID().uuidString)", "role": "superadmin", "notebook_count": 1, "page_count": 1, "last_updated": null}
        """)
        XCTAssertEqual(row.role, .user)
        XCTAssertFalse(row.role.isAdministrator)
    }

    func testAMissingUserIdIsAHardFailure() {
        // Without an identity the row is meaningless, so this one must throw
        // rather than be silently defaulted.
        XCTAssertThrowsError(try decode("""
        {"role": "admin", "notebook_count": 1, "page_count": 1}
        """))
    }

    func testRowsAreEquatableAndHashable() throws {
        let id = UUID()
        let json = """
        {"user_id": "\(id.uuidString)", "role": "user", "notebook_count": 2, "page_count": 3, "last_updated": null}
        """
        XCTAssertEqual(try decode(json), try decode(json))
        XCTAssertEqual(Set([try decode(json), try decode(json)]).count, 1)
    }

    func testMemberwiseInitialiserRoundTrips() throws {
        let row = AdminUserOverviewRow(
            userId: UUID(), role: .admin, notebookCount: 5, pageCount: 9,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(row)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AdminUserOverviewRow.self, from: data)
        XCTAssertEqual(decoded.userId, row.userId)
        XCTAssertEqual(decoded.role, .admin)
        XCTAssertEqual(decoded.notebookCount, 5)
        XCTAssertEqual(decoded.pageCount, 9)
    }
}
