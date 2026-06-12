import SwiftUI
import PencilKit

// MARK: - Page Strip View

struct PageStripView: View {
    @ObservedObject var canvasVM: CanvasViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: GSpacing.sm) {
                ForEach(canvasVM.pages.indices, id: \.self) { index in
                    pageButton(for: index)
                }
                addPageButton
            }
            .padding(.vertical, GSpacing.md)
            .padding(.horizontal, GSpacing.sm)
        }
        .frame(width: 80)
        .background(Color.gBackground.opacity(0.96))
        .overlay(alignment: .trailing) {
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

                    // Use cached thumbnail from CanvasViewModel (generated async off main thread)
                    if let thumbnail = canvasVM.pageThumbnails[page.id] {
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
        .contextMenu {
            if canvasVM.pages.count > 1 {
                Button(role: .destructive) {
                    withAnimation {
                        canvasVM.deletePage(at: index)
                    }
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            }
        }
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
    var onPatternChanged: ((BackgroundPattern) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gBackground.ignoresSafeArea()

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
            .toolbarBackground(Color.gSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Subviews

    private func patternButton(for pattern: BackgroundPattern) -> some View {
        let isSelected = selectedPattern == pattern
        return Button {
            selectedPattern = pattern
            onPatternChanged?(pattern)
            dismiss()
        } label: {
            VStack(spacing: GSpacing.xs) {
                patternTile(for: pattern, isSelected: isSelected)
                Text(pattern.displayName)
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
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
                .fill(Color.gSurface)
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: GRadius.sm)
                        .stroke(
                            isSelected ? Color.gPrimary : Color.gBorder,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )

            Image(systemName: pattern.icon)
                .font(.gEmojiSmall)
                .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
        }
    }
}
