import Combine
import SwiftUI
internal import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("homeSidebarVisible") private var homeSidebarVisible = true

    /// Shared ViewModel — either owned internally or provided externally (iPad split view)
    @ObservedObject var viewModel: HomeViewModel

    /// External notebook selection binding (iPad detail coordination)
    @Binding var selectedNotebook: Notebook?

    /// Whether this view is embedded in a NavigationSplitView (skips wrapping in NavigationStack)
    var isEmbedded: Bool = false

    @State private var showNewNotebookSheet = false
    @State private var notebookToRename: Notebook?
    @State private var renameText = ""
    @State private var showSettings = false
    @State private var showSidebarPanel = false
    @State private var showNotebookImporter = false
    @State private var archiveDocument = ExportedBinaryDocument(data: Data())
    @State private var archiveContentType: UTType = .girokIQNotebook
    @State private var archiveDefaultFilename = "Notebook.girokiq"
    @State private var showArchiveExporter = false
    @State private var didAttemptLaunchRestore = false
    
    // Folder Creation & Management
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: Folder?
    @State private var renameFolderText = ""
    @State private var notebookPendingTrash: Notebook?
    @State private var folderPendingTrash: Folder?

    /// Adaptive columns: fits as many as possible with 150pt minimum
    private var columns: [GridItem] {
        if viewModel.viewMode == .list {
            return [GridItem(.flexible())]
        }
        // Use an adaptive layout so the portrait cards don't grow to fill the screen
        return [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: GSpacing.md)]
    }

    private var recentColumns: [GridItem] {
        // Larger cards so the cover feels tappable and the action menu doesn't dwarf it.
        let minimum = horizontalSizeClass == .compact ? 140.0 : 160.0
        let maximum = horizontalSizeClass == .compact ? 200.0 : 220.0
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: GSpacing.md)]
    }

    private var folderColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: GSpacing.md)]
    }

    private var headerTitle: String {
        viewModel.selectedSection == .trash ? "Trash" : "Home"
    }

    private var headerSubtitle: String {
        if viewModel.selectedSection == .trash {
            return "Recently deleted notebooks and folders"
        }
        return "Pick up where you left off"
    }

    private var notebooksSectionTitle: String {
        guard let selectedFolderId = viewModel.selectedFolderId,
              let folder = viewModel.folders.first(where: { $0.id == selectedFolderId }) else {
            return "All Notebooks"
        }
        return folder.name.isEmpty ? "Folder" : folder.name
    }

    private var notebooksSectionSubtitle: String {
        viewModel.selectedFolderId == nil ? "Your full notebook library" : "Notebooks in this folder"
    }

    private var showsInlineSidebar: Bool {
        horizontalSizeClass == .regular && homeSidebarVisible
    }

    private func openNotebook(_ notebook: Notebook) {
        viewModel.selectedSection = .library
        viewModel.markNotebookOpened(notebook)
        selectedNotebook = notebook
    }

    var body: some View {
        let content = VStack(spacing: 0) {
            homeToolbar

            // Content
            if (viewModel.isLoading && viewModel.notebooks.isEmpty) || (authViewModel.isSyncing && viewModel.notebooks.isEmpty) {
                skeletonGrid
            } else if isCurrentViewEmpty {
                emptyState
            } else {
                currentContent
            }
        }
        .background(Color.gBackground)
        .onOpenURL { url in
            // Support share-sheet / Files "Open in GirokIQ" for notebook and folder archives.
            guard let userId = authViewModel.currentUserId else { return }
            let supportedExtensions = ["girokiq", "girokfolder"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
            Task { await viewModel.importArchive(from: url, userId: userId) }
        }
        .task {
            if let userId = authViewModel.currentUserId {
                if viewModel.notebooks.isEmpty {
                    await viewModel.loadNotebooks(userId: userId)
                }
                if !didAttemptLaunchRestore, selectedNotebook == nil {
                    didAttemptLaunchRestore = true
                    if let notebook = viewModel.lastOpenedNotebook() {
                        selectedNotebook = notebook
                    }
                }
            }
        }
        .onReceive(authViewModel.syncMonitor.$pendingCount.removeDuplicates()) { _ in
            Task {
                await viewModel.refreshSyncSurface(userId: authViewModel.currentUserId)
            }
        }
        .onReceive(authViewModel.syncMonitor.$state.removeDuplicates()) { _ in
            Task {
                await viewModel.refreshSyncSurface(userId: authViewModel.currentUserId)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let userId = authViewModel.currentUserId else { return }
            Task {
                await viewModel.loadNotebooks(userId: userId)
            }
        }
        .fullScreenCover(isPresented: $showNewNotebookSheet) {
            NewNotebookSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fileExporter(
            isPresented: $showArchiveExporter,
            document: archiveDocument,
            contentType: archiveContentType,
            defaultFilename: archiveDefaultFilename
        ) { _ in }
        .fileImporter(
            isPresented: $showNotebookImporter,
            allowedContentTypes: [.girokIQNotebook, .girokIQFolder, .data],
            allowsMultipleSelection: false
        ) { result in
            guard let userId = authViewModel.currentUserId else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel.importArchive(from: url, userId: userId) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert("Rename Notebook", isPresented: Binding(
            get: { notebookToRename != nil },
            set: { if !$0 { notebookToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let notebook = notebookToRename {
                    let nameToSave = renameText
                    Task { await viewModel.renameNotebook(notebook, to: nameToSave) }
                }
                notebookToRename = nil
                renameText = ""
            }
            Button("Cancel", role: .cancel) { 
                notebookToRename = nil
                renameText = ""
            }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let userId = authViewModel.currentUserId, !newFolderName.isEmpty {
                    let nameToSave = newFolderName
                    newFolderName = ""
                    Task { await viewModel.createFolder(userId: userId, name: nameToSave) }
                } else {
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameFolderText)
            Button("Rename") {
                if let folder = folderToRename {
                    let nameToSave = renameFolderText
                    Task { await viewModel.renameFolder(folder, to: nameToSave) }
                }
                folderToRename = nil
                renameFolderText = ""
            }
            Button("Cancel", role: .cancel) { 
                folderToRename = nil
                renameFolderText = ""
            }
        }
        .alert("Stored Locally", isPresented: Binding(
            get: { viewModel.quotaNoticeMessage != nil },
            set: { if !$0 { viewModel.quotaNoticeMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.quotaNoticeMessage = nil
            }
        } message: {
            Text(viewModel.quotaNoticeMessage ?? "")
        }
        .confirmationDialog(
            "Move Notebook to Trash?",
            isPresented: Binding(
                get: { notebookPendingTrash != nil },
                set: { if !$0 { notebookPendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let notebook = notebookPendingTrash {
                    Task { await viewModel.moveNotebookToTrash(notebook) }
                }
                notebookPendingTrash = nil
            }
            Button("Cancel", role: .cancel) {
                notebookPendingTrash = nil
            }
        } message: {
            Text("This notebook will move to Trash and stay there for 2 weeks before it is permanently deleted. You can also delete it immediately from Trash.")
        }
        .confirmationDialog(
            "Move Folder to Trash?",
            isPresented: Binding(
                get: { folderPendingTrash != nil },
                set: { if !$0 { folderPendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let folder = folderPendingTrash {
                    Task { await viewModel.moveFolderToTrash(folder) }
                }
                folderPendingTrash = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingTrash = nil
            }
        } message: {
            Text("This folder and its notebooks will move to Trash and stay there for 2 weeks before they are permanently deleted. You can also delete them immediately from Trash.")
        }

        // Wrap content with optional sidebar
        let mainContent = ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                if showsInlineSidebar {
                    SidebarPanelView(
                        viewModel: viewModel,
                        selectedFolderId: Binding(
                            get: { viewModel.selectedFolderId },
                            set: { viewModel.selectedFolderId = $0 }
                        ),
                        selectedNotebook: Binding(
                            get: { selectedNotebook },
                            set: { newValue in
                                if let notebook = newValue {
                                    viewModel.markNotebookOpened(notebook)
                                }
                                selectedNotebook = newValue
                            }
                        ),
                        showSettings: $showSettings,
                        isPersistent: true,
                        onClose: { homeSidebarVisible = false },
                        onNewNotebook: { showNewNotebookSheet = true },
                        onImportNotebook: { showNotebookImporter = true },
                        onNewFolder: { showNewFolderAlert = true },
                        onFolderContextAction: { handleFolderContextAction($0, folder: $1) }
                    )
                    .frame(width: 280)
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color.gBackground.ignoresSafeArea())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Dimming backdrop
            if !showsInlineSidebar && showSidebarPanel {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        animateMotionSafe {
                            showSidebarPanel = false
                        }
                    }
                    .accessibilityLabel("Close library panel")
                    .accessibilityAddTraits(.isButton)
            }

            // Sliding sidebar panel
            if !showsInlineSidebar && showSidebarPanel {
                SidebarPanelView(
                    viewModel: viewModel,
                    selectedFolderId: Binding(
                        get: { viewModel.selectedFolderId },
                        set: { newValue in
                            viewModel.selectedFolderId = newValue
                            animateMotionSafe {
                                showSidebarPanel = false
                            }
                        }
                    ),
                    selectedNotebook: Binding(
                        get: { selectedNotebook },
                        set: { newValue in
                            if let notebook = newValue {
                                viewModel.markNotebookOpened(notebook)
                            }
                            selectedNotebook = newValue
                            animateMotionSafe {
                                showSidebarPanel = false
                            }
                        }
                    ),
                    showSettings: $showSettings,
                    isPersistent: false,
                    onClose: {
                        animateMotionSafe {
                            showSidebarPanel = false
                        }
                    },
                    onNewNotebook: { showNewNotebookSheet = true },
                    onImportNotebook: { showNotebookImporter = true },
                    onNewFolder: { showNewFolderAlert = true },
                    onFolderContextAction: { handleFolderContextAction($0, folder: $1) }
                )
                .frame(width: 280)
                .transition(.move(edge: .leading))
            }

            if viewModel.isImporting {
                ZStack {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()

                    VStack(spacing: GSpacing.md) {
                        ProgressView()
                            .scaleEffect(1.05)
                            .tint(.gPrimary)

                        Text("Importing archive…")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gTextPrimary)

                        if let name = viewModel.importingNotebookName, !name.isEmpty {
                            Text(name)
                                .font(.gCaption)
                                .foregroundColor(.gTextSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(Color.gSurface.opacity(0.96))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
                    )
                }
                .transition(.opacity)
                .zIndex(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Importing archive")
            }
        }
        .animation(GAnimation.motionSafe(), value: showSidebarPanel)

        // On iPhone (not embedded), wrap in NavigationStack with push to canvas
        if isEmbedded {
            mainContent
        } else {
            NavigationStack {
                mainContent
                    .navigationDestination(item: $selectedNotebook) { notebook in
                        CanvasContainerView(notebook: notebook)
                    }
            }
        }
    }

    private var currentContent: some View {
        Group {
            if viewModel.selectedSection == .trash {
                trashContent
            } else {
                notebookContent
            }
        }
    }

    private var isCurrentViewEmpty: Bool {
        if viewModel.selectedSection == .trash {
            return viewModel.filteredTrashFolders.isEmpty && viewModel.filteredTrashNotebooks.isEmpty
        }
        return viewModel.displayedNotebooks.isEmpty && viewModel.displayedFolders.isEmpty
    }

    // MARK: - Toolbar

    var homeToolbar: some View {
        HStack(spacing: GSpacing.sm) {
            Button {
                if horizontalSizeClass == .regular {
                    homeSidebarVisible.toggle()
                } else {
                    animateMotionSafe {
                        showSidebarPanel.toggle()
                    }
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .toolbarIconStyle(active: showsInlineSidebar || showSidebarPanel)
            }
            .minTapTarget()
            .accessibilityLabel("Library")
            .accessibilityHint((showsInlineSidebar || showSidebarPanel) ? "Double tap to hide library panel" : "Double tap to show library panel")

            Text(headerTitle)
                .font(.custom("InstrumentSerif-Regular", size: 28))
                .foregroundColor(.gTextPrimary)

            Spacer()

            toolbarSearchField
        }
        .padding(.horizontal, GSpacing.lg)
        .padding(.vertical, GSpacing.md)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }

    var toolbarSearchField: some View {
        HStack(spacing: GSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.gIconSmall)
                .foregroundColor(.gTextTertiary)
            TextField(viewModel.selectedSection == .trash ? "Search trash…" : "Search notebooks and folders…", text: $viewModel.searchText)
                .font(.gSubheadline)
                .foregroundColor(.gTextPrimary)
                .textFieldStyle(.plain)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.gIconSmall)
                        .foregroundColor(.gTextTertiary)
                }
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, GSpacing.sm)
        .background(Color.gElevated)
        .clipShape(RoundedRectangle(cornerRadius: GRadius.md, style: .continuous))
        .frame(width: horizontalSizeClass == .compact ? 220 : 360)
    }

    // MARK: - Notebook Content (folders + grid)

    var notebookContent: some View {
        ScrollView {
            LazyVStack(spacing: GSpacing.lg) {
                if Configuration.cloudSyncEnabled {
                    StorageUsageCard(
                        usage: viewModel.storageUsage,
                        breakdown: viewModel.storageBreakdown
                    )
                        .padding(.horizontal, GSpacing.lg)
                }

                // 1. Recent
                if !viewModel.recentNotebooks.isEmpty && viewModel.selectedFolderId == nil {
                    HomeSectionCard(title: "Continue", subtitle: "Pick up where you left off") {
                        LazyVGrid(columns: recentColumns, alignment: .leading, spacing: GSpacing.md) {
                            ForEach(viewModel.recentNotebooks) { notebook in
                                ZStack(alignment: .topTrailing) {
                                    RecentNotebookCard(notebook: notebook) {
                                        openNotebook(notebook)
                                    }
                                    .contextMenu { notebookContextMenu(for: notebook) }

                                    notebookActionMenu(for: notebook, buttonSize: 32)
                                        .padding(8)
                                }
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, GSpacing.lg)
                }

                // 2. Folders
                if !viewModel.displayedFolders.isEmpty {
                    HomeSectionCard(
                        title: "Folders",
                        subtitle: "Organize notebooks by area",
                        trailing: {
                            Button("New Folder") {
                                showNewFolderAlert = true
                            }
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextPrimary)
                            .padding(.horizontal, GSpacing.sm)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                Capsule()
                                    .fill(Color.gElevated.opacity(0.78))
                            )
                            .contentShape(Rectangle())
                        }
                    ) {
                        LazyVGrid(columns: folderColumns, alignment: .leading, spacing: GSpacing.md) {
                            ForEach(viewModel.displayedFolders) { folder in
                                FolderSummaryCard(
                                    folder: folder,
                                    notebookCount: viewModel.notebooksInFolder(folder.id).count
                                ) {
                                    viewModel.selectedSection = .library
                                    viewModel.selectedFolderId = folder.id
                                }
                                .contextMenu {
                                    Button {
                                        handleFolderContextAction(.rename, folder: folder)
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button {
                                        handleFolderContextAction(.export, folder: folder)
                                    } label: {
                                        Label("Export Folder", systemImage: "square.and.arrow.up")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        handleFolderContextAction(.delete, folder: folder)
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash")
                                    }
                                }
                                .overlay(alignment: .trailing) {
                                    VStack {
                                        Spacer(minLength: 0)
                                        folderActionMenu(for: folder, buttonSize: 36)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.trailing, 8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, GSpacing.lg)
                }

                // 3. My Notebooks
                if !viewModel.displayedUnfolderedNotebooks.isEmpty {
                    HomeSectionCard(
                        title: notebooksSectionTitle,
                        subtitle: notebooksSectionSubtitle,
                        trailing: {
                            HStack(spacing: GSpacing.xs) {
                                Button {
                                    animateMotionSafe(GAnimation.springFast) {
                                        viewModel.viewMode = .grid
                                    }
                                } label: {
                                    Text("Grid")
                                        .font(.gCaption.weight(.semibold))
                                        .foregroundColor(viewModel.viewMode == .grid ? .gTextPrimary : .gTextSecondary)
                                        .padding(.horizontal, GSpacing.sm)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            Capsule()
                                                .fill(viewModel.viewMode == .grid ? Color.gElevated : .clear)
                                        )
                                        .contentShape(Rectangle())
                                }

                                Button {
                                    animateMotionSafe(GAnimation.springFast) {
                                        viewModel.viewMode = .list
                                    }
                                } label: {
                                    Text("List")
                                        .font(.gCaption.weight(.semibold))
                                        .foregroundColor(viewModel.viewMode == .list ? .gTextPrimary : .gTextSecondary)
                                        .padding(.horizontal, GSpacing.sm)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            Capsule()
                                                .fill(viewModel.viewMode == .list ? Color.gElevated : .clear)
                                        )
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(4)
                            .background(
                                Capsule()
                                    .fill(Color.gBackground.opacity(0.8))
                            )
                        }
                    ) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: GSpacing.md) {
                            ForEach(viewModel.displayedUnfolderedNotebooks) { notebook in
                                ZStack(alignment: .bottomTrailing) {
                                    NotebookCard(
                                        notebook: notebook,
                                        viewMode: viewModel.viewMode
                                    ) {
                                        openNotebook(notebook)
                                    }
                                    .contextMenu { notebookContextMenu(for: notebook) }

                                    notebookActionMenu(for: notebook, buttonSize: 36)
                                        .padding(8)
                                }
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, GSpacing.lg)
                    .animation(GAnimation.spring, value: viewModel.displayedNotebooks.count)
                }
            }
            .padding(.vertical, GSpacing.md)
        }
    }

    var trashContent: some View {
        ScrollView {
            LazyVStack(spacing: GSpacing.md) {
                if !viewModel.filteredTrashFolders.isEmpty {
                    SectionHeaderView(title: "Trash Folders")
                    ForEach(viewModel.filteredTrashFolders) { folder in
                        TrashFolderRow(
                            folder: folder,
                            isExpanded: viewModel.expandedFolderIds.contains(folder.id),
                            notebooks: viewModel.trashedNotebooksInFolder(folder.id),
                            viewMode: viewModel.viewMode,
                            columns: columns,
                            onToggle: { viewModel.toggleFolder(folder.id) },
                            onRestoreFolder: { Task { await viewModel.restoreFolder(folder) } },
                            onDeleteFolderPermanently: { Task { await viewModel.permanentlyDeleteFolder(folder) } },
                            onRestoreNotebook: { notebook in
                                Task { await viewModel.restoreNotebook(notebook) }
                            },
                            onDeleteNotebookPermanently: { notebook in
                                Task { await viewModel.permanentlyDeleteNotebook(notebook) }
                            }
                        )
                    }
                }

                if !viewModel.filteredTrashNotebooks.isEmpty {
                    SectionHeaderView(title: "Trash Notebooks")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: GSpacing.md) {
                        ForEach(viewModel.filteredTrashNotebooks) { notebook in
                            TrashNotebookCard(
                                notebook: notebook,
                                viewMode: viewModel.viewMode,
                                onRestore: { Task { await viewModel.restoreNotebook(notebook) } },
                                onDeletePermanently: { Task { await viewModel.permanentlyDeleteNotebook(notebook) } }
                            )
                            .contextMenu { trashNotebookContextMenu(for: notebook) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GSpacing.lg)
                }
            }
            .padding(.vertical, GSpacing.md)
        }
    }

    // MARK: - Skeleton Grid

    var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: GSpacing.md) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonNotebookCard()
                }
            }
            .padding(GSpacing.lg)
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: GSpacing.xl) {
            Spacer()
            
            if viewModel.searchText.isEmpty, let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(.gPrimary)

                Text("Couldn’t load notebooks")
                    .font(.custom("InstrumentSerif-Regular", size: 26))
                    .foregroundColor(.gTextPrimary)

                Text(error)
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, GSpacing.xl)

                Button {
                    guard let userId = authViewModel.currentUserId else { return }
                    Task { await viewModel.loadNotebooks(userId: userId) }
                } label: {
                    Text("Try Again")
                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, GSpacing.xl)
                        .padding(.vertical, GSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(Color.gPrimary)
                        )
                }
                .minTapTarget()
                .accessibilityLabel("Retry notebook loading")
                .accessibilityHint("Double tap to try loading your notebooks again")
            } else if viewModel.searchText.isEmpty {
                if viewModel.selectedSection == .trash {
                    Image(systemName: "trash")
                        .font(.system(size: 42, weight: .light))
                        .foregroundColor(.gPrimary)

                    Text("Trash is empty")
                        .font(.custom("InstrumentSerif-Regular", size: 26))
                        .foregroundColor(.gTextPrimary)

                    Text("Items moved here stay for 2 weeks before being permanently deleted.")
                        .font(.gSubheadline)
                        .foregroundColor(.gTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, GSpacing.xl)
                } else {
                    // Minimal line art illustration
                    ZStack {
                        Circle()
                            .fill(Color.gPrimaryMuted)
                            .frame(width: 80, height: 80)
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.gPrimary)
                    }

                    Text("Start your first notebook")
                        .font(.custom("InstrumentSerif-Regular", size: 26))
                        .foregroundColor(.gTextPrimary)

                    Button {
                        showNewNotebookSheet = true
                    } label: {
                        Text("New Notebook")
                            .font(.custom("PlusJakartaSans-Medium", size: 16))
                            .foregroundColor(.white)
                            .padding(.horizontal, GSpacing.xl)
                            .padding(.vertical, GSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                    .fill(Color.gPrimary)
                            )
                    }
                    .minTapTarget()
                    .accessibilityLabel("Create new notebook")
                    .accessibilityHint("Double tap to create your first notebook")
                }
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.gTextTertiary)
                Text("No Results")
                    .font(.gTitle3.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text(viewModel.selectedSection == .trash ? "No trash items match \"\(viewModel.searchText)\"" : "No notebooks or folders match \"\(viewModel.searchText)\"")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    func notebookContextMenu(for notebook: Notebook) -> some View {
        Button {
            renameText = notebook.name
            notebookToRename = notebook
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        if !viewModel.folders.isEmpty {
            Menu("Move to Folder") {
                ForEach(viewModel.folders) { folder in
                    Button(folder.name) {
                        Task { await viewModel.moveNotebookToFolder(notebook, folderId: folder.id) }
                    }
                }
                if notebook.folderId != nil {
                    Button("Remove from Folder") {
                        Task { await viewModel.moveNotebookToFolder(notebook, folderId: nil) }
                    }
                }
            }
        }

        Button {
            Task {
                await exportNotebookArchive(notebook)
            }
        } label: {
            Label("Export Notebook", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            notebookPendingTrash = notebook
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func exportNotebookArchive(_ notebook: Notebook) async {
        guard let url = await viewModel.exportNotebookArchive(notebook),
              let data = try? Data(contentsOf: url) else { return }

        let safeName = notebook.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        archiveContentType = .girokIQNotebook
        archiveDocument = ExportedBinaryDocument(data: data)
        archiveDefaultFilename = "\(safeName).girokiq"
        showArchiveExporter = true
    }

    private func exportFolderArchive(_ folder: Folder) async {
        guard let url = await viewModel.exportFolderArchive(folder),
              let data = try? Data(contentsOf: url) else { return }

        let safeName = folder.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        archiveContentType = .girokIQFolder
        archiveDocument = ExportedBinaryDocument(data: data)
        archiveDefaultFilename = "\(safeName.isEmpty ? "Folder" : safeName).girokfolder"
        showArchiveExporter = true
    }

    @ViewBuilder
    func trashNotebookContextMenu(for notebook: Notebook) -> some View {
        Button {
            Task { await viewModel.restoreNotebook(notebook) }
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.permanentlyDeleteNotebook(notebook) }
        } label: {
            Label("Delete Permanently", systemImage: "trash.fill")
        }
    }

    // MARK: - Context Action Handler

    private func handleContextAction(_ action: NotebookContextAction, notebook: Notebook) {
        switch action {
        case .rename:
            renameText = notebook.name
            notebookToRename = notebook
        case .delete:
            notebookPendingTrash = notebook
        case .moveToFolder(let folderId):
            Task { await viewModel.moveNotebookToFolder(notebook, folderId: folderId) }
        }
    }

    private func handleFolderContextAction(_ action: FolderContextAction, folder: Folder) {
        switch action {
        case .rename:
            renameFolderText = folder.name
            folderToRename = folder
        case .export:
            Task { await exportFolderArchive(folder) }
        case .delete:
            folderPendingTrash = folder
        }
    }

    // MARK: - Action menus (no long press)

    private func notebookActionMenu(for notebook: Notebook, buttonSize: CGFloat) -> some View {
        Menu {
            Button {
                renameText = notebook.name
                notebookToRename = notebook
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if !viewModel.folders.isEmpty {
                Menu("Move to Folder") {
                    ForEach(viewModel.folders) { folder in
                        Button(folder.name) {
                            Task { await viewModel.moveNotebookToFolder(notebook, folderId: folder.id) }
                        }
                    }
                    if notebook.folderId != nil {
                        Button("Remove from Folder") {
                            Task { await viewModel.moveNotebookToFolder(notebook, folderId: nil) }
                        }
                    }
                }
            }

            Button {
                Task { await exportNotebookArchive(notebook) }
            } label: {
                Label("Export Notebook", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                notebookPendingTrash = notebook
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gTextSecondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Color.gSurface.opacity(0.92)))
                .overlay(Circle().stroke(Color.gBorder.opacity(0.5), lineWidth: 0.5))
                .contentShape(Circle())
                .minTapTarget()
                .accessibilityLabel("Notebook actions")
        }
        .buttonStyle(.plain)
    }

    private func folderActionMenu(for folder: Folder, buttonSize: CGFloat) -> some View {
        Menu {
            Button {
                renameFolderText = folder.name
                folderToRename = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                Task { await exportFolderArchive(folder) }
            } label: {
                Label("Export Folder", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                folderPendingTrash = folder
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gTextSecondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Color.gSurface.opacity(0.92)))
                .overlay(Circle().stroke(Color.gBorder.opacity(0.5), lineWidth: 0.5))
                .contentShape(Circle())
                .minTapTarget()
                .accessibilityLabel("Folder actions")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notebook Context Action

enum NotebookContextAction {
    case rename
    case delete
    case moveToFolder(UUID?)
}

// MARK: - Folder Context Action

enum FolderContextAction {
    case rename
    case export
    case delete
}

// MARK: - Section Header View

struct SectionHeaderView: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 13))
                    .foregroundColor(.gTextSecondary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.gCaption)
                        .foregroundColor(.gTextTertiary)
                }
            }

            Rectangle()
                .fill(Color.gBorder.opacity(0.5))
                .frame(height: 1)
                .offset(y: subtitle == nil ? 0 : 8)
        }
        .padding(.horizontal, GSpacing.lg)
        .padding(.vertical, GSpacing.xs)
    }
}

struct HomeSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)

        VStack(alignment: .leading, spacing: GSpacing.md) {
            HStack(alignment: .top, spacing: GSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                    }
                }

                Spacer(minLength: GSpacing.md)
                trailing
            }

            content
        }
        .padding(GSpacing.md)
        .background(
            shape
                .fill(Color.gSurface.opacity(0.94))
                .background(
                    .ultraThinMaterial,
                    in: shape
                )
        )
        .overlay(
            shape
                .stroke(Color.gBorder.opacity(0.7), lineWidth: 0.75)
        )
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
    }
}

extension HomeSectionCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

private struct StorageUsageCard: View {
    let usage: HomeViewModel.StorageUsage
    let breakdown: [HomeViewModel.NotebookStorageBreakdownItem]

    @State private var isExpanded = false
    @State private var showsAllItems = false

    private var displayedBreakdown: [HomeViewModel.NotebookStorageBreakdownItem] {
        showsAllItems ? breakdown : Array(breakdown.prefix(6))
    }

    private var accentColor: Color {
        switch usage.level {
        case .full:
            return .red
        case .critical:
            return .orange
        case .warning:
            return Color(hex: "#D9A441")
        default:
            return .gPrimary
        }
    }

    private var percentText: String {
        "\(Int((usage.progress * 100).rounded()))%"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)

        VStack(alignment: .leading, spacing: GSpacing.sm) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        showsAllItems = false
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: GSpacing.sm) {
                    HStack(spacing: GSpacing.sm) {
                        Label("Storage", systemImage: "externaldrive")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gTextPrimary)

                        Spacer(minLength: GSpacing.sm)

                        Text("\(usage.usedText) / 1 GB")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextSecondary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gElevated.opacity(0.85))

                            Capsule()
                                .fill(accentColor)
                                .frame(width: usage.progress == 0 ? 0 : max(10, proxy.size.width * usage.progress))
                        }
                    }
                    .frame(height: 8)

                    HStack(spacing: GSpacing.sm) {
                        Text(usage.statusMessage)
                            .font(.gCaption)
                            .foregroundColor(usage.level == .normal ? .gTextTertiary : accentColor)

                        Spacer(minLength: GSpacing.sm)

                        Text(percentText)
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(accentColor)
                    }

                    HStack(spacing: GSpacing.xs) {
                        Text("\(breakdown.count) \(breakdown.count == 1 ? "notebook" : "notebooks")")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                        Spacer(minLength: GSpacing.sm)
                        Text(isExpanded ? "Hide notebooks" : "Show notebooks")
                            .font(.gCaption.weight(.medium))
                            .foregroundColor(.gTextSecondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: GSpacing.sm) {
                    Divider()
                        .overlay(Color.gBorder.opacity(0.5))

                    Text("Notebooks")
                        .font(.gCaption.weight(.semibold))
                        .foregroundColor(.gTextSecondary)

                    if displayedBreakdown.isEmpty {
                        Text("Add notebook content to see how much space each notebook is taking.")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                    } else {
                        ForEach(displayedBreakdown) { item in
                            NotebookStorageBreakdownRow(item: item)
                        }

                        if breakdown.count > 6 {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                                    showsAllItems.toggle()
                                }
                            } label: {
                                Text(showsAllItems ? "Show less" : "Show all \(breakdown.count) notebooks")
                                    .font(.gCaption.weight(.semibold))
                                    .foregroundColor(.gPrimary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, GSpacing.md)
        .background(
            shape
                .fill(Color.gSurface.opacity(0.94))
                .background(.ultraThinMaterial, in: shape)
        )
        .overlay(
            shape.stroke(Color.gBorder.opacity(0.7), lineWidth: 0.75)
        )
        .clipShape(shape)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage used \(usage.usedText) out of 1 gigabyte. \(usage.statusMessage)")
    }
}

private struct NotebookStorageBreakdownRow: View {
    let item: HomeViewModel.NotebookStorageBreakdownItem

    private var syncLabel: String {
        switch item.syncState {
        case .synced:
            return "Synced"
        case .pending:
            return "Pending sync"
        case .localOnly:
            return "Local only"
        case .neverSynced:
            return "Never synced"
        }
    }

    private var syncColor: Color {
        switch item.syncState {
        case .synced:
            return Color(hex: "#6FB5A5")
        case .pending:
            return Color(hex: "#D9A441")
        case .localOnly:
            return .orange
        case .neverSynced:
            return .gTextTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: GSpacing.sm) {
                Text(item.notebook.name.isEmpty ? "Untitled" : item.notebook.name)
                    .font(.gSubheadline.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                    .lineLimit(1)

                Spacer(minLength: GSpacing.sm)

                Text(item.usedText)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gTextSecondary)
            }

            HStack(spacing: GSpacing.sm) {
                Text(item.quotaShareText)
                    .font(.gCaption)
                    .foregroundColor(.gTextTertiary)

                Spacer(minLength: GSpacing.sm)

                Text(syncLabel)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(syncColor)
            }
        }
        .padding(.horizontal, GSpacing.md)
        .padding(.vertical, GSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gElevated.opacity(0.6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.notebook.name), \(item.usedText), \(syncLabel)")
    }
}

struct FolderSummaryCard: View {
    let folder: Folder
    let notebookCount: Int
    let onTap: () -> Void

    private var accentColor: Color {
        let colors: [Color] = [.gPrimary, Color(hex: "#7F9FD9"), Color(hex: "#6FB5A5"), Color(hex: "#B49CE6")]
        return colors[abs(folder.id.hashValue) % colors.count]
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: GSpacing.sm) {
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.gIconMedium)
                            .foregroundColor(accentColor)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name.isEmpty ? "Unnamed Folder" : folder.name)
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                        .lineLimit(1)

                    Text("\(notebookCount) \(notebookCount == 1 ? "notebook" : "notebooks")")
                        .font(.gCaption)
                        .foregroundColor(.gTextSecondary)
                }

                Spacer(minLength: GSpacing.sm)
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.vertical, GSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                    .fill(Color.gElevated.opacity(0.65))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.name), \(notebookCount) notebooks")
        .accessibilityHint("Double tap to open this folder")
    }
}

