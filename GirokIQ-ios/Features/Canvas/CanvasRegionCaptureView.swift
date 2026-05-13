import SwiftUI

struct CanvasRegionCaptureView: View {
    let canvasAreaFrame: CGRect     // frame of the canvas area in global coords (excludes AI panel)
    let onCapture: (Data?) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint = .zero
    @State private var dragCurrent: CGPoint = .zero
    @State private var isDragging: Bool = false

    private var selectionRect: CGRect {
        CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    var body: some View {
        ZStack {
            // Dim layer with punch-out
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .overlay {
                    if isDragging && selectionRect.width > 10 && selectionRect.height > 10 {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()

            // Gold border
            if isDragging && selectionRect.width > 10 && selectionRect.height > 10 {
                Rectangle()
                    .strokeBorder(Color(hex: "#C9A84C"), lineWidth: 2)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)

                Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#C9A84C").opacity(0.9))
                    .cornerRadius(6)
                    .position(x: selectionRect.midX, y: max(selectionRect.minY - 24, 40))
            }

            // Instructions (only when not dragging)
            if !isDragging {
                VStack(spacing: 12) {
                    Image(systemName: "crop")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    Text("Drag to select a region")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                    Text("Release to send to AI")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }

            // Cancel button
            VStack {
                HStack {
                    Spacer()
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        dragStart = value.startLocation
                        isDragging = true
                    }
                    dragCurrent = value.location
                }
                .onEnded { _ in
                    isDragging = false
                    let rect = selectionRect
                    guard rect.width > 20 && rect.height > 20 else {
                        onCapture(nil)
                        return
                    }
                    onCapture(renderRegion(screenRect: rect))
                }
        )
    }

    // MARK: - Render

    private func renderRegion(screenRect: CGRect) -> Data? {
        // Find the key window and take a screenshot of the exact screen region.
        // This captures strokes + image blocks + background — everything the user sees.
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(size: screenRect.size, format: format)
        let image = renderer.image { ctx in
            window.drawHierarchy(in: CGRect(
                origin: CGPoint(x: -screenRect.minX, y: -screenRect.minY),
                size: window.bounds.size
            ), afterScreenUpdates: false)
        }
        return image.pngData()
    }
}