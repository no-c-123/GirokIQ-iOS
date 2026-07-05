import SwiftUI
import PencilKit

struct CanvasSidebar: View {
    @ObservedObject var viewModel: CanvasViewModel
    let onShowPages: () -> Void
    let onShowPatterns: () -> Void
    let onShowAI: () -> Void
    let isAIPanelVisible: Bool
    let isAIEnabled: Bool
    let onRegionCapture: () -> Void
    let onManualSync: () -> Void
    @State private var activePopoverTool: DrawingTool?
    @State private var toolFrames: [DrawingTool: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: GSpacing.sm) {
                VStack(spacing: GSpacing.xs) {
                    ForEach([DrawingTool.pen, .pencil, .marker, .eraser, .lasso, .text, .image], id: \.self) { tool in
                        RailToolButton(
                            tool: tool,
                            viewModel: viewModel,
                            activePopoverTool: $activePopoverTool
                        )
                        .background(
                            GeometryReader { buttonGeo in
                                Color.clear
                                    .preference(
                                        key: ToolFramePreferenceKey.self,
                                        value: [tool: buttonGeo.frame(in: .named("CanvasSidebarSpace"))]
                                    )
                            }
                        )
                    }
                }

                Divider().opacity(0.2)
                    .padding(.vertical, 6)

                SidebarButton(icon: "square.stack.3d.up", label: "Pages", action: onShowPages)
                SidebarButton(icon: "circle.grid.3x3", label: "Pattern", action: onShowPatterns)

                if isAIEnabled {
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
                }

                Spacer()

                SidebarButton(icon: "scope", label: "Recenter") {
                    viewModel.recenterViewport()
                }

                if Configuration.cloudSyncEnabled {
                    SidebarButton(icon: "arrow.triangle.2.circlepath", label: "Sync") {
                        onManualSync()
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
            .overlay(alignment: .topLeading) {
                if let tool = activePopoverTool, let frame = toolFrames[tool] {
                    let panelWidth = popoverWidth(for: tool)
                    let panelHeight = popoverHeight(for: tool)
                    ToolQuickSettingsPopover(tool: tool, viewModel: viewModel)
                        .frame(width: panelWidth)
                        .padding(GSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                .fill(Color.gSurface.opacity(0.96))
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                                        .stroke(Color.gBorderStrong.opacity(0.42), lineWidth: 0.7)
                                )
                                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
                        )
                        .position(
                            x: 52 + panelWidth / 2 + 18,
                            y: clampedPopoverY(
                                anchorMidY: frame.midY,
                                panelHeight: panelHeight,
                                availableHeight: proxy.size.height
                            )
                        )
                        .transition(.genie(edge: .leading, travel: 30).combined(with: .opacity))
                        .zIndex(30)
                }
            }
            .coordinateSpace(name: "CanvasSidebarSpace")
            .onPreferenceChange(ToolFramePreferenceKey.self) { value in
                toolFrames = value
            }
            .onChange(of: viewModel.selectedTool) { _, selectedTool in
                if activePopoverTool != selectedTool {
                    animateMotionSafe(GAnimation.springFast) {
                        activePopoverTool = nil
                    }
                }
            }
        }
        .frame(width: 52)
    }

    private func clampedPopoverY(anchorMidY: CGFloat, panelHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(max(anchorMidY, panelHeight / 2 + 8), availableHeight - panelHeight / 2 - 8)
    }

    private func popoverWidth(for tool: DrawingTool) -> CGFloat {
        switch tool {
        case .image:
            return 240
        case .eraser:
            return 224
        default:
            return 220
        }
    }

    private func popoverHeight(for tool: DrawingTool) -> CGFloat {
        switch tool {
        case .pen, .pencil, .marker:
            return tool == .pen ? 438 : 372
        case .eraser:
            return viewModel.eraserType == .vector ? 108 : 204
        case .image:
            return 184
        default:
            return 120
        }
    }
}

private struct RailToolButton: View {
    let tool: DrawingTool
    @ObservedObject var viewModel: CanvasViewModel
    @Binding var activePopoverTool: DrawingTool?

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
                animateMotionSafe(GAnimation.springFast) {
                    activePopoverTool = activePopoverTool == tool ? nil : tool
                }
            } else {
                animateMotionSafe(GAnimation.springFast) {
                    activePopoverTool = nil
                }
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
            animateMotionSafe(GAnimation.springFast) {
                activePopoverTool = tool
            }
        }
        .accessibilityLabel(tool.label)
    }
}

private struct ToolFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DrawingTool: CGRect] = [:]

    static func reduce(value: inout [DrawingTool: CGRect], nextValue: () -> [DrawingTool: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
