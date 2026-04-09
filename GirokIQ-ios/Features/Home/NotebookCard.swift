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

    /// Generates a unique, rich dark gradient based on the notebook's ID
    private var coverGradient: LinearGradient {
        let index = abs(notebook.id.hashValue) % 4
        let topColors = [
            Color(hex: "#1A233A"), // Deep Navy
            Color(hex: "#2A1A3A"), // Deep Purple
            Color(hex: "#1A3A2B"), // Dark Forest
            Color(hex: "#3A1A1A")  // Deep Burgundy
        ]
        return LinearGradient(
            colors: [topColors[index], Color(hex: "#0A0C10")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Generates a subtle notebook type icon based on the notebook's ID
    private var coverIcon: String {
        let icons = ["doc.plaintext", "squareshape.split.3x3", "line.horizontal.3", "book.closed"]
        let index = abs(notebook.id.hashValue) % icons.count
        return icons[index]
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
                // Rich dark ink gradient
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(coverGradient)

                // Faint paper grain texture overlay
                Image(systemName: "circle.grid.cross")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.05)
                    .blendMode(.multiply)

                // Spine binding effect
                HStack {
                    VStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                        }
                    }
                    .frame(width: 8)
                    .padding(.leading, 8)
                    Spacer()
                }

                // Center icon representing notebook type
                Image(systemName: coverIcon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .aspectRatio(0.75, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding([.top, .horizontal], 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(notebook.name)
                    .font(.custom("InstrumentSerif-Regular", size: 20))
                    .foregroundColor(.gTextPrimary)
                    .lineLimit(1)

                Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.custom("PlusJakartaSans-Medium", size: 12))
                    .foregroundColor(.gTextTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
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
