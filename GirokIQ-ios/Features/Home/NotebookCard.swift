import SwiftUI

// MARK: - Notebook Card

/// Performance-optimized notebook card.
/// - Uses `Equatable` conformance to skip redundant SwiftUI diffs during scroll.
/// - Avoids offscreen rendering by using `compositingGroup()` instead of separate overlay strokes.
struct NotebookCard: View, Equatable {
    let notebook: Notebook
    let viewMode: HomeViewModel.ViewMode
    let onTap: () -> Void

    static func == (lhs: NotebookCard, rhs: NotebookCard) -> Bool {
        lhs.notebook.id == rhs.notebook.id &&
        lhs.notebook.name == rhs.notebook.name &&
        lhs.notebook.updatedAt == rhs.notebook.updatedAt &&
        lhs.viewMode == rhs.viewMode
    }

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
        .background(Color.gSurface)
        .clipShape(RoundedRectangle(cornerRadius: GRadius.md, style: .continuous))
        // Use compositingGroup to flatten all layers into a single offscreen buffer,
        // then apply the border stroke once — avoids per-frame offscreen rendering
        // that Core Animation would otherwise trigger for each overlay + clip combination.
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .stroke(Color.gBorder, lineWidth: 0.5)
        )
        .compositingGroup()
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
        .background(Color.gSurface)
        .clipShape(RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                .stroke(Color.gBorder, lineWidth: 0.5)
        )
        .compositingGroup()
    }
}
