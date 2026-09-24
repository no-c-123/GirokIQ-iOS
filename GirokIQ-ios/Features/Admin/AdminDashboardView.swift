import SwiftUI
import Charts

/// Full-screen administrator dashboard.
///
/// What an operator needs to know about the platform: how many accounts exist,
/// how many are actually using it, what it holds, and how AI usage is trending.
///
/// What it deliberately does NOT show: anything a user wrote. No note text, no
/// page titles, no chat messages, no drawings, no email addresses. The
/// aggregates come from `admin_platform_stats()` and `admin_daily_metrics()`,
/// both of which return only counts and dates, and both of which reject a
/// non-administrator caller server-side. Hiding this screen in the client is a
/// convenience; the database is what enforces it.
struct AdminDashboardView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var stats = AdminPlatformStats()
    @State private var daily: [AdminDailyMetric] = []
    @State private var accounts: [AdminUserOverviewRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var chartMetric: ChartMetric = .activeAccounts
    @State private var range: Range = .thirtyDays

    enum ChartMetric: String, CaseIterable, Identifiable {
        case activeAccounts, newAccounts, aiRequests
        var id: String { rawValue }

        var title: String {
            switch self {
            case .activeAccounts: return "Active"
            case .newAccounts: return "Signups"
            case .aiRequests: return "AI calls"
            }
        }

        func value(_ metric: AdminDailyMetric) -> Int {
            switch self {
            case .activeAccounts: return metric.activeAccounts
            case .newAccounts: return metric.newAccounts
            case .aiRequests: return metric.aiRequests
            }
        }
    }

    enum Range: Int, CaseIterable, Identifiable {
        case sevenDays = 7
        case thirtyDays = 30
        case ninetyDays = 90
        var id: Int { rawValue }
        var title: String { "\(rawValue)d" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading && daily.isEmpty {
                    loadingState
                } else if let errorMessage, stats.totalAccounts == 0 {
                    errorState(errorMessage)
                } else {
                    VStack(alignment: .leading, spacing: GSpacing.xl) {
                        kpiGrid
                        trendCard
                        compositionCard
                        contentCard
                        accountsCard
                        privacyNote
                    }
                    .padding(GSpacing.md)
                }
            }
            .background(Color.gBackground)
            .navigationTitle("Administration")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: range) { _, _ in
                Task { await loadSeries() }
            }
        }
    }

    // MARK: - KPIs

    private var kpiGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: GSpacing.sm)],
            spacing: GSpacing.sm
        ) {
            KPITile(
                title: "Accounts",
                value: "\(stats.totalAccounts)",
                detail: stats.newAccounts7d > 0 ? "+\(stats.newAccounts7d) this week" : "no new this week",
                icon: "person.2"
            )
            KPITile(
                title: "Active (30d)",
                value: "\(stats.activeAccounts30d)",
                detail: stats.totalAccounts > 0
                    ? "\(Int((stats.activeShare30d * 100).rounded()))% of accounts"
                    : "—",
                icon: "waveform.path.ecg"
            )
            KPITile(
                title: "Notebooks",
                value: "\(stats.totalNotebooks)",
                detail: "\(stats.totalPages) pages",
                icon: "book.closed"
            )
            KPITile(
                title: "Storage",
                value: stats.storageLabel,
                detail: "\(stats.totalElements) elements",
                icon: "internaldrive"
            )
        }
    }

    // MARK: - Trend

    private var trendCard: some View {
        DashboardCard(title: "Trend", subtitle: "Daily, from the platform aggregates") {
            VStack(alignment: .leading, spacing: GSpacing.sm) {
                HStack {
                    Picker("Metric", selection: $chartMetric) {
                        ForEach(ChartMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                if daily.isEmpty {
                    Text("No data for this range yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 180)
                } else {
                    Chart(daily) { metric in
                        AreaMark(
                            x: .value("Day", metric.day),
                            y: .value(chartMetric.title, chartMetric.value(metric))
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.gPrimary.opacity(0.35), Color.gPrimary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Day", metric.day),
                            y: .value(chartMetric.title, chartMetric.value(metric))
                        )
                        .foregroundStyle(Color.gPrimary)
                        .interpolationMethod(.monotone)
                    }
                    .chartYAxis {
                        // Counts are whole numbers; fractional gridlines would
                        // imply a precision the data does not have.
                        AxisMarks(format: Decimal.FormatStyle.number.precision(.fractionLength(0)))
                    }
                    .frame(height: 180)
                }

                HStack(spacing: GSpacing.lg) {
                    Legend(label: "AI calls, 7d", value: "\(stats.aiRequests7d)")
                    Legend(label: "30d", value: "\(stats.aiRequests30d)")
                    Legend(label: "all time", value: "\(stats.aiRequestsTotal)")
                }
            }
        }
    }

    // MARK: - Composition

    private var compositionCard: some View {
        DashboardCard(title: "Plans", subtitle: "Distribution across tiers") {
            VStack(alignment: .leading, spacing: GSpacing.sm) {
                ShareBar(
                    leadingLabel: "Free \(stats.freeAccounts)",
                    trailingLabel: "Pro \(stats.proAccounts)",
                    fraction: stats.proShare
                )

                Grid(alignment: .leading, horizontalSpacing: GSpacing.lg, verticalSpacing: 6) {
                    GridRow {
                        Text("Administrators").foregroundStyle(.secondary)
                        Text("\(stats.adminAccounts)")
                    }
                    GridRow {
                        Text("New, 30 days").foregroundStyle(.secondary)
                        Text("\(stats.newAccounts30d)")
                    }
                    GridRow {
                        Text("Active, 7 days").foregroundStyle(.secondary)
                        Text("\(stats.activeAccounts7d)")
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Content

    private var contentCard: some View {
        DashboardCard(title: "Content", subtitle: "Volume only, never contents") {
            Grid(alignment: .leading, horizontalSpacing: GSpacing.lg, verticalSpacing: 6) {
                GridRow {
                    Text("Notebooks").foregroundStyle(.secondary)
                    Text("\(stats.totalNotebooks)")
                }
                GridRow {
                    Text("Pages").foregroundStyle(.secondary)
                    Text("\(stats.totalPages)")
                }
                GridRow {
                    Text("Canvas elements").foregroundStyle(.secondary)
                    Text("\(stats.totalElements)")
                }
                GridRow {
                    Text("Pages per notebook").foregroundStyle(.secondary)
                    Text(stats.averagePagesPerNotebook.formatted(.number.precision(.fractionLength(1))))
                }
                GridRow {
                    Text("In trash").foregroundStyle(.secondary)
                    Text("\(stats.trashedNotebooks)")
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Accounts

    private var accountsCard: some View {
        DashboardCard(
            title: "Accounts",
            subtitle: "\(accounts.count) rows, identified by id only"
        ) {
            if accounts.isEmpty {
                Text("No accounts returned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts.prefix(50)) { row in
                        AccountRow(row: row)
                        if row.id != accounts.prefix(50).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                    if accounts.count > 50 {
                        Text("Showing the first 50 of \(accounts.count).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, GSpacing.sm)
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.gPrimary)
            Text("""
            This dashboard shows counts, dates and roles. Note contents, page \
            titles, drawings, chat history and email addresses are never \
            exposed here, and the functions behind it reject any caller whose \
            token does not carry the administrator role.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(GSpacing.md)
        .background(Color.gPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: GRadius.sm))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: GSpacing.md) {
            ProgressView()
            Text("Loading platform metrics…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: GSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load the dashboard").font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .padding(.top, GSpacing.xs)
        }
        .padding(GSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil

        // Three independent queries, so they run concurrently rather than
        // stacking three round trips.
        async let statsTask = SupabaseService.shared.fetchAdminPlatformStats()
        async let seriesTask = SupabaseService.shared.fetchAdminDailyMetrics(days: range.rawValue)
        async let accountsTask = SupabaseService.shared.fetchAdminUserOverview()

        do {
            let (loadedStats, loadedSeries, loadedAccounts) =
                try await (statsTask, seriesTask, accountsTask)
            stats = loadedStats
            daily = loadedSeries
            accounts = loadedAccounts.sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Reloads only the chart when the range changes; the totals do not depend
    /// on it, so refetching them would be wasted work.
    private func loadSeries() async {
        do {
            daily = try await SupabaseService.shared.fetchAdminDailyMetrics(days: range.rawValue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Building blocks

private struct KPITile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.gIconSmall)
                    .foregroundStyle(Color.gPrimary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.gDisplaySerif)
                .foregroundStyle(Color.gTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GSpacing.md)
        .background(Color.gSurface, in: RoundedRectangle(cornerRadius: GRadius.sm))
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.gSerifTitle).foregroundStyle(Color.gTextPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GSpacing.md)
        .background(Color.gSurface, in: RoundedRectangle(cornerRadius: GRadius.sm))
    }
}

private struct Legend: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct ShareBar: View {
    let leadingLabel: String
    let trailingLabel: String
    /// Portion filled by the trailing series, 0...1.
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gPrimary.opacity(0.15))
                    Capsule()
                        .fill(Color.gPrimary)
                        .frame(width: max(0, min(1, fraction)) * proxy.size.width)
                }
            }
            .frame(height: 10)

            HStack {
                Text(leadingLabel)
                Spacer()
                Text(trailingLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct AccountRow: View {
    let row: AdminUserOverviewRow

    var body: some View {
        HStack(spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.userId.uuidString.prefix(8) + "…")
                    .font(.system(.footnote, design: .monospaced))
                Text("\(row.notebookCount) notebooks · \(row.pageCount) pages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if row.role.isAdministrator {
                Text(row.role.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.gPrimary.opacity(0.18), in: Capsule())
            }

            Text(row.lastUpdated.map { $0.formatted(.relative(presentation: .numeric)) } ?? "never")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }
}
