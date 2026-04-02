import SwiftUI

// MARK: - Notebook Card

struct NotebookCard: View {
    let notebook: Notebook
    let viewMode: HomeViewModel.ViewMode
    let onTap: () -> Void

    @State private var isPressed = false

    /// Generate a consistent accent color from the notebook's ID
    private var accentColor: Color {
        let colors: [Color] = [.gPrimary, Color(hex: "#8B5CF6"), Color(hex: "#06B6D4"), Color(hex: "#10B981"), Color(hex: "#F59E0B"), Color(hex: "#EC4899")]
        let index = abs(notebook.id.hashValue) % colors.count
        return colors[index]
    }

    /// First letter of the notebook name as a visual icon
    private var initial: String {
        String(notebook.name.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            if viewMode == .grid {
                gridCard
            } else {
                listCard
            }
        }
        .buttonStyle(GScaleButtonStyle())
        .accessibilityLabel(notebook.name)
        .accessibilityHint("Double tap to open notebook")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Grid Card

    var gridCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                    }
                }
                .padding(GSpacing.md)

                Text(initial)
                    .font(.gEmojiMedium)
                    .foregroundColor(.white)
            }
            .frame(height: 110)

            VStack(alignment: .leading, spacing: 3) {
                Text(notebook.name)
                    .font(.gFootnote.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                    .lineLimit(1)

                Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.gCaption2)
                    .foregroundColor(.gTextTertiary)
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
    }

    // MARK: - List Card

    var listCard: some View {
        HStack(spacing: GSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(accentColor.opacity(0.3))
                    .frame(width: 44, height: 44)
                Text(initial)
                    .font(.gSubheadline.weight(.bold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.gSubheadline.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
                Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.gCaption)
                    .foregroundColor(.gTextTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.gCaption.weight(.medium))
                .foregroundColor(.gTextTertiary)
        }
        .padding(GSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .fill(Color.gSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                        .stroke(Color.gBorder, lineWidth: 0.5)
                )
        )
    }
}
