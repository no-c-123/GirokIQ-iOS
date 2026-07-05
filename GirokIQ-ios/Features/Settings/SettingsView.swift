import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showEditDisplayName = false
    @State private var editedDisplayName = ""
    @State private var isUpdatingDisplayName = false
    @State private var displayNameErrorMessage: String?
    @State private var isForceBackfillRunning = false
    @State private var forceBackfillErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Account
                accountSection

                // MARK: - Appearance
                appearanceSection

                // MARK: - Canvas Defaults
                canvasSection

                // MARK: - AI Assistant
                aiSection

                if Configuration.cloudSyncEnabled {
                    syncSection
                }

                // MARK: - Data & Export
                dataSection

                // MARK: - About
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.gPrimary)
                }
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Edit Display Name", isPresented: $showEditDisplayName) {
                TextField("Display Name", text: $editedDisplayName)
                Button("Save") {
                    Task {
                        isUpdatingDisplayName = true
                        defer { isUpdatingDisplayName = false }

                        do {
                            try await authViewModel.updateDisplayName(editedDisplayName)
                        } catch {
                            displayNameErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose the name shown in your account and settings.")
            }
            .confirmationDialog("Delete Account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        defer { isDeletingAccount = false }

                        do {
                            try await authViewModel.deleteAccount()
                            dismiss()
                        } catch {
                            deleteAccountErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all notebooks, pages, strokes, elements, and chats. This action cannot be undone.")
            }
            .alert(
                "Couldn’t Delete Account",
                isPresented: Binding(
                    get: { deleteAccountErrorMessage != nil },
                    set: { if !$0 { deleteAccountErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountErrorMessage ?? "")
            }
            .alert(
                "Couldn’t Update Display Name",
                isPresented: Binding(
                    get: { displayNameErrorMessage != nil },
                    set: { if !$0 { displayNameErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(displayNameErrorMessage ?? "")
            }
            .alert(
                "Couldn’t Rebuild Cloud Backup",
                isPresented: Binding(
                    get: { forceBackfillErrorMessage != nil },
                    set: { if !$0 { forceBackfillErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(forceBackfillErrorMessage ?? "")
            }
        }
    }

    // MARK: - Account Section

    var accountSection: some View {
        Section {
            if let email = authViewModel.currentUserEmail {
                HStack(spacing: GSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.gPrimaryMuted)
                            .frame(width: 44, height: 44)
                        Text(authViewModel.displayName.prefix(1).uppercased())
                            .font(.gSubheadline.weight(.bold))
                            .foregroundColor(.gPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authViewModel.displayName)
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gTextPrimary)
                        Text(email)
                            .font(.gCaption)
                            .foregroundColor(.gTextSecondary)
                    }
                }
            }

            Button {
                editedDisplayName = authViewModel.displayName == authViewModel.currentUserEmail ? "" : authViewModel.displayName
                showEditDisplayName = true
            } label: {
                HStack {
                    Text("Display Name")
                    Spacer()
                    if isUpdatingDisplayName {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(authViewModel.displayName)
                            .foregroundColor(.gTextSecondary)
                    }
                }
            }
            .disabled(isUpdatingDisplayName || isDeletingAccount)
            .accessibilityLabel("Edit display name")
            .accessibilityHint("Double tap to change the display name shown on your account")

            if viewModel.canUseBiometrics {
                Toggle("\(viewModel.biometricName) Lock", isOn: $viewModel.biometricLockEnabled)
                    .accessibilityLabel("\(viewModel.biometricName) lock")
                    .accessibilityHint("Require \(viewModel.biometricName) to unlock the app")
            }

            Button("Sign Out", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            .disabled(isDeletingAccount)
            .accessibilityLabel("Sign out")
            .accessibilityHint("Double tap to sign out of your account")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                if isDeletingAccount {
                    Label("Deleting Account…", systemImage: "trash")
                } else {
                    Label("Delete Account", systemImage: "trash")
                }
            }
            .disabled(isDeletingAccount)
            .accessibilityLabel("Delete account")
            .accessibilityHint("Permanently delete your account and all synced data")
        } header: {
            Text("Account")
        } footer: {
            Text("Account deletion is permanent and removes all synced notebooks, pages, strokes, elements, and chats.")
        }
    }

    // MARK: - Appearance Section

    var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $viewModel.appearance) {
                ForEach(AppTheme.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Reduce Motion", isOn: $viewModel.reducedMotion)
                .accessibilityHint("Reduces animations throughout the app")
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Canvas Section

    var canvasSection: some View {
        Section {
            Picker("Default Background", selection: $viewModel.defaultBackground) {
                Text("Grid").tag("grid")
                Text("Dots").tag("dots")
                Text("Lines").tag("lines")
                Text("Blank").tag("blank")
                Text("Isometric").tag("isometric")
            }

            Toggle("Palm Rejection", isOn: $viewModel.palmRejection)
                .accessibilityHint("Ignore palm touches while drawing with Apple Pencil")
            Toggle("Finger Drawing", isOn: $viewModel.fingerDrawingEnabled)
                .accessibilityHint("Allow drawing with your finger in addition to Apple Pencil")

            HStack {
                Text("Default Stroke Width")
                Spacer()
                Text("\(viewModel.defaultStrokeWidth, specifier: "%.1f")pt")
                    .foregroundColor(.gTextSecondary)
            }
            Slider(value: $viewModel.defaultStrokeWidth, in: 0.5...20, step: 0.5)
                .tint(.gPrimary)
                .accessibilityLabel("Default stroke width")
                .accessibilityValue("\(viewModel.defaultStrokeWidth, specifier: "%.1f") points")
        } header: {
            Text("Canvas Defaults")
        }
    }

    // MARK: - AI Section

    var aiSection: some View {
        Section {
            Toggle("Enable AI Assistant", isOn: $viewModel.aiEnabled)
                .accessibilityHint("Show the AI assistant button on the canvas toolbar")

            Picker("Chat Panel Position", selection: $viewModel.aiPanelDockSide) {
                ForEach(AIChatPanelSide.allCases) { side in
                    Text(side.title).tag(side)
                }
            }

            HStack {
                Text("Status")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.aiAvailabilityStatus.tintColor)
                        .frame(width: 7, height: 7)
                    Text(viewModel.aiAvailabilityStatus.title)
                        .font(.gCaption)
                        .foregroundColor(.gTextSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI status: \(viewModel.aiAvailabilityStatus.title)")
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("AI requests are sent through the signed-in app server proxy. No model API key is stored in the app bundle.")
        }
    }

    // MARK: - Sync Section

    var syncSection: some View {
        Section {
            Toggle("Auto Sync", isOn: $viewModel.autoSync)
                .accessibilityHint("Automatically push pending changes to cloud in the background")

            Toggle("Sync on Wi-Fi Only", isOn: $viewModel.syncOnWiFiOnly)
                .accessibilityHint("Restrict automatic cloud sync to Wi-Fi connections")

            Button {
                Task {
                    isForceBackfillRunning = true
                    defer { isForceBackfillRunning = false }

                    do {
                        try await authViewModel.forceCloudBackfill()
                    } catch {
                        forceBackfillErrorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if isForceBackfillRunning {
                        Label("Rebuilding Cloud Backup…", systemImage: "arrow.clockwise.icloud")
                    } else {
                        Label("Rebuild Cloud Backup", systemImage: "arrow.clockwise.icloud")
                    }
                    Spacer()
                    if isForceBackfillRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isForceBackfillRunning || isDeletingAccount || authViewModel.currentUserId == nil)
            .accessibilityHint("Re-enqueue all local content for upload after a remote reset or migration")

            if let status = authViewModel.backfillStatusMessage, !status.isEmpty {
                Text(status)
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Use Rebuild Cloud Backup after resetting Supabase tables or when you need to re-upload the full local library without reinstalling the app.")
        }
    }

    // MARK: - Data Section

    var dataSection: some View {
        Section {
            Button {
                Task {
                    if let userId = authViewModel.currentUserId {
                        exportURL = await viewModel.exportAllData(userId: userId)
                        if exportURL != nil { showExportShare = true }
                    }
                }
            } label: {
                Label("Export All Data", systemImage: "square.and.arrow.up")
            }
            .accessibilityHint("Double tap to export all notebooks as an archive")
        } header: {
            Text("Data")
        }
    }

    // MARK: - About Section

    var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.gTextSecondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundColor(.gTextSecondary)
            }
            Link("Privacy Policy", destination: URL(string: "https://girokiq.app/privacy")!)
                .foregroundColor(.gPrimary)
            Link("Terms of Service", destination: URL(string: "https://girokiq.app/terms")!)
                .foregroundColor(.gPrimary)
        } header: {
            Text("About")
        } footer: {
            Text("GirokIQ — Think on canvas.")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, GSpacing.md)
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad: UIActivityViewController is presented as a popover and requires an anchor.
        // Without this, presenting from a sheet/navigation stack can crash.
        if let popover = controller.popoverPresentationController {
            let anchorView = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })
            popover.sourceView = anchorView
            popover.sourceRect = CGRect(
                x: anchorView?.bounds.midX ?? 0,
                y: anchorView?.bounds.midY ?? 0,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
