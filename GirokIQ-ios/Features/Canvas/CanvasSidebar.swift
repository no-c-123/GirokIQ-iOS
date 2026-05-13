import SwiftUI

struct CanvasSidebar: View {
    @ObservedObject var viewModel: CanvasViewModel
    let onShowPages: () -> Void
    let onShowPatterns: () -> Void
    let onShowAI: () -> Void
    let isAIPanelVisible: Bool

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onShowPages) {
                Image(systemName: "doc.on.doc")
                    .canvasToolbarIcon()
            }
            .accessibilityLabel("Pages")

            Button(action: onShowPatterns) {
                Image(systemName: "grid")
                    .canvasToolbarIcon()
            }
            .accessibilityLabel("Background pattern")

            Button {
                withAnimation(GAnimation.springFast) {
                    viewModel.showProperties.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .canvasToolbarIcon(active: viewModel.showProperties)
            }
            .accessibilityLabel("Properties panel")

            Divider().padding(.horizontal, 8)

            Button {
                viewModel.isShapeSnappingEnabled.toggle()
            } label: {
                Image(systemName: "lasso")
                    .canvasToolbarIcon(active: viewModel.isShapeSnappingEnabled)
            }
            .accessibilityLabel("Shape Snap")

            Divider().padding(.horizontal, 8)

            Button(action: onShowAI) {
                Image(systemName: "sparkles")
                    .canvasToolbarIcon(active: isAIPanelVisible)
            }
            .accessibilityLabel("AI Assistant")

            Spacer()

            if viewModel.isSaving {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "checkmark.icloud")
                    .font(.gIconMedium)
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 32, height: 32)
                    .opacity(0.5)
                    .accessibilityLabel("Synced")
            }

            if viewModel.isOpenOnWeb {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Web")
                        .font(.gCaption2.weight(.medium))
                        .foregroundColor(.gTextSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5))
                )
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Also open on web")
            }
        }
        .padding(.vertical, 12)
        .frame(width: 52)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.96))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .stroke(Color.gBorderStrong, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}
