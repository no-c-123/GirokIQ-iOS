import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false

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
                            .foregroundColor(.gTextPrimary(for: colorScheme))
                        Text(email)
                            .font(.gCaption)
                            .foregroundColor(.gTextSecondary(for: colorScheme))
                    }
                }
            }

            if viewModel.canUseBiometrics {
                Toggle("\(viewModel.biometricName) Lock", isOn: $viewModel.biometricLockEnabled)
                    .accessibilityLabel("\(viewModel.biometricName) lock")
                    .accessibilityHint("Require \(viewModel.biometricName) to unlock the app")
            }

            Button("Sign Out", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            .accessibilityLabel("Sign out")
            .accessibilityHint("Double tap to sign out of your account")
        } header: {
            Text("Account")
        }
    }

    // MARK: - Appearance Section

    var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $viewModel.appearance) {
                ForEach(SettingsViewModel.AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
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
                    .foregroundColor(.gTextSecondary(for: colorScheme))
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

            if viewModel.hasAPIKey {
                HStack {
                    Text("API Key")
                    Spacer()
                    Text("••••••••")
                        .foregroundColor(.gTextSecondary(for: colorScheme))
                }
                Button("Remove API Key", role: .destructive) {
                    viewModel.removeAPIKey()
                }
                .accessibilityHint("Double tap to remove the stored API key")
            } else {
                HStack {
                    SecureField("Anthropic API Key", text: $viewModel.apiKeyText)
                        .textFieldStyle(.plain)
                        .font(.gSubheadline)
                        .accessibilityLabel("API key input")
                        .accessibilityHint("Enter your Anthropic API key")
                    Button("Save") {
                        viewModel.saveAPIKey()
                    }
                    .disabled(viewModel.apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(.gPrimary)
                    .accessibilityLabel("Save API key")
                    .accessibilityHint("Double tap to save the entered API key to Keychain")
                }
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Your API key is stored securely in the Keychain and never leaves this device.")
        }
    }

    // MARK: - Data Section

    var dataSection: some View {
        Section {
            Toggle("Auto Sync", isOn: $viewModel.autoSync)
                .accessibilityHint("Automatically sync notebooks to the cloud")
            Toggle("Wi-Fi Only", isOn: $viewModel.syncOnWiFiOnly)
                .accessibilityHint("Only sync when connected to Wi-Fi")

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
            Text("Data & Sync")
        }
    }

    // MARK: - About Section

    var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.gTextSecondary(for: colorScheme))
            }
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundColor(.gTextSecondary(for: colorScheme))
            }
            Link("Privacy Policy", destination: URL(string: "https://girokiq.com/privacy")!)
                .foregroundColor(.gPrimary)
            Link("Terms of Service", destination: URL(string: "https://girokiq.com/terms")!)
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
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