struct RecentNotebookCard: View {
    let notebook: Notebook
    let onTap: () -> Void

    private var pattern: BackgroundPattern {
        BackgroundPattern(rawValue: notebook.backgroundPattern) ?? .blank
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: GSpacing.xs) {
                NotebookLiveCoverPreview(
                    title: notebook.name,
                    pattern: pattern,
                    backgroundColorHex: notebook.backgroundColorHex,
                    cornerRadius: GRadius.md,
                    showsShadow: false
                )
                .aspectRatio(0.74, contentMode: .fit)
                .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 6)

                VStack(spacing: 2) {
                    Text(notebook.name)
                        .font(.gFootnote.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notebook.name)
        .accessibilityHint("Double tap to open notebook")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Folder Row (Accordion)

struct FolderRow: View {
    let folder: Folder
    let isExpanded: Bool
    let notebooks: [Notebook]
    let viewMode: HomeViewModel.ViewMode
    let columns: [GridItem]
    let onToggle: () -> Void
    let onSelectNotebook: (Notebook) -> Void
    let onContextAction: (NotebookContextAction, Notebook) -> Void
    let onFolderContextAction: (FolderContextAction, Folder) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            Button(action: onToggle) {
                HStack(spacing: GSpacing.sm) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.gIconMedium)
                        .foregroundColor(isExpanded ? .gPrimary : .gTextSecondary)
                    
                    Text(folder.name.isEmpty ? "Unnamed Folder" : folder.name)
                        .font(.custom("PlusJakartaSans-Medium", size: 15))
                        .foregroundColor(.gTextPrimary)
                    
                    if !isExpanded {
                        Text("\(notebooks.count)")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gElevated))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(.gTextTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(GAnimation.springFast, value: isExpanded)
                }
                .padding(.horizontal, GSpacing.lg)
                .padding(.vertical, GSpacing.sm)
                .contentShape(Rectangle())
            }
            .contextMenu {
                Button {
                    onFolderContextAction(.rename, folder)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    onFolderContextAction(.export, folder)
                } label: {
                    Label("Export Folder", systemImage: "square.and.arrow.up")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onFolderContextAction(.delete, folder)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }

            // Expanded content
            if isExpanded && !notebooks.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: GSpacing.md) {
                    ForEach(notebooks) { notebook in
                        NotebookCard(
                            notebook: notebook,
                            viewMode: viewMode
                        ) {
                            onSelectNotebook(notebook)
                        }
                        .contextMenu {
                            Button {
                                onContextAction(.rename, notebook)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                onContextAction(.moveToFolder(nil), notebook)
                            } label: {
                                Label("Remove from Folder", systemImage: "folder.badge.minus")
                            }
                            Divider()
                            Button(role: .destructive) {
                                onContextAction(.delete, notebook)
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GSpacing.lg)
                .padding(.bottom, GSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(GAnimation.spring, value: isExpanded)
    }
}

struct TrashFolderRow: View {
    let folder: Folder
    let isExpanded: Bool
    let notebooks: [Notebook]
    let viewMode: HomeViewModel.ViewMode
    let columns: [GridItem]
    let onToggle: () -> Void
    let onRestoreFolder: () -> Void
    let onDeleteFolderPermanently: () -> Void
    let onRestoreNotebook: (Notebook) -> Void
    let onDeleteNotebookPermanently: (Notebook) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: GSpacing.sm) {
                    Image(systemName: isExpanded ? "folder.fill.badge.minus" : "folder.badge.minus")
                        .font(.gIconMedium)
                        .foregroundColor(.gPrimary)

                    Text(folder.name.isEmpty ? "Unnamed Folder" : folder.name)
                        .font(.custom("PlusJakartaSans-Medium", size: 15))
                        .foregroundColor(.gTextPrimary)

                    Spacer()

                    Text("Deletes in 2 weeks")
                        .font(.gCaption2)
                        .foregroundColor(.gTextTertiary)

                    Image(systemName: "chevron.right")
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(.gTextTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(GAnimation.springFast, value: isExpanded)
                }
                .padding(.horizontal, GSpacing.lg)
                .padding(.vertical, GSpacing.sm)
                .contentShape(Rectangle())
            }
            .contextMenu {
                Button(action: onRestoreFolder) {
                    Label("Restore Folder", systemImage: "arrow.uturn.backward")
                }
                Divider()
                Button(role: .destructive, action: onDeleteFolderPermanently) {
                    Label("Delete Permanently", systemImage: "trash.fill")
                }
            }

            if isExpanded && !notebooks.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: GSpacing.md) {
                    ForEach(notebooks) { notebook in
                        TrashNotebookCard(
                            notebook: notebook,
                            viewMode: viewMode,
                            onRestore: { onRestoreNotebook(notebook) },
                            onDeletePermanently: { onDeleteNotebookPermanently(notebook) }
                        )
                        .contextMenu {
                            Button {
                                onRestoreNotebook(notebook)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            Divider()
                            Button(role: .destructive) {
                                onDeleteNotebookPermanently(notebook)
                            } label: {
                                Label("Delete Permanently", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GSpacing.lg)
                .padding(.bottom, GSpacing.md)
            }
        }
        .animation(GAnimation.spring, value: isExpanded)
    }
}

struct TrashNotebookCard: View {
    let notebook: Notebook
    let viewMode: HomeViewModel.ViewMode
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GSpacing.sm) {
            NotebookCard(
                notebook: notebook,
                viewMode: viewMode,
                onTap: {}
            )
            .allowsHitTesting(false)

            HStack(spacing: GSpacing.sm) {
                Button(action: onRestore) {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.gCaption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onDeletePermanently) {
                    Label("Delete", systemImage: "trash.fill")
                        .font(.gCaption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Toolbar Icon Style

extension Image {
    func toolbarIconStyle(primary: Bool = false, active: Bool = false) -> some View {
        self
            .font(.gIconMedium)
            .foregroundColor(primary ? .white : active ? .gPrimary : .gTextSecondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(primary ? Color.gPrimary : active ? Color.gPrimaryMuted : Color.gElevated.opacity(0.5))
            )
            .contentShape(Circle())
    }
}

// MARK: - Skeleton Notebook Card

struct SkeletonNotebookCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gElevated.opacity(0.5))
                .frame(height: 110)

            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.gElevated.opacity(0.5))
                    .frame(width: 80, height: 12)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.gElevated.opacity(0.3))
                    .frame(width: 50, height: 10)
            }
            .padding(.horizontal, GSpacing.xxs)
            .padding(.vertical, GSpacing.xs)
        }
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                        .stroke(Color.gBorder, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.md, style: .continuous))
        .shimmer()
    }
}

