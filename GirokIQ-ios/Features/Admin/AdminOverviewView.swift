import SwiftUI

/// Administrator panel: per-account aggregates, nothing more.
///
/// The visibility of this screen is decided by the role claim on the client,
/// but the data behind it is protected server-side: `admin_user_overview()`
/// raises 42501 for a non-administrator. If someone forced their way into this
/// view, they would see the permission error, not the data.
struct AdminOverviewView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var rows: [AdminUserOverviewRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                loadingRow
            } else if let errorMessage {
                errorRow(errorMessage)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No accounts",
                    systemImage: "person.slash",
                    description: Text("The overview came back empty.")
                )
            } else {
                summarySection
                accountsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Administration")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            LabeledContent("Accounts", value: "\(rows.count)")
            LabeledContent("Administrators", value: "\(rows.filter(\.role.isAdministrator).count)")
            LabeledContent("Notebooks", value: "\(rows.reduce(0) { $0 + $1.notebookCount })")
            LabeledContent("Pages", value: "\(rows.reduce(0) { $0 + $1.pageCount })")
        } header: {
            Text("Totals")
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // The overview exposes no email, by design; the id is
                        // enough to correlate with Supabase when support needs it.
                        Text(row.userId.uuidString.prefix(8) + "…")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if row.role.isAdministrator {
                            Text(row.role.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.gPrimary.opacity(0.18), in: Capsule())
                        }
                    }

                    Text("\(row.notebookCount) notebooks · \(row.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastUpdated = row.lastUpdated {
                        Text("Last activity \(lastUpdated.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No activity yet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Counts and activity only. Note contents are never exposed here.")
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading overview…").foregroundStyle(.secondary)
        }
    }

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load the overview", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await load() }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            rows = try await SupabaseService.shared.fetchAdminUserOverview()
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
