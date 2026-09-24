import Foundation

/// Platform-level totals for the administrator dashboard, from
/// `public.admin_platform_stats()`.
///
/// Every field is a count, a byte total or a date. Nothing here describes what
/// a user wrote: no note text, no page titles, no chat contents, no email
/// addresses. That is a deliberate boundary, not an oversight -- an
/// administrator needs to know how much the platform holds, not what it says.
struct AdminPlatformStats: Codable, Hashable, Sendable {
    var totalAccounts: Int = 0
    var adminAccounts: Int = 0
    var newAccounts7d: Int = 0
    var newAccounts30d: Int = 0
    var activeAccounts7d: Int = 0
    var activeAccounts30d: Int = 0
    var proAccounts: Int = 0
    var freeAccounts: Int = 0
    var totalNotebooks: Int = 0
    var totalPages: Int = 0
    var totalElements: Int = 0
    var trashedNotebooks: Int = 0
    var storageBytes: Int64 = 0
    var aiRequests7d: Int = 0
    var aiRequests30d: Int = 0
    var aiRequestsTotal: Int = 0

    enum CodingKeys: String, CodingKey {
        case totalAccounts = "total_accounts"
        case adminAccounts = "admin_accounts"
        case newAccounts7d = "new_accounts_7d"
        case newAccounts30d = "new_accounts_30d"
        case activeAccounts7d = "active_accounts_7d"
        case activeAccounts30d = "active_accounts_30d"
        case proAccounts = "pro_accounts"
        case freeAccounts = "free_accounts"
        case totalNotebooks = "total_notebooks"
        case totalPages = "total_pages"
        case totalElements = "total_elements"
        case trashedNotebooks = "trashed_notebooks"
        case storageBytes = "storage_bytes"
        case aiRequests7d = "ai_requests_7d"
        case aiRequests30d = "ai_requests_30d"
        case aiRequestsTotal = "ai_requests_total"
    }

    init() {}

    /// Every field defaults to zero when absent.
    ///
    /// A dashboard that fails to render because one aggregate came back null is
    /// worse than a dashboard showing a zero: Postgres returns null for a sum
    /// over no rows, and a brand-new deployment has no rows anywhere.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int {
            (try? container.decodeIfPresent(Int.self, forKey: key)) .flatMap { $0 } ?? 0
        }
        totalAccounts = int(.totalAccounts)
        adminAccounts = int(.adminAccounts)
        newAccounts7d = int(.newAccounts7d)
        newAccounts30d = int(.newAccounts30d)
        activeAccounts7d = int(.activeAccounts7d)
        activeAccounts30d = int(.activeAccounts30d)
        proAccounts = int(.proAccounts)
        freeAccounts = int(.freeAccounts)
        totalNotebooks = int(.totalNotebooks)
        totalPages = int(.totalPages)
        totalElements = int(.totalElements)
        trashedNotebooks = int(.trashedNotebooks)
        storageBytes = (try? container.decodeIfPresent(Int64.self, forKey: .storageBytes))
            .flatMap { $0 } ?? 0
        aiRequests7d = int(.aiRequests7d)
        aiRequests30d = int(.aiRequests30d)
        aiRequestsTotal = int(.aiRequestsTotal)
    }

    // MARK: - Derived values

    var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    /// Share of accounts on the paid tier, 0...1. Zero when there are none.
    var proShare: Double {
        guard totalAccounts > 0 else { return 0 }
        return Double(proAccounts) / Double(totalAccounts)
    }

    /// Share of accounts that touched a notebook in the last 30 days, 0...1.
    var activeShare30d: Double {
        guard totalAccounts > 0 else { return 0 }
        return min(Double(activeAccounts30d) / Double(totalAccounts), 1)
    }

    var averagePagesPerNotebook: Double {
        guard totalNotebooks > 0 else { return 0 }
        return Double(totalPages) / Double(totalNotebooks)
    }
}

/// One day of the dashboard chart, from `public.admin_daily_metrics(days)`.
struct AdminDailyMetric: Codable, Hashable, Identifiable, Sendable {
    let day: Date
    var newAccounts: Int
    var aiRequests: Int
    var activeAccounts: Int

    var id: Date { day }

    enum CodingKeys: String, CodingKey {
        case day
        case newAccounts = "new_accounts"
        case aiRequests = "ai_requests"
        case activeAccounts = "active_accounts"
    }

    init(day: Date, newAccounts: Int, aiRequests: Int, activeAccounts: Int) {
        self.day = day
        self.newAccounts = newAccounts
        self.aiRequests = aiRequests
        self.activeAccounts = activeAccounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Postgres `date` arrives as "2026-09-24", which is not what the default
        // date strategy expects, so it is parsed explicitly here rather than
        // depending on the decoder's configuration.
        let raw = try container.decode(String.self, forKey: .day)
        guard let parsed = AdminDailyMetric.dayFormatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day, in: container,
                debugDescription: "Expected a yyyy-MM-dd date, got \"\(raw)\""
            )
        }
        day = parsed
        newAccounts = try container.decodeIfPresent(Int.self, forKey: .newAccounts) ?? 0
        aiRequests = try container.decodeIfPresent(Int.self, forKey: .aiRequests) ?? 0
        activeAccounts = try container.decodeIfPresent(Int.self, forKey: .activeAccounts) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AdminDailyMetric.dayFormatter.string(from: day), forKey: .day)
        try container.encode(newAccounts, forKey: .newAccounts)
        try container.encode(aiRequests, forKey: .aiRequests)
        try container.encode(activeAccounts, forKey: .activeAccounts)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
