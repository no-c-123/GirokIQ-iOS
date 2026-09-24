import XCTest
@testable import GirokIQ_ios

/// The dashboard reads aggregates straight out of Postgres, where a sum over
/// no rows is NULL and a fresh deployment has no rows at all. A dashboard that
/// refuses to render because one aggregate came back null is worse than one
/// showing a zero, so these tests pin that behaviour down.
final class AdminPlatformStatsTests: XCTestCase {

    private func decode(_ json: String) throws -> AdminPlatformStats {
        try JSONDecoder().decode(AdminPlatformStats.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesACompleteRow() throws {
        let stats = try decode("""
        {
          "total_accounts": 42, "admin_accounts": 2,
          "new_accounts_7d": 5, "new_accounts_30d": 11,
          "active_accounts_7d": 8, "active_accounts_30d": 21,
          "pro_accounts": 6, "free_accounts": 36,
          "total_notebooks": 120, "total_pages": 640, "total_elements": 3100,
          "trashed_notebooks": 4, "storage_bytes": 1073741824,
          "ai_requests_7d": 90, "ai_requests_30d": 400, "ai_requests_total": 1250
        }
        """)

        XCTAssertEqual(stats.totalAccounts, 42)
        XCTAssertEqual(stats.adminAccounts, 2)
        XCTAssertEqual(stats.proAccounts, 6)
        XCTAssertEqual(stats.totalPages, 640)
        XCTAssertEqual(stats.storageBytes, 1_073_741_824)
        XCTAssertEqual(stats.aiRequestsTotal, 1250)
    }

    func testAnEmptyPlatformDecodesAsZeros() throws {
        // Every aggregate is absent, which is what a brand-new deployment
        // produces once the nulls are stripped.
        let stats = try decode("{}")

        XCTAssertEqual(stats.totalAccounts, 0)
        XCTAssertEqual(stats.totalNotebooks, 0)
        XCTAssertEqual(stats.storageBytes, 0)
        XCTAssertEqual(stats.aiRequestsTotal, 0)
    }

    func testNullAggregatesDecodeAsZeros() throws {
        // sum() over zero rows is NULL in Postgres, not 0.
        let stats = try decode("""
        {"total_accounts": 3, "storage_bytes": null, "ai_requests_total": null, "total_pages": null}
        """)

        XCTAssertEqual(stats.totalAccounts, 3)
        XCTAssertEqual(stats.storageBytes, 0)
        XCTAssertEqual(stats.aiRequestsTotal, 0)
        XCTAssertEqual(stats.totalPages, 0)
    }

    func testStorageBytesSurvivesValuesBeyondInt32() throws {
        // 8 GB does not fit in a 32-bit int; on a 64-bit device Int would cope,
        // but the field is Int64 precisely so the contract does not depend on
        // the platform's word size.
        let stats = try decode("{\"storage_bytes\": 8589934592}")
        XCTAssertEqual(stats.storageBytes, 8_589_934_592)
    }

    // MARK: - Derived values

    func testSharesAreZeroWhenThereAreNoAccounts() {
        // Guards the divide-by-zero, which is the only way these can crash.
        let stats = AdminPlatformStats()
        XCTAssertEqual(stats.proShare, 0)
        XCTAssertEqual(stats.activeShare30d, 0)
        XCTAssertEqual(stats.averagePagesPerNotebook, 0)
    }

    func testProShareIsTheFractionOfPaidAccounts() throws {
        let stats = try decode("{\"total_accounts\": 40, \"pro_accounts\": 10}")
        XCTAssertEqual(stats.proShare, 0.25, accuracy: 0.0001)
    }

    func testActiveShareIsClampedToOne() throws {
        // Active counts come from a different table than the account count, so
        // a lagging aggregate could exceed the total. The bar must not overflow.
        let stats = try decode("{\"total_accounts\": 10, \"active_accounts_30d\": 15}")
        XCTAssertEqual(stats.activeShare30d, 1.0)
    }

    func testAveragePagesPerNotebook() throws {
        let stats = try decode("{\"total_notebooks\": 4, \"total_pages\": 10}")
        XCTAssertEqual(stats.averagePagesPerNotebook, 2.5, accuracy: 0.0001)
    }

    func testStorageLabelIsHumanReadable() throws {
        let stats = try decode("{\"storage_bytes\": 1073741824}")
        XCTAssertFalse(stats.storageLabel.isEmpty)
        XCTAssertTrue(stats.storageLabel.contains("GB") || stats.storageLabel.contains("MB"))
    }
}

/// One point of the dashboard chart.
final class AdminDailyMetricTests: XCTestCase {

    private func decode(_ json: String) throws -> AdminDailyMetric {
        try JSONDecoder().decode(AdminDailyMetric.self, from: Data(json.utf8))
    }

    func testDecodesAPostgresDate() throws {
        let metric = try decode("""
        {"day": "2026-09-24", "new_accounts": 3, "ai_requests": 17, "active_accounts": 5}
        """)

        XCTAssertEqual(AdminDailyMetric.dayFormatter.string(from: metric.day), "2026-09-24")
        XCTAssertEqual(metric.newAccounts, 3)
        XCTAssertEqual(metric.aiRequests, 17)
        XCTAssertEqual(metric.activeAccounts, 5)
        XCTAssertEqual(metric.id, metric.day)
    }

    func testAQuietDayDecodesAsZeros() throws {
        // generate_series fills empty days so the chart does not skip them.
        let metric = try decode("{\"day\": \"2026-09-01\"}")
        XCTAssertEqual(metric.newAccounts, 0)
        XCTAssertEqual(metric.aiRequests, 0)
        XCTAssertEqual(metric.activeAccounts, 0)
    }

    func testAMalformedDateThrows() {
        // Silently dropping the point would misplace every later value on the
        // x axis, so this has to fail loudly.
        XCTAssertThrowsError(try decode("{\"day\": \"24/09/2026\"}"))
        XCTAssertThrowsError(try decode("{\"day\": \"\"}"))
    }

    func testAMissingDateThrows() {
        XCTAssertThrowsError(try decode("{\"new_accounts\": 1}"))
    }

    func testTheDayIsParsedInUTCNotLocalTime() throws {
        // The formatter pins UTC; without that, a device east of Greenwich
        // would shift every point to the previous day.
        let metric = try decode("{\"day\": \"2026-09-24\"}")
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: metric.day)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 24)
    }

    func testRoundTripsThroughCodable() throws {
        let original = AdminDailyMetric(
            day: AdminDailyMetric.dayFormatter.date(from: "2026-09-24")!,
            newAccounts: 2, aiRequests: 9, activeAccounts: 4
        )
        let decoded = try JSONDecoder().decode(
            AdminDailyMetric.self, from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }
}
