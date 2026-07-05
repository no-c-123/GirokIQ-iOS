import SwiftUI

/// Reusable "live preview" notebook cover, matching the New Notebook modal style.
struct NotebookLiveCoverPreview: View {
    let title: String
    let pattern: BackgroundPattern
    let backgroundColorHex: String

    var cornerRadius: CGFloat = 14
    var showsShadow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var panelStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var coverFill: Color {
        // Keep the same special-case behavior as the New Notebook modal.
        backgroundColorHex.uppercased() == "#0F0F0E" ? .gBackground : Color(hex: backgroundColorHex)
    }

    private var titleColor: Color {
        isDarkColorHex(backgroundColorHex) ? .white : .black
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(coverFill)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(panelStroke, lineWidth: 1)

            NotebookPaperPatternOverlay(pattern: pattern)
                .opacity(isDarkColorHex(backgroundColorHex) ? 0.18 : 0.12)
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            Text(title)
                .font(.custom("InstrumentSerif-Regular", size: 14))
                .foregroundColor(titleColor.opacity(0.92))
                .lineLimit(2)
                .padding(12)
        }
        .compositingGroup()
        .if(showsShadow) { view in
            view.shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18),
                radius: 16,
                x: 0,
                y: 10
            )
        }
        .accessibilityHidden(true)
    }
}

private struct NotebookPaperPatternOverlay: View {
    let pattern: BackgroundPattern

    var body: some View {
        Canvas { context, size in
            guard pattern != .blank else { return }

            let strokeColor = Color.primary.opacity(0.55)
            let lineWidth: CGFloat = 1

            func stroke(_ path: Path) {
                context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
            }

            switch pattern {
            case .blank:
                return

            case .grid:
                let spacing: CGFloat = 16
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                stroke(p)

            case .dots:
                let spacing: CGFloat = 14
                let r: CGFloat = 1.4
                var y: CGFloat = spacing / 2
                while y <= size.height {
                    var x: CGFloat = spacing / 2
                    while x <= size.width {
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(strokeColor))
                        x += spacing
                    }
                    y += spacing
                }

            case .lines:
                let spacing: CGFloat = 18
                var p = Path()
                var y: CGFloat = spacing
                while y <= size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                stroke(p)

            case .isometric:
                // Simple isometric grid: 3 directions (horizontal + 2 diagonals)
                let spacing: CGFloat = 18
                let angle: CGFloat = .pi / 3 // 60°
                let dx = cos(angle) * spacing
                let dy = sin(angle) * spacing

                var p = Path()

                // Horizontal
                var y: CGFloat = spacing
                while y <= size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }

                // Diagonal down-right
                var startX: CGFloat = -size.height
                while startX <= size.width {
                    var x0 = startX
                    var y0: CGFloat = 0
                    p.move(to: CGPoint(x: x0, y: y0))
                    while x0 <= size.width && y0 <= size.height {
                        x0 += dx
                        y0 += dy
                        p.addLine(to: CGPoint(x: x0, y: y0))
                    }
                    startX += spacing
                }

                // Diagonal down-left
                var startX2: CGFloat = 0
                while startX2 <= size.width + size.height {
                    var x0 = startX2
                    var y0: CGFloat = 0
                    p.move(to: CGPoint(x: x0, y: y0))
                    while x0 >= 0 && y0 <= size.height {
                        x0 -= dx
                        y0 += dy
                        p.addLine(to: CGPoint(x: x0, y: y0))
                    }
                    startX2 += spacing
                }

                stroke(p)
            }
        }
        .drawingGroup()
    }
}

private func isDarkColorHex(_ hex: String) -> Bool {
    let upper = hex.uppercased()
    let darkColors = ["#0F0F0E", "#333333", "#1A233A", "#000000"]
    return darkColors.contains(upper)
}

