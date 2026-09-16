import XCTest
@testable import GirokIQ_ios

/// Covers the plan limits that gate notebook creation and cloud storage.
final class SubscriptionTierTests: XCTestCase {

    private var originalTier: String?

    override func setUp() {
        super.setUp()
        originalTier = UserDefaults.standard.string(forKey: AppSubscriptionTier.userDefaultsKey)
    }

    override func tearDown() {
        // Leave the simulator's defaults exactly as they were found.
        if let originalTier {
            UserDefaults.standard.set(originalTier, forKey: AppSubscriptionTier.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSubscriptionTier.userDefaultsKey)
        }
        super.tearDown()
    }

    func testFreePlanIsCappedAtThreeNotebooks() {
        XCTAssertEqual(AppSubscriptionTier.free.maximumNotebookCount, 3)
    }

    func testProPlanHasNoNotebookCap() {
        XCTAssertNil(AppSubscriptionTier.pro.maximumNotebookCount)
    }

    func testStorageLimits() {
        XCTAssertEqual(AppSubscriptionTier.free.storageLimitBytes, 1_073_741_824)   // 1 GiB
        XCTAssertEqual(AppSubscriptionTier.pro.storageLimitBytes, 10_737_418_240)   // 10 GiB
        XCTAssertGreaterThan(
            AppSubscriptionTier.pro.storageLimitBytes,
            AppSubscriptionTier.free.storageLimitBytes
        )
    }

    func testStorageLimitLabelIsHumanReadable() {
        XCTAssertFalse(AppSubscriptionTier.free.storageLimitLabel.isEmpty)
        XCTAssertFalse(AppSubscriptionTier.pro.storageLimitLabel.isEmpty)
    }

    func testPersistedDefaultsToFreeWhenNothingIsStored() {
        UserDefaults.standard.removeObject(forKey: AppSubscriptionTier.userDefaultsKey)
        XCTAssertEqual(AppSubscriptionTier.persisted, .free)
    }

    func testPersistedFallsBackToFreeOnAnUnknownValue() {
        // A tier written by a newer build must not crash or silently unlock Pro.
        UserDefaults.standard.set("enterprise", forKey: AppSubscriptionTier.userDefaultsKey)
        XCTAssertEqual(AppSubscriptionTier.persisted, .free)
    }

    func testPersistedRoundTripsBothTiers() {
        AppSubscriptionTier.persisted = .pro
        XCTAssertEqual(AppSubscriptionTier.persisted, .pro)

        AppSubscriptionTier.persisted = .free
        XCTAssertEqual(AppSubscriptionTier.persisted, .free)
    }

    func testRawValuesMatchTheDatabaseContract() {
        // These strings are stored in Supabase `app_state.subscription_tier`;
        // renaming a case without a migration would silently downgrade users.
        XCTAssertEqual(AppSubscriptionTier.free.rawValue, "free")
        XCTAssertEqual(AppSubscriptionTier.pro.rawValue, "pro")
    }

    func testTierSurvivesCodableRoundTrip() throws {
        for tier in [AppSubscriptionTier.free, .pro] {
            let data = try JSONEncoder().encode(tier)
            XCTAssertEqual(try JSONDecoder().decode(AppSubscriptionTier.self, from: data), tier)
        }
    }

    // MARK: - AppState

    func testAppStateIdMirrorsTheUserId() {
        let userId = UUID()
        XCTAssertEqual(AppState(userId: userId).id, userId)
    }

    func testAppStateDefaultsEverythingOptionalToNil() {
        let state = AppState(userId: UUID())
        XCTAssertNil(state.lastNotebookId)
        XCTAssertNil(state.lastPageId)
        XCTAssertNil(state.preferences)
        XCTAssertNil(state.subscriptionTier)
    }

    func testAppStateEncodesSnakeCaseKeysForSupabase() throws {
        let state = AppState(
            userId: UUID(),
            lastNotebookId: UUID(),
            lastPageId: UUID(),
            preferences: UserPreferences(theme: "dark", defaultPattern: "grid",
                                         fingerDrawing: false, palmRejection: true, autoSync: true),
            subscriptionTier: .pro
        )

        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // The column names are the API contract with the `app_state` table.
        XCTAssertNotNil(json["user_id"])
        XCTAssertNotNil(json["last_notebook_id"])
        XCTAssertNotNil(json["last_page_id"])
        XCTAssertNotNil(json["updated_at"])
        XCTAssertEqual(json["subscription_tier"] as? String, "pro")
        XCTAssertNil(json["userId"], "camelCase keys would not match the database")
    }

    func testAppStateDecodesARowFromSupabase() throws {
        let userId = UUID()
        let row = """
        {
          "user_id": "\(userId.uuidString)",
          "last_notebook_id": null,
          "last_page_id": null,
          "preferences": {"theme": "light", "autoSync": false},
          "subscription_tier": "free",
          "updated_at": 0
        }
        """

        let state = try JSONDecoder().decode(AppState.self, from: Data(row.utf8))

        XCTAssertEqual(state.userId, userId)
        XCTAssertNil(state.lastNotebookId)
        XCTAssertEqual(state.subscriptionTier, .free)
        XCTAssertEqual(state.preferences?.theme, "light")
        XCTAssertEqual(state.preferences?.autoSync, false)
        XCTAssertNil(state.preferences?.palmRejection)
    }

    func testAppStateSurvivesACodableRoundTrip() throws {
        let original = AppState(
            userId: UUID(),
            lastNotebookId: UUID(),
            preferences: UserPreferences(theme: "dark", defaultPattern: nil,
                                         fingerDrawing: nil, palmRejection: nil, autoSync: true),
            subscriptionTier: .free,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let decoded = try JSONDecoder().decode(
            AppState.self, from: try JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.userId, original.userId)
        XCTAssertEqual(decoded.lastNotebookId, original.lastNotebookId)
        XCTAssertEqual(decoded.subscriptionTier, original.subscriptionTier)
        XCTAssertEqual(decoded.preferences, original.preferences)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970,
                       original.updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }
}
