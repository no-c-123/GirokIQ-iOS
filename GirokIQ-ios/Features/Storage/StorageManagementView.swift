import SwiftUI
import Combine

@MainActor
final class StorageManagementViewModel: ObservableObject {
    @Published private(set) var cloudStatus: CloudStorageQuotaStatus = .empty
    @Published private(set) var deviceSnapshot = DeviceStorageSnapshot(
        databaseBytes: 0,
        drawingBytes: 0,
        imageBytes: 0,
        reclaimableImageBytes: 0
    )
    @Published private(set) var notebookSnapshots: [NotebookStorageBreakdownSnapshot] = []
    @Published var infoMessage: String?
    @Published var deviceErrorMessage: String?
    @Published var notebookErrorMessage: String?
    @Published var isLoading = false
    @Published var isClearingUnusedImages = false
    @Published var isEmptyingTrash = false

    let userId: UUID
    private let homeViewModel: HomeViewModel
    private let localDatabase = LocalDatabase.shared
    private let quotaService = CloudStorageQuotaService.shared

    init(userId: UUID, homeViewModel: HomeViewModel) {
        self.userId = userId
        self.homeViewModel = homeViewModel
    }

    var activeNotebookSnapshots: [NotebookStorageBreakdownSnapshot] {
        notebookSnapshots
            .filter { $0.notebook.trashedAt == nil }
            .sorted { $0.usedBytes > $1.usedBytes }
    }

    var trashedNotebookSnapshots: [NotebookStorageBreakdownSnapshot] {
        notebookSnapshots
            .filter { $0.notebook.trashedAt != nil }
            .sorted { $0.usedBytes > $1.usedBytes }
    }

    var recentlyDeletedBytes: Int64 {
        trashedNotebookSnapshots.reduce(into: Int64(0)) { $0 += $1.usedBytes }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadSnapshots()
    }

    func refresh() async {
        infoMessage = nil
        deviceErrorMessage = nil
        notebookErrorMessage = nil
        await homeViewModel.loadNotebooks(userId: userId)
        await homeViewModel.refreshSyncSurface(userId: userId)
        await loadSnapshots()
    }

    func clearUnusedImages() async {
        guard !isClearingUnusedImages else { return }
        isClearingUnusedImages = true
        defer { isClearingUnusedImages = false }

        do {
            let clearedBytes = try await localDatabase.clearUnusedCanvasImages()
            ImageCache.shared.removeAll()
            await quotaService.invalidateCache()
            await homeViewModel.refreshQuotaStatus(userId: userId)
            await loadSnapshots()
            infoMessage = clearedBytes > 0
                ? "Freed \(ByteCountFormatter.string(fromByteCount: clearedBytes, countStyle: .file)) of unused local image files."
                : "No unused local image files were found."
        } catch {
            deviceErrorMessage = "Couldn't clear unused local image files right now."
        }
    }

    func emptyTrash() async {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }

        let trashedFolders = homeViewModel.filteredTrashFolders
        let folderIDs = Set(trashedFolders.map(\.id))
        let standaloneNotebooks = homeViewModel.filteredTrashNotebooks.filter { notebook in
            guard let folderId = notebook.folderId else { return true }
            return !folderIDs.contains(folderId)
        }

        for folder in trashedFolders {
            await homeViewModel.permanentlyDeleteFolder(folder)
        }
        for notebook in standaloneNotebooks {
            await homeViewModel.permanentlyDeleteNotebook(notebook)
        }

        await quotaService.invalidateCache()
        await homeViewModel.refreshQuotaStatus(userId: userId)
        await loadSnapshots()
        infoMessage = "Recently deleted items were removed from storage."
    }

    private func loadSnapshots() async {
        cloudStatus = await quotaService.status(for: userId)

        async let deviceResult = loadDeviceSnapshotResult()
        async let notebookResult = loadNotebookSnapshotResult()

        let resolvedDeviceResult = await deviceResult
        let resolvedNotebookResult = await notebookResult

        switch resolvedDeviceResult {
        case .success(let snapshot):
            deviceSnapshot = snapshot
            deviceErrorMessage = nil
        case .failure(let error):
            if error is CancellationError { break }
            deviceErrorMessage = "Couldn't load on-device storage details right now."
        }

        switch resolvedNotebookResult {
        case .success(let snapshots):
            notebookSnapshots = snapshots
            notebookErrorMessage = nil
        case .failure(let error):
            if error is CancellationError { break }
            notebookErrorMessage = "Couldn't load notebook storage details right now."
        }
    }

    private func loadDeviceSnapshotResult() async -> Result<DeviceStorageSnapshot, Error> {
        do {
            return .success(try await localDatabase.deviceStorageSnapshot())
        } catch {
            return .failure(error)
        }
    }

    private func loadNotebookSnapshotResult() async -> Result<[NotebookStorageBreakdownSnapshot], Error> {
        do {
            return .success(try await localDatabase.notebookStorageBreakdown(userId: userId))
        } catch {
            return .failure(error)
        }
    }
}

