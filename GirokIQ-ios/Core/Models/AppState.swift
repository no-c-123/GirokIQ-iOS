import Foundation

// MARK: - App State (matches Supabase `app_state` table)

enum AppSubscriptionTier: String, Codable, Sendable {
    case free
    case pro

    static let userDefaultsKey = "app.subscriptionTier"

    var storageLimitBytes: Int64 {
        switch self {
        case .free:
            return 1_073_741_824
        case .pro:
            return 10_737_418_240
        }
    }

    var storageLimitLabel: String {
        ByteCountFormatter.string(fromByteCount: storageLimitBytes, countStyle: .file)
    }

    static var persisted: AppSubscriptionTier {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let tier = AppSubscriptionTier(rawValue: rawValue) else {
                return .free
            }
            return tier
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}

struct AppState: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    var lastNotebookId: UUID?
    var lastPageId: UUID?
    var preferences: UserPreferences?
    var subscriptionTier: AppSubscriptionTier?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastNotebookId = "last_notebook_id"
        case lastPageId = "last_page_id"
        case preferences
        case subscriptionTier = "subscription_tier"
        case updatedAt = "updated_at"
    }

    init(
        userId: UUID,
        lastNotebookId: UUID? = nil,
        lastPageId: UUID? = nil,
        preferences: UserPreferences? = nil,
        subscriptionTier: AppSubscriptionTier? = nil,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.lastNotebookId = lastNotebookId
        self.lastPageId = lastPageId
        self.preferences = preferences
        self.subscriptionTier = subscriptionTier
        self.updatedAt = updatedAt
    }
}

// MARK: - User Preferences (jsonb column)

struct UserPreferences: Codable, Hashable {
    var theme: String?
    var defaultPattern: String?
    var fingerDrawing: Bool?
    var palmRejection: Bool?
    var autoSync: Bool?
}
