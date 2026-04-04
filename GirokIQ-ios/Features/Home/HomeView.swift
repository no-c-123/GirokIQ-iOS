import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager

    /// Shared ViewModel — either owned internally or provided externally (iPad split view)
    @ObservedObject var viewModel: HomeViewModel

    /// External notebook selection binding (iPad detail coordination)
    @Binding var selectedNotebook: Notebook?

    /// Whether this view is embedded in a NavigationSplitView (skips wrapping in NavigationStack)
    var isEmbedded: Bool = false

    @State private var showNewNotebookSheet = false
    @State private var showUserMenu = false
    @State private var showSearch = false
    @State private var notebookToRename: Notebook?
    @State private var renameText = ""
    @State private var showSettings = false
    @State private var showSidebarPanel = false

    /// Adaptive columns: fits as many as possible with 150pt minimum
    private var columns: [GridItem] {
        if viewModel.viewMode == .list {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: GSpacing.md)]
    }

    var body: some View {
        let content = ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                homeToolbar

                // Inline search bar
                if showSearch {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Content
                if viewModel.isLoading || authViewModel.isSyncing {
                    skeletonGrid
                } else if viewModel.displayedNotebooks.isEmpty {
                    emptyState
                } else {
                    notebookContent
                }
            }
        }
        .task {
            if let userId = authViewModel.currentUserId, viewModel.notebooks.isEmpty {
                await viewModel.loadNotebooks(userId: userId)
            }
        }
        .sheet(isPresented: $showNewNotebookSheet) {
            NewNotebookSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Rename Notebook", isPresented: Binding(
            get: { notebookToRename != nil },
            set: { if !$0 { notebookToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let notebook = notebookToRename {
                    Task { await viewModel.renameNotebook(notebook, to: renameText) }
                }
                notebookToRename = nil
            }
            Button("Cancel", role: .cancel) { notebookToRename = nil }
        }

        // Wrap content with optional sidebar overlay panel
        let mainContent = ZStack(alignment: .leading) {
            content

            // Dimming backdrop
            if showSidebarPanel {
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
            if showSidebarPanel {
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
                            selectedNotebook = newValue
                            animateMotionSafe {
                                showSidebarPanel = false
                            }
                        }
                    ),
                    showSettings: $showSettings,
                    onClose: {
                        animateMotionSafe {
                            showSidebarPanel = false
                        }
                    }
                )
                .frame(width: 280)
                .transition(.move(edge: .leading))
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

    // MARK: - Toolbar

    var homeToolbar: some View {
        HStack(spacing: GSpacing.sm) {
            // Sidebar toggle
            Button {
                animateMotionSafe {
                    showSidebarPanel.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .toolbarIconStyle(active: showSidebarPanel)
            }
            .minTapTarget()
            .accessibilityLabel("Library")
            .accessibilityHint(showSidebarPanel ? "Double tap to hide library panel" : "Double tap to show library panel")

            // App logo
            HStack(spacing: GSpacing.xs) {
                Image(systemName: "pencil.and.outline")
                    .font(.gIconLarge.weight(.semibold))
                    .foregroundColor(.gPrimary)
                Text("GirokIQ")
                    .font(.gTitle3.weight(.bold))
                    .foregroundColor(themeManager.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GirokIQ")

            Spacer()

            // Search toggle
            Button {
                animateMotionSafe(GAnimation.springFast) {
                    showSearch.toggle()
                    if !showSearch { viewModel.searchText = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .toolbarIconStyle(active: showSearch)
            }
            .minTapTarget()
            .accessibilityLabel("Search")
            .accessibilityHint(showSearch ? "Double tap to close search" : "Double tap to search notebooks")

            // Grid/List toggle
            Button {
                animateMotionSafe(GAnimation.springFast) {
                    viewModel.viewMode = viewModel.viewMode == .grid ? .list : .grid
                }
            } label: {
                Image(systemName: viewModel.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .toolbarIconStyle()
            }
            .minTapTarget()
            .accessibilityLabel(viewModel.viewMode == .grid ? "Switch to list view" : "Switch to grid view")
            .accessibilityHint("Double tap to change layout")

            // New notebook
            Button {
                showNewNotebookSheet = true
            } label: {
                Image(systemName: "plus")
                    .toolbarIconStyle(primary: true)
            }
            .minTapTarget()
            .accessibilityLabel("Create new notebook")
            .accessibilityHint("Double tap to open the new notebook dialog")
            .keyboardShortcut("n", modifiers: .command)

            // Avatar / user
            Button {
                showUserMenu = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.gPrimaryMuted)
                        .frame(width: 32, height: 32)
                    Text(authViewModel.displayName.prefix(1).uppercased())
                        .font(.gFootnote.weight(.bold))
                        .foregroundColor(.gPrimary)
                }
            }
            .minTapTarget()
            .accessibilityLabel("Account menu for \(authViewModel.displayName)")
            .accessibilityHint("Double tap for settings and sign out")
            .confirmationDialog("Account", isPresented: $showUserMenu) {
                Button("Settings") { showSettings = true }
                Button("Sign Out", role: .destructive) {
                    Task { await authViewModel.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.horizontal, GSpacing.lg)
        .padding(.vertical, GSpacing.md)
        .background(themeManager.surfaceColor)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }

    // MARK: - Search Bar

    var searchBar: some View {
        HStack(spacing: GSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.gIconSmall)
                .foregroundColor(.gTextTertiary)
            TextField("Search notebooks…", text: $viewModel.searchText)
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
        .clipShape(RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous))
        .padding(.horizontal, GSpacing.lg)
        .padding(.vertical, GSpacing.xs)
    }

    // MARK: - Notebook Content (folders + grid)

    var notebookContent: some View {
        ScrollView {
            LazyVStack(spacing: GSpacing.md) {
                // Folder sections (hidden when sidebar drives folder selection)
                ForEach(viewModel.displayedFolders) { folder in
                    FolderRow(
                        folder: folder,
                        isExpanded: viewModel.expandedFolderIds.contains(folder.id),
                        notebooks: viewModel.notebooksInFolder(folder.id),
                        viewMode: viewModel.viewMode,
                        columns: columns,
                        onToggle: { viewModel.toggleFolder(folder.id) },
                        onSelectNotebook: { selectedNotebook = $0 },
                        onContextAction: { handleContextAction($0, notebook: $1) }
                    )
                }

                // Notebooks grid
                if !viewModel.displayedUnfolderedNotebooks.isEmpty {
                    if !viewModel.displayedFolders.isEmpty {
                        HStack {
                            Text("Notebooks")
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(.gTextTertiary)
                                .textCase(.uppercase)
                                .tracking(0.4)
                            Spacer()
                        }
                        .padding(.horizontal, GSpacing.lg)
                    }

                    LazyVGrid(columns: columns, spacing: GSpacing.md) {
                        ForEach(viewModel.displayedUnfolderedNotebooks) { notebook in
                            NotebookCard(
                                notebook: notebook,
                                viewMode: viewModel.viewMode
                            ) {
                                selectedNotebook = notebook
                            }
                            .contextMenu { notebookContextMenu(for: notebook) }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, GSpacing.lg)
                    .animation(GAnimation.spring, value: viewModel.displayedNotebooks.count)
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
        VStack(spacing: GSpacing.lg) {
            Spacer()
            Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gTextTertiary)

            if viewModel.searchText.isEmpty {
                Text("No Notebooks Yet")
                    .font(.gTitle3.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text("Tap + to create your first notebook\nand start thinking on canvas.")
                    .font(.gSubheadline)
                    .foregroundColor(.gTextSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    showNewNotebookSheet = true
                } label: {
                    Text("Create Notebook")
                        .font(.gCallout.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, GSpacing.xl)
                        .padding(.vertical, GSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                .fill(Color.gPrimary)
                        )
                }
                .minTapTarget()
                .accessibilityLabel("Create notebook")
                .accessibilityHint("Double tap to create your first notebook")
            } else {
                Text("No Results")
                    .font(.gTitle3.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text("No notebooks match \"\(viewModel.searchText)\"")
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

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.deleteNotebook(notebook) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Context Action Handler

    private func handleContextAction(_ action: NotebookContextAction, notebook: Notebook) {
        switch action {
        case .rename:
            renameText = notebook.name
            notebookToRename = notebook
        case .delete:
            Task { await viewModel.deleteNotebook(notebook) }
        case .moveToFolder(let folderId):
            Task { await viewModel.moveNotebookToFolder(notebook, folderId: folderId) }
        }
    }
}

// MARK: - Notebook Context Action

enum NotebookContextAction {
    case rename
    case delete
    case moveToFolder(UUID?)
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

    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            Button(action: onToggle) {
                HStack(spacing: GSpacing.sm) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.gIconMedium)
                        .foregroundColor(.gPrimary)
                    Text(folder.name)
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                    Text("\(notebooks.count)")
                        .font(.gCaption)
                        .foregroundColor(.gTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gElevated))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(.gTextTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(GAnimation.springFast, value: isExpanded)
                }
                .padding(.horizontal, GSpacing.lg)
                .padding(.vertical, GSpacing.sm)
            }

            // Expanded content
            if isExpanded && !notebooks.isEmpty {
                LazyVGrid(columns: columns, spacing: GSpacing.md) {
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, GSpacing.lg)
                .padding(.bottom, GSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(GAnimation.spring, value: isExpanded)
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
    var onClose: () -> Void

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.gTitle3.weight(.bold))
                    .foregroundColor(.gTextPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.gIconSmall.weight(.medium))
                        .foregroundColor(.gTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.gElevated))
                }
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.top, GSpacing.lg)
            .padding(.bottom, GSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: GSpacing.lg) {
                    // All Notebooks
                    sidebarButton(
                        icon: "book.closed",
                        label: "All Notebooks",
                        isActive: selectedFolderId == nil
                    ) {
                        selectedFolderId = nil
                    }

                    // Folders
                    if !viewModel.folders.isEmpty {
                        sectionHeader("Folders")

                        ForEach(viewModel.folders) { folder in
                            sidebarButton(
                                icon: selectedFolderId == folder.id ? "folder.fill" : "folder",
                                label: folder.name,
                                isActive: selectedFolderId == folder.id,
                                badge: "\(viewModel.notebooksInFolder(folder.id).count)"
                            ) {
                                selectedFolderId = folder.id
                            }
                        }
                    }

                    // Recents
                    if !viewModel.recentNotebooks.isEmpty {
                        sectionHeader("Recent")

                        ForEach(viewModel.recentNotebooks) { notebook in
                            Button {
                                selectedNotebook = notebook
                            } label: {
                                HStack(spacing: GSpacing.sm) {
                                    recentIcon(for: notebook)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(notebook.name)
                                            .font(.gSubheadline)
                                            .foregroundColor(.gTextPrimary)
                                            .lineLimit(1)
                                        Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                                            .font(.gCaption2)
                                            .foregroundColor(.gTextTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, GSpacing.md)
                                .padding(.vertical, GSpacing.xs)
                            }
                        }
                    }

                    Divider().opacity(0.3).padding(.horizontal, GSpacing.md)

                    // Actions
                    sidebarButton(icon: "folder.badge.plus", label: "New Folder", tint: .gPrimary) {
                        showNewFolderAlert = true
                    }

                    sidebarButton(icon: "gearshape", label: "Settings") {
                        showSettings = true
                        onClose()
                    }
                }
                .padding(.bottom, GSpacing.xl)
            }
        }
        .background(Color.gSurface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: GRadius.lg,
                topTrailingRadius: GRadius.lg
            )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 4, y: 0)
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let userId = authViewModel.currentUserId, !newFolderName.isEmpty {
                    Task { await viewModel.createFolder(userId: userId, name: newFolderName) }
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
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
                        .foregroundColor(.gTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gElevated))
                }
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.vertical, GSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .fill(isActive ? Color.gPrimaryMuted : .clear)
                    .padding(.horizontal, GSpacing.xs)
            )
        }
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