// MARK: - Sidebar Panel (Overlay)

/// A slide-in panel showing folders, recent notebooks, and actions.
/// Overlays on top of the Home content — not a system sidebar.
struct SidebarPanelView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var selectedFolderId: UUID?
    @Binding var selectedNotebook: Notebook?
    @Binding var showSettings: Bool
    var isPersistent: Bool = false
    var onClose: () -> Void
    var onNewNotebook: () -> Void = {}
    var onImportNotebook: () -> Void = {}
    var onNewFolder: () -> Void = {}
    var onFolderContextAction: ((FolderContextAction, Folder) -> Void)?

    @EnvironmentObject var authViewModel: AuthViewModel

    private var activeFolders: [Folder] {
        viewModel.folders.filter { $0.trashedAt == nil }
    }

    private var sidebarTitle: String {
        authViewModel.displayName.isEmpty ? "Workspace" : authViewModel.displayName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GSpacing.lg) {
                HStack(spacing: GSpacing.sm) {
                    Image("SidebarLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GirokIQ")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gTextPrimary)
                        Text("Notebook Library")
                            .font(.gCaption)
                            .foregroundColor(.gTextTertiary)
                    }

                    Spacer()

                    if !isPersistent {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.gIconSmall.weight(.semibold))
                                .foregroundColor(.gTextSecondary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.gElevated.opacity(0.75)))
                        }
                        .accessibilityLabel("Close sidebar")
                    }
                }

                Button(action: {}) {
                    HStack(spacing: GSpacing.sm) {
                        Circle()
                            .fill(Color.gPrimary.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Text(authViewModel.displayName.prefix(1).uppercased())
                                    .font(.gFootnote.weight(.bold))
                                    .foregroundColor(.black.opacity(0.75))
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sidebarTitle)
                                .font(.gSubheadline.weight(.semibold))
                                .foregroundColor(.gTextPrimary)
                                .lineLimit(1)
                            Text("Notebook workspace")
                                .font(.gCaption)
                                .foregroundColor(.gTextTertiary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, GSpacing.md)
                    .padding(.vertical, GSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(Color.gElevated.opacity(0.72))
                    )
                }
                .buttonStyle(.plain)

                VStack(spacing: GSpacing.sm) {
                    Button(action: onNewNotebook) {
                        Label("New Notebook", systemImage: "plus")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.black.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                    .fill(Color.gPrimary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onImportNotebook) {
                        Label("Import Archive", systemImage: "square.and.arrow.down.on.square")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                    .fill(Color.gElevated.opacity(0.72))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onNewFolder) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                    .fill(Color.gElevated.opacity(0.72))
                            )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: GSpacing.xs) {
                    sectionHeader("Library")

                    sidebarButton(
                        icon: "house",
                        label: "Home",
                        isActive: viewModel.selectedSection == .library && selectedFolderId == nil
                    ) {
                        viewModel.selectedSection = .library
                        selectedFolderId = nil
                        if !isPersistent { onClose() }
                    }

                    sidebarButton(
                        icon: "trash",
                        label: "Trash",
                        isActive: viewModel.selectedSection == .trash
                    ) {
                        viewModel.selectedSection = .trash
                        selectedFolderId = nil
                        if !isPersistent { onClose() }
                    }
                }

                if !activeFolders.isEmpty {
                    VStack(alignment: .leading, spacing: GSpacing.xs) {
                        HStack {
                            sectionHeader("Folders")
                            Spacer()
                        }

                        ForEach(activeFolders) { folder in
                            sidebarButton(
                                icon: selectedFolderId == folder.id ? "folder.fill" : "folder",
                                label: folder.name.isEmpty ? "Unnamed Folder" : folder.name,
                                isActive: viewModel.selectedSection == .library && selectedFolderId == folder.id,
                                tint: sidebarAccent(for: folder),
                                badge: "\(viewModel.notebooksInFolder(folder.id).count)"
                            ) {
                                viewModel.selectedSection = .library
                                selectedFolderId = folder.id
                                if !isPersistent { onClose() }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    onFolderContextAction?(.rename, folder)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gPrimary)

                                Button {
                                    onFolderContextAction?(.export, folder)
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .tint(Color(hex: "#6FB5A5"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onFolderContextAction?(.delete, folder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    onFolderContextAction?(.rename, folder)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    onFolderContextAction?(.export, folder)
                                } label: {
                                    Label("Export Folder", systemImage: "square.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    onFolderContextAction?(.delete, folder)
                                } label: {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: GSpacing.sm) {
                    HStack {
                        Text("Library")
                            .font(.gCaption.weight(.semibold))
                            .foregroundColor(.gTextSecondary)
                        Spacer()
                        Text("\(viewModel.activeNotebooks.count) notebooks")
                            .font(.gCaption2)
                            .foregroundColor(.gTextTertiary)
                    }

                    HStack(spacing: GSpacing.sm) {
                        sidebarStatPill(title: "Folders", value: "\(activeFolders.count)")
                        sidebarStatPill(title: "Recent", value: "\(viewModel.recentNotebooks.count)")
                    }
                }
                .padding(GSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                        .fill(Color.gElevated.opacity(0.72))
                )

                VStack(spacing: GSpacing.xs) {
                    Button {
                        showSettings = true
                        if !isPersistent { onClose() }
                    } label: {
                        HStack(spacing: GSpacing.sm) {
                            Image(systemName: "gearshape")
                                .font(.gIconMedium)
                                .foregroundColor(.gTextSecondary)
                                .frame(width: 24)
                            Text("Settings")
                                .font(.gSubheadline.weight(.semibold))
                                .foregroundColor(.gTextPrimary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .padding(.horizontal, GSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                                .fill(Color.gElevated.opacity(0.5))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await authViewModel.signOut() }
                    } label: {
                        HStack(spacing: GSpacing.sm) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.gIconMedium)
                                .foregroundColor(.gTextSecondary)
                                .frame(width: 24)
                            Text("Sign Out")
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.gTextSecondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .padding(.horizontal, GSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GSpacing.md)
            .padding(.bottom, GSpacing.md)
            .safeAreaPadding(.top, isPersistent ? GSpacing.md : GSpacing.md)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Group {
                if isPersistent {
                    Color.gBackground
                } else {
                    UnevenRoundedRectangle(
                        topLeadingRadius: GRadius.xl,
                        bottomLeadingRadius: GRadius.xl,
                        bottomTrailingRadius: GRadius.xl,
                        topTrailingRadius: GRadius.xl
                    )
                    .fill(Color.gSurface.opacity(0.96))
                    .background(
                        .ultraThinMaterial,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: GRadius.xl,
                            bottomLeadingRadius: GRadius.xl,
                            bottomTrailingRadius: GRadius.xl,
                            topTrailingRadius: GRadius.xl
                        )
                    )
                }
            }
        )
        .overlay(alignment: .trailing) {
            if isPersistent {
                Rectangle()
                    .fill(Color.gBorder.opacity(0.6))
                    .frame(width: 0.75)
            }
        }
        .shadow(color: .black.opacity(isPersistent ? 0 : 0.28), radius: 20, x: 4, y: 0)
    }

    // MARK: - Sidebar Button

    private func sidebarButton(
        icon: String,
        label: String,
        isActive: Bool = false,
        tint: Color? = nil,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: GSpacing.sm) {
                Image(systemName: icon)
                    .font(.gIconMedium)
                    .foregroundColor(tint ?? (isActive ? .gPrimary : .gTextSecondary))
                    .frame(width: 24)
                Text(label)
                    .font(.gSubheadline.weight(isActive ? .semibold : .regular))
                    .foregroundColor(tint ?? (isActive ? .gPrimary : .gTextPrimary))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.gCaption2)
                        .foregroundColor(isActive ? .gPrimary : .gTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isActive ? Color.gPrimaryMuted : Color.gElevated))
                }
            }
            .padding(.horizontal, GSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                    .fill(isActive ? Color.gPrimaryMuted : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.gCaption.weight(.semibold))
            .foregroundColor(.gTextTertiary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.horizontal, GSpacing.md)
    }

    private func sidebarStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.gCaption2)
                .foregroundColor(.gTextTertiary)
            Text(value)
                .font(.gCaption.weight(.semibold))
                .foregroundColor(.gTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GSpacing.sm)
        .padding(.vertical, GSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gSurface.opacity(0.5))
        )
    }

    private func sidebarAccent(for folder: Folder) -> Color {
        let colors: [Color] = [.gPrimary, Color(hex: "#7F9FD9"), Color(hex: "#6FB5A5"), Color(hex: "#B49CE6")]
        return colors[abs(folder.id.hashValue) % colors.count]
    }

    // MARK: - Recent Notebook Icon

    private func recentIcon(for notebook: Notebook) -> some View {
        let colors: [Color] = [.gPrimary, Color(hex: "#8B5CF6"), Color(hex: "#06B6D4"), Color(hex: "#10B981"), Color(hex: "#F59E0B"), Color(hex: "#EC4899")]
        let color = colors[abs(notebook.id.hashValue) % colors.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 28, height: 28)
            Text(String(notebook.name.prefix(1)).uppercased())
                .font(.gCaption.weight(.bold))
                .foregroundColor(color)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var vm = HomeViewModel()
        @State private var selected: Notebook?
        var body: some View {
            HomeView(viewModel: vm, selectedNotebook: $selected)
                .environmentObject(AuthViewModel())
                .environmentObject(ThemeManager())
                .environmentObject(AppDependencies())
        }
    }
    return PreviewWrapper()
}
