import SwiftUI

struct RegionCaptureOverlay: View {
    @ObservedObject var canvasVM: CanvasViewModel
    @ObservedObject var aiVM: AIChatViewModel
    @Binding var showAIPanel: Bool
    var onInlineAI: ((CGRect, Data) -> Void)? = nil

    @State private var startPoint: CGPoint? = nil
    @State private var currentPoint: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // Drawn rect
                if let start = startPoint, let current = currentPoint {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                    
                    // Cutout
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addRect(rect)
                    }
                    .fill(style: FillStyle(eoFill: true))
                    .foregroundColor(Color.black.opacity(0.4))
                    .ignoresSafeArea()
                    
                    // Border
                    Rectangle()
                        .stroke(Color.white, style: SwiftUI.StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            canvasVM.isRegionCaptureMode = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .padding(24)
                    }
                    Spacer()
                }
            }
            // Invisible layer for gestures
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startPoint == nil {
                            startPoint = value.startLocation
                        }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        guard let start = startPoint else { return }
                        let current = value.location
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        
                        if rect.width > 20 && rect.height > 20 {
                            captureRegion(rect: rect, in: geo)
                        }
                        
                        startPoint = nil
                        currentPoint = nil
                    }
            )
        }
        .ignoresSafeArea()
    }
    
    private func captureRegion(rect: CGRect, in geo: GeometryProxy) {
        // Find the main window
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        
        // Since `rect` is in GeometryReader's local coordinate space,
        // we need to convert it to the window's coordinate space.
        let frameInWindow = geo.frame(in: .global)
        let windowRect = CGRect(
            x: rect.origin.x + frameInWindow.minX,
            y: rect.origin.y + frameInWindow.minY,
            width: rect.width,
            height: rect.height
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(size: windowRect.size, format: format)
        
        let image = renderer.image { _ in
            // Shift the drawing rect so that the targeted rect origin aligns with (0,0) in the image context
            let drawRect = CGRect(
                x: -windowRect.origin.x,
                y: -windowRect.origin.y,
                width: window.bounds.width,
                height: window.bounds.height
            )
            window.drawHierarchy(in: drawRect, afterScreenUpdates: true)
        }
        
        if let data = image.pngData() {
            canvasVM.isRegionCaptureMode = false
            let canvasRect = CGRect(
                x: (rect.minX + canvasVM.canvasOffset.width) / max(canvasVM.canvasScale, 0.001),
                y: (rect.minY + canvasVM.canvasOffset.height) / max(canvasVM.canvasScale, 0.001),
                width: rect.width / max(canvasVM.canvasScale, 0.001),
                height: rect.height / max(canvasVM.canvasScale, 0.001)
            )

            if let onInlineAI {
                onInlineAI(canvasRect, data)
            } else {
                // Fallback to the original behavior: attach to chat panel
                if !showAIPanel {
                    showAIPanel = true
                }
                aiVM.attachedImageData = data
            }
        }
    }
}
