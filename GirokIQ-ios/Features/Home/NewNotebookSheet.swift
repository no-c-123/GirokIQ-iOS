import SwiftUI

// MARK: - New Notebook Sheet

struct NewNotebookSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gBackground(for: colorScheme).ignoresSafeArea()

                VStack(spacing: GSpacing.xl) {
                    // Preview
                    ZStack {
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gPrimary, Color.gPrimary.opacity(0.7)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.gPrimary.opacity(0.4), radius: 16, y: 8)
                        Text(String(name.isEmpty ? "U" : name.prefix(1)).uppercased())
                            .font(.gEmojiLarge)
                            .foregroundColor(.white)
                    }
                    .padding(.top, GSpacing.xs)
                    .animation(GAnimation.springFast, value: name)

                    // Name
                    VStack(alignment: .leading, spacing: GSpacing.xs) {
                        Text("Name")
                            .font(.gCaption)
                            .foregroundColor(.gTextSecondary(for: colorScheme))
                        TextField("Notebook name", text: $name)
                            .font(.gCallout)
                            .foregroundColor(.gTextPrimary(for: colorScheme))
                            .padding(GSpacing.sm)
                            .background(Color.gElevated(for: colorScheme).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: GRadius.sm))
                    }
                    .padding(.horizontal, GSpacing.lg)

                    Spacer()
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gTextSecondary(for: colorScheme))
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Double tap to dismiss without creating")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            guard let userId = authViewModel.currentUserId else { return }
                            _ = await viewModel.createNotebook(
                                userId: userId,
                                name: name.isEmpty ? "Untitled" : name
                            )
                            dismiss()
                        }
                    }
                    .font(.gSubheadline.weight(.semibold))
                    .foregroundColor(.gPrimary)
                    .accessibilityLabel("Create notebook")
                    .accessibilityHint("Double tap to create \(name.isEmpty ? "an untitled" : name) notebook")
                }
            }
            .toolbarBackground(Color.gSurface(for: colorScheme), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
