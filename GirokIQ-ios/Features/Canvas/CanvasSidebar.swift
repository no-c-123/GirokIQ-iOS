import SwiftUI

struct CanvasSidebar: View {
    @ObservedObject var viewModel: CanvasViewModel
    let onShowPages: () -> Void
    let onShowPatterns: () -> Void
    let onShowAI: () -> Void
    let isAIPanelVisible: Bool
    let onRegionCapture: () -> Void

    var body: some View {
        VStack(spacing: GSpacing.sm) {
            // Pages
            SidebarButton(icon: "square.stack.3d.up", label: "Pages", action: onShowPages)
            
            // Patterns
            SidebarButton(icon: "circle.grid.3x3", label: "Pattern", action: onShowPatterns)
            
            // Properties Toggle
            SidebarButton(
                icon: "slider.horizontal.3",
                label: "Properties",
                isActive: viewModel.showProperties,
                action: {
                    withAnimation(GAnimation.springFast) {
                        viewModel.showProperties.toggle()
                    }
                }
            )
            
            // AI Button
            SidebarButton(
                icon: "sparkles",
                label: "AI",
                isActive: isAIPanelVisible,
                action: onShowAI
            )
            
            // Region Capture Button
            SidebarButton(
                icon: "viewfinder",
                label: "Capture Region",
                isActive: viewModel.isRegionCaptureMode,
                action: onRegionCapture
            )
            
            Spacer()
            
            // Sync
            SidebarButton(icon: "arrow.triangle.2.circlepath", label: "Sync") {
                Task {
                    await viewModel.flushSave()
                    HapticEngine.success()
                }
            }
        }
        .padding(.vertical, GSpacing.sm)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gSurface.opacity(0.96))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .stroke(Color.gBorderStrong.opacity(0.5), lineWidth: 0.5)
        )
        .frame(width: 52)
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(isActive ? Color.gPrimary : Color.gElevated.opacity(0.5))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? .white : .gTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
