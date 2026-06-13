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
            VStack(spacing: GSpacing.xs) {
                ForEach([DrawingTool.pen, .pencil, .marker, .eraser, .lasso, .text, .image], id: \.self) { tool in
                    RailToolButton(tool: tool, viewModel: viewModel)
                }
            }

            Divider().opacity(0.2)
                .padding(.vertical, 6)

            SidebarButton(icon: "square.stack.3d.up", label: "Pages", action: onShowPages)
            SidebarButton(icon: "circle.grid.3x3", label: "Pattern", action: onShowPatterns)

            SidebarButton(
                icon: "sparkles",
                label: "AI",
                isActive: isAIPanelVisible,
                action: onShowAI
            )

            SidebarButton(
                icon: "viewfinder",
                label: "Capture Region",
                isActive: viewModel.isRegionCaptureMode,
                action: onRegionCapture
            )

            Spacer()

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

private struct RailToolButton: View {
    let tool: DrawingTool
    @ObservedObject var viewModel: CanvasViewModel

    @State private var showPopover = false

    private var isSelected: Bool { viewModel.selectedTool == tool }
    private var supportsPopover: Bool {
        switch tool {
        case .text, .lasso, .selection:
            return false
        default:
            return true
        }
    }

    var body: some View {
        Button {
            if isSelected && supportsPopover {
                showPopover.toggle()
            } else {
                showPopover = false
                viewModel.selectTool(tool)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.gPrimary : Color.gElevated.opacity(0.5))
                    .frame(width: 36, height: 36)

                Image(systemName: tool.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .gTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.4) {
            guard supportsPopover else { return }
            if !isSelected { viewModel.selectTool(tool) }
            HapticEngine.light()
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .leading) {
            ToolQuickSettingsPopover(tool: tool, viewModel: viewModel)
                .frame(width: tool == .image ? 240 : 220)
        }
        .accessibilityLabel(tool.label)
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
