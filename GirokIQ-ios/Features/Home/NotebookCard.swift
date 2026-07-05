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

    private var coverColor: Color {
        let hex = notebook.backgroundColorHex.uppercased()
        return hex == "#0F0F0E" ? .gBackground : Color(hex: notebook.backgroundColorHex)
    }

    private var coverForegroundColor: Color {
        let darkColors = ["#0F0F0E", "#333333", "#1A233A", "#000000"]
        return darkColors.contains(notebook.backgroundColorHex.uppercased()) ? .white : .black
    }

    // MARK: - Grid Card

    var gridCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(coverColor)

                Image(systemName: "circle.grid.cross")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.04)
                    .blendMode(.multiply)

                HStack {
                    VStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(coverForegroundColor.opacity(0.16))
                                .frame(height: 1)
                        }
                    }
                    .frame(width: 8)
                    .padding(.leading, 8)
                    Spacer()
                }

                VStack {
                    Spacer()
                    Text(notebook.name)
                        .font(.custom("InstrumentSerif-Regular", size: 20))
                        .foregroundColor(coverForegroundColor.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
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
                    .fill(coverColor)
                    .frame(width: 44, height: 44)
                Text(initial)
                    .font(.gSubheadline.weight(.bold))
                    .foregroundColor(coverForegroundColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.gSubheadline.weight(.semibold))
                    .foregroundColor(.gTextPrimary)
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
