import SwiftUI
import PencilKit

// MARK: - Page Strip View

struct PageStripView: View {
    @ObservedObject var canvasVM: CanvasViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GSpacing.sm) {
                ForEach(canvasVM.pages.indices, id: \.self) { index in
                    pageButton(for: index)
                }
                addPageButton
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.vertical, GSpacing.sm)
        }
        .background(Color.gBackground.opacity(0.96))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }

    // MARK: - Subviews

    private func pageButton(for index: Int) -> some View {
        let isSelected = canvasVM.currentPageIndex == index
        let page = canvasVM.pages[index]
        return Button {
            withAnimation(GAnimation.springFast) { canvasVM.currentPageIndex = index }
        } label: {
            VStack(spacing: GSpacing.xxs) {
                ZStack {
                    RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                        .fill(Color.gElevated)
                        .frame(width: 56, height: 74)

                    // PencilKit thumbnail
                    if let thumbnail = pageThumbnail(for: page) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: GRadius.xs - 1, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.xs)
                        .stroke(
                            isSelected ? Color.gPrimary : Color.gBorder,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )
                .frame(width: 56, height: 74)

                Text("\(index + 1)")
                    .font(.gCaption2)
                    .foregroundColor(.gTextTertiary)
            }
        }
        .minTapTarget()
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to switch to page \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Generate a small thumbnail from the page's PKDrawing data
    private func pageThumbnail(for page: DrawingPage) -> UIImage? {
        guard let data = page.drawingData,
              let drawing = PencilKitBridge.deserialize(data) else { return nil }
        let bounds = CGRect(origin: .zero, size: CGSize(width: 56, height: 74))
        let image = drawing.image(from: drawing.bounds.isEmpty ? bounds : drawing.bounds, scale: 1.0)
        return image
    }

    private var addPageButton: some View {
        Button {
            canvasVM.addPage()
        } label: {
            VStack(spacing: GSpacing.xxs) {
                RoundedRectangle(cornerRadius: GRadius.xs, style: .continuous)
                    .stroke(Color.gBorder, style: SwiftUI.StrokeStyle(dash: [4]))
                    .frame(width: 56, height: 74)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.gTitle3)
                            .foregroundColor(.gTextTertiary)
                    )
                Text("Add")
                    .font(.gCaption2)
                    .foregroundColor(.gTextTertiary)
            }
        }
        .minTapTarget()
        .accessibilityLabel("Add new page")
        .accessibilityHint("Double tap to add a new page")
        .accessibilityAddTraits(.isButton)
        .keyboardShortcut("n", modifiers: .command)
    }
}

// MARK: - Pattern Picker Sheet

struct PatternPickerSheet: View {
    @Binding var selectedPattern: BackgroundPattern
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gBackground(for: colorScheme).ignoresSafeArea()

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: GSpacing.md
                ) {
                    ForEach(BackgroundPattern.allCases, id: \.self) { pattern in
                        patternButton(for: pattern)
                    }
                }
                .padding(GSpacing.lg)
            }
            .navigationTitle("Background Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.gPrimary)
                }
            }
            .toolbarBackground(Color.gSurface(for: colorScheme), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Subviews

    private func patternButton(for pattern: BackgroundPattern) -> some View {
        let isSelected = selectedPattern == pattern
        return Button {
            selectedPattern = pattern
            dismiss()
        } label: {
            VStack(spacing: GSpacing.xs) {
                patternTile(for: pattern, isSelected: isSelected)
                Text(pattern.displayName)
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary(for: colorScheme))
            }
        }
        .minTapTarget()
        .accessibilityLabel("\(pattern.displayName) background")
        .accessibilityHint("Double tap to select this pattern")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func patternTile(for pattern: BackgroundPattern, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: GRadius.sm)
                .fill(Color.gSurface(for: colorScheme))
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm)
                        .stroke(
                            isSelected ? Color.gPrimary : Color.gBorder(for: colorScheme),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )

            Image(systemName: pattern.icon)
                .font(.gEmojiSmall)
                .foregroundColor(isSelected ? .gPrimary : .gTextSecondary(for: colorScheme))
        }
    }
}
