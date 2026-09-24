import Foundation

/// One row of `public.admin_user_overview()`.
///
/// Aggregates only: how many notebooks and pages an account holds and when it
/// was last active. Deliberately no note content, no drawings and no chats --
/// being an administrator should not imply the ability to read someone's
/// notes.
struct AdminUserOverviewRow: Codable, Identifiable, Hashable, Sendable {
    let userId: UUID
    let role: AppUserRole
    let notebookCount: Int
    let pageCount: Int
    let lastUpdated: Date?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
        case notebookCount = "notebook_count"
        case pageCount = "page_count"
        case lastUpdated = "last_updated"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        // An unrecognised role must not fail the whole listing, and must not
        // be mistaken for an administrator.
        role = (try? container.decode(AppUserRole.self, forKey: .role)) ?? .user
        notebookCount = try container.decodeIfPresent(Int.self, forKey: .notebookCount) ?? 0
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
    }

    init(
        userId: UUID,
        role: AppUserRole,
        notebookCount: Int,
        pageCount: Int,
        lastUpdated: Date?
    ) {
        self.userId = userId
        self.role = role
        self.notebookCount = notebookCount
        self.pageCount = pageCount
        self.lastUpdated = lastUpdated
    }
}