struct StorageManagementView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    let userId: UUID

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: StorageManagementViewModel
    @State private var showPricing = false
    @State private var isRetryingSync = false

    init(homeViewModel: HomeViewModel, userId: UUID) {
        self.homeViewModel = homeViewModel
        self.userId = userId
        _viewModel = StateObject(wrappedValue: StorageManagementViewModel(userId: userId, homeViewModel: homeViewModel))
    }

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            Color.gBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: GSpacing.xl) {
                        headerSection

                        if let info = viewModel.infoMessage, !info.isEmpty {
                            banner(title: "Storage", message: info, accent: .gPrimary)
                        }

                        syncSection
                        storageSummarySection
                        notebookBreakdownSection
                        recentlyDeletedSection
                        planFooter
                    }
                    .padding(.horizontal, isWideLayout ? GSpacing.xxxl : GSpacing.lg)
                    .padding(.vertical, GSpacing.xl)
                    .frame(maxWidth: 1280, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .fullScreenCover(isPresented: $showPricing) {
            PricingView(entryPoint: .storage)
        }
    }

    private var topBar: some View {
        HStack(spacing: GSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Storage")
                    .font(.gTitle3.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text("See what is using space and what to do next.")
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.gIconMedium.weight(.semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.gElevated.opacity(0.82)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isWideLayout ? GSpacing.xxxl : GSpacing.lg)
        .padding(.vertical, GSpacing.md)
        .background(
            Color.gBackground
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(Color.gBorder.opacity(0.35))
                }
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            Text("Storage is usually opened when something feels wrong.")
                .font(.custom("InstrumentSerif-Regular", size: isWideLayout ? 42 : 32))
                .foregroundColor(.gTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("This screen shows cloud quota, local device footprint, the largest notebooks, and the fastest ways to recover space.")
                .font(.gCallout)
                .foregroundColor(.gTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var storageSummarySection: some View {
        Group {
            if isWideLayout {
                HStack(alignment: .top, spacing: GSpacing.md) {
                    cloudCard
                    deviceCard
                }
            } else {
                VStack(spacing: GSpacing.md) {
                    cloudCard
                    deviceCard
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        switch authViewModel.syncMonitor.state {
        case .paused(let message):
            syncCard(
                title: "Sync paused",
                message: message,
                accent: .gWarning,
                buttonTitle: nil
            )
        case .error(let message):
            syncCard(
                title: "Sync error",
                message: message,
                accent: .gDestructive,
                buttonTitle: "Retry sync"
            )
        case .syncing:
            syncCard(
                title: "Syncing",
                message: authViewModel.syncMonitor.pendingCount > 0
                    ? "\(authViewModel.syncMonitor.pendingCount) changes are being uploaded."
                    : "Checking for new changes now.",
                accent: .gPrimary,
                buttonTitle: nil
            )
        case .idle:
            if authViewModel.syncMonitor.pendingCount > 0 {
                syncCard(
                    title: "Pending sync",
                    message: authViewModel.syncMonitor.pendingCount == 1
                        ? "1 change is still waiting to upload."
                        : "\(authViewModel.syncMonitor.pendingCount) changes are still waiting to upload.",
                    accent: .gWarning,
                    buttonTitle: "Retry sync"
                )
            }
        }
    }

    private var cloudCard: some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                HStack {
                    Text("In cloud")
                        .font(.gHeadline)
                        .foregroundColor(.gTextPrimary)
                    Spacer()
                    Text(viewModel.cloudStatus.limitText)
                        .font(.gCaption.weight(.semibold))
                        .foregroundColor(.gTextSecondary)
                }

                Text("\(viewModel.cloudStatus.usedText) of \(viewModel.cloudStatus.limitText)")
                    .font(.gTitle3.weight(.semibold))
                    .foregroundColor(.gTextPrimary)

                ProgressView(value: viewModel.cloudStatus.progress)
                    .tint(cloudTintColor)

                Text(viewModel.cloudStatus.statusMessage)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(GSpacing.lg)
        }
    }

    private var deviceCard: some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                HStack {
                    Text("On this device")
                        .font(.gHeadline)
                        .foregroundColor(.gTextPrimary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.deviceSnapshot.totalBytes, countStyle: .file))
                        .font(.gCaption.weight(.semibold))
                        .foregroundColor(.gTextSecondary)
                }

                deviceRow(title: "Database", bytes: viewModel.deviceSnapshot.databaseBytes)
                deviceRow(title: "Strokes", bytes: viewModel.deviceSnapshot.drawingBytes)
                deviceRow(title: "Images", bytes: viewModel.deviceSnapshot.imageBytes)

                if let deviceErrorMessage = viewModel.deviceErrorMessage, !deviceErrorMessage.isEmpty {
                    banner(title: "Device storage", message: deviceErrorMessage, accent: .gDestructive)
                }

                Button {
                    Task { await viewModel.clearUnusedImages() }
                } label: {
                    HStack {
                        Text(viewModel.deviceSnapshot.reclaimableImageBytes > 0
                             ? "Clear unused image files"
                             : "Check for unused image files")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gPrimary)
                        Spacer()
                        if viewModel.isClearingUnusedImages {
                            ProgressView()
                                .tint(.gPrimary)
                        } else {
                            Text(ByteCountFormatter.string(fromByteCount: viewModel.deviceSnapshot.reclaimableImageBytes, countStyle: .file))
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.gTextSecondary)
                        }
                    }
                    .padding(GSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(Color.gPrimaryMuted.opacity(0.7))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(GSpacing.lg)
        }
    }

    private func deviceRow(title: String, bytes: Int64) -> some View {
        HStack {
            Text(title)
                .font(.gSubheadline)
                .foregroundColor(.gTextSecondary)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.gSubheadline.weight(.semibold))
                .foregroundColor(.gTextPrimary)
        }
    }

    private var notebookBreakdownSection: some View {
        VStack(alignment: .leading, spacing: GSpacing.md) {
            Text("Largest notebooks")
                .font(.gTitle3.weight(.semibold))
                .foregroundColor(.gTextPrimary)

            legend

            if let notebookErrorMessage = viewModel.notebookErrorMessage, !notebookErrorMessage.isEmpty {
                banner(title: "Notebook storage", message: notebookErrorMessage, accent: .gDestructive)
            }

            ForEach(viewModel.activeNotebookSnapshots, id: \.notebook.id) { snapshot in
                notebookCard(snapshot)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: GSpacing.md) {
            legendItem(title: "Strokes", color: .gPrimary)
            legendItem(title: "Images", color: .gSecondary)
            legendItem(title: "Other", color: .gTextTertiary)
        }
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: GSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.gCaption)
                .foregroundColor(.gTextSecondary)
        }
    }

    private func notebookCard(_ snapshot: NotebookStorageBreakdownSnapshot) -> some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.notebook.name)
                            .font(.gHeadline)
                            .foregroundColor(.gTextPrimary)
                        Text(syncStatusText(for: snapshot))
                            .font(.gCaption.weight(.medium))
                            .foregroundColor(syncStatusColor(for: snapshot))
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: snapshot.usedBytes, countStyle: .file))
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                }

                NotebookStorageBar(snapshot: snapshot)
                    .frame(height: 14)

                HStack(spacing: GSpacing.md) {
                    notebookMetric(title: "Strokes", bytes: snapshot.drawingBytes)
                    notebookMetric(title: "Images", bytes: snapshot.imageBytes)
                    notebookMetric(title: "Other", bytes: snapshot.otherBytes)
                }
            }
            .padding(GSpacing.lg)
        }
    }

    private func notebookMetric(title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.gCaption)
                .foregroundColor(.gTextSecondary)
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.gSubheadline.weight(.semibold))
                .foregroundColor(.gTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentlyDeletedSection: some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recently deleted")
                            .font(.gHeadline)
                            .foregroundColor(.gTextPrimary)
                        Text(viewModel.trashedNotebookSnapshots.isEmpty
                             ? "Nothing is waiting in trash."
                             : "\(viewModel.trashedNotebookSnapshots.count) notebooks still count toward storage until they are emptied.")
                            .font(.gSubheadline)
                            .foregroundColor(.gTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.recentlyDeletedBytes, countStyle: .file))
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                }

                if !viewModel.trashedNotebookSnapshots.isEmpty {
                    ForEach(viewModel.trashedNotebookSnapshots.prefix(3), id: \.notebook.id) { snapshot in
                        HStack {
                            Text(snapshot.notebook.name)
                                .font(.gSubheadline)
                                .foregroundColor(.gTextPrimary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: snapshot.usedBytes, countStyle: .file))
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.gTextSecondary)
                        }
                    }

                    GButton(
                        title: "Empty trash",
                        style: .secondary,
                        isLoading: viewModel.isEmptyingTrash,
                        isDisabled: false
                    ) {
                        Task { await viewModel.emptyTrash() }
                    }
                }
            }
            .padding(GSpacing.lg)
        }
    }

    private var planFooter: some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                Text(authViewModel.subscriptionTier == .pro ? "GirokIQ Pro" : "GirokIQ Student")
                    .font(.gHeadline)
                    .foregroundColor(.gTextPrimary)

                Text(authViewModel.subscriptionTier == .pro
                     ? "You have \(AppSubscriptionTier.pro.storageLimitLabel) of cloud storage and higher AI limits."
                     : "You have \(AppSubscriptionTier.free.storageLimitLabel) of cloud storage. Upgrade if you need more headroom.")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                GButton(title: authViewModel.subscriptionTier == .pro ? "Manage subscription" : "Upgrade to Pro", style: .primary) {
                    Task {
                        if authViewModel.subscriptionTier == .pro {
                            await purchaseManager.openManageSubscriptions()
                        } else {
                            showPricing = true
                        }
                    }
                }
            }
            .padding(GSpacing.lg)
        }
    }

    private func banner(title: String, message: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text(message)
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gElevated.opacity(0.62))
        )
    }

    private func syncCard(title: String, message: String, accent: Color, buttonTitle: String?) -> some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                HStack(alignment: .top, spacing: GSpacing.sm) {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.gHeadline)
                            .foregroundColor(.gTextPrimary)
                        Text(message)
                            .font(.gSubheadline)
                            .foregroundColor(.gTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let buttonTitle {
                    GButton(title: buttonTitle, style: .secondary, isLoading: isRetryingSync, isDisabled: false) {
                        Task {
                            isRetryingSync = true
                            await authViewModel.syncMonitor.pushPending()
                            await viewModel.refresh()
                            isRetryingSync = false
                        }
                    }
                }
            }
            .padding(GSpacing.lg)
        }
    }

    private var cloudTintColor: Color {
        switch viewModel.cloudStatus.level {
        case .normal:
            return .gSuccess
        case .warning:
            return .gWarning
        case .critical, .full:
            return .gDestructive
        }
    }

    private func syncStatusText(for snapshot: NotebookStorageBreakdownSnapshot) -> String {
        if viewModel.cloudStatus.level == .full && snapshot.pendingChangeCount > 0 {
            return snapshot.pendingChangeCount == 1
                ? "Sync paused · 1 local change waiting"
                : "Sync paused · \(snapshot.pendingChangeCount) local changes waiting"
        }
        if snapshot.pendingChangeCount > 0 {
            return snapshot.pendingChangeCount == 1
                ? "Pending upload · 1 local change waiting"
                : "Pending upload · \(snapshot.pendingChangeCount) local changes waiting"
        }
        if let lastSyncedAt = snapshot.lastSyncedAt {
            return "Synced · \(RelativeDateTimeFormatter().localizedString(for: lastSyncedAt, relativeTo: Date()))"
        }
        return "Local only"
    }

    private func syncStatusColor(for snapshot: NotebookStorageBreakdownSnapshot) -> Color {
        if viewModel.cloudStatus.level == .full && snapshot.pendingChangeCount > 0 {
            return .gWarning
        }
        if snapshot.pendingChangeCount > 0 {
            return .gPrimary
        }
        if snapshot.lastSyncedAt != nil {
            return .gSuccess
        }
        return .gTextSecondary
    }
}

private struct NotebookStorageBar: View {
    let snapshot: NotebookStorageBreakdownSnapshot

    private var totalBytes: Double {
        max(Double(snapshot.usedBytes), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let drawingWidth = width * CGFloat(Double(snapshot.drawingBytes) / totalBytes)
            let imageWidth = width * CGFloat(Double(snapshot.imageBytes) / totalBytes)
            let otherWidth = max(width - drawingWidth - imageWidth, 0)

            HStack(spacing: 0) {
                Rectangle().fill(Color.gPrimary).frame(width: drawingWidth)
                Rectangle().fill(Color.gSecondary).frame(width: imageWidth)
                Rectangle().fill(Color.gTextTertiary.opacity(0.45)).frame(width: otherWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.gElevated.opacity(0.5))
            )
        }
    }
}
