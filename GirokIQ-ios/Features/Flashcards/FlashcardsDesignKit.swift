import SwiftUI

// MARK: - Flashcards Design Kit
//
// Shared primitives for the Flashcards (Study Mode) surface.
// Everything here follows the Home visual language: white cards on the app
// background, warm gold as the only accent, muted green / coral for verdicts,
// and Instrument Serif reserved for the results hero number.

// MARK: - Metrics

enum FMetrics {
    /// Reading column for full-screen study surfaces.
    static let contentWidth: CGFloat = 720
    /// Setup modals (select content, configure session).
    static let modalWidth: CGFloat = 560
    /// Focus-mode card.
    static let focusCardWidth: CGFloat = 640

    /// Vertical rhythm — tight, but never cramped.
    static let rowGap: CGFloat = 8
    static let blockGap: CGFloat = 14
    static let sectionGap: CGFloat = 22

    /// Interior padding for the big white cards.
    static let cardPadding: CGFloat = 18
    /// Interior padding for list rows and small cards.
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 12
}

// MARK: - Fonts

extension Font {
    /// Question prompts — the loudest SF text in the feature.
    static let fQuestion = Font.system(size: 24, weight: .bold)
    static let fQuestionCompact = Font.system(size: 20, weight: .bold)
    /// Section labels inside cards ("Study mode", "Difficulty").
    static let fSectionTitle = Font.system(size: 14, weight: .semibold)
    /// All-caps eyebrows ("YOUR ANSWER", "ANSWER").
    static let fEyebrow = Font.system(size: 10, weight: .semibold)
    /// Body copy inside cards.
    static let fBody = Font.system(size: 15, weight: .regular)
    static let fBodyStrong = Font.system(size: 15, weight: .semibold)
    /// Captions, sources, helper lines.
    static let fMeta = Font.system(size: 12, weight: .regular)
    static let fMetaStrong = Font.system(size: 12, weight: .semibold)
}

// MARK: - Verdict colors
//
// `gSuccess` / `gDestructive` are bright signal colors; the design calls for
// muted, readable versions on tinted fills, so these are derived deliberately
// rather than reused directly.

extension Color {
    static let fCorrect = Color(light: Color(hex: "#3F7D58"), dark: Color(hex: "#5FBF8B"))
    static let fCorrectFill = Color(light: Color(hex: "#3F7D58").opacity(0.09), dark: Color(hex: "#5FBF8B").opacity(0.14))
    static let fWrong = Color(light: Color(hex: "#B4524A"), dark: Color(hex: "#E08C84"))
    static let fWrongFill = Color(light: Color(hex: "#B4524A").opacity(0.08), dark: Color(hex: "#E08C84").opacity(0.14))
    /// Inset panels inside a white card (the "your answer" sub-cards).
    static let fInset = Color(light: Color(hex: "#F4F4F6"), dark: Color(hex: "#242424"))
}

// MARK: - Session chrome

/// Top bar for the full-screen study surfaces: close on the left, centered
/// notebook name + position, optional overflow on the right.
struct FSessionBar: View {
    let title: String
    let subtitle: String?
    var progress: Double? = nil
    let onClose: () -> Void
    var menu: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let subtitle {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(.fMetaStrong)
                            .foregroundColor(.gTextPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.fMeta)
                            .foregroundColor(.gTextTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 64)
                }

                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .toolbarIconStyle()
                    }
                    .minTapTarget()
                    .accessibilityLabel("Close study session")

                    Spacer()

                    if let menu {
                        menu
                    }
                }
            }
            .padding(.horizontal, GSpacing.md)
            .padding(.top, GSpacing.xs)
            .padding(.bottom, GSpacing.sm)

            if let progress {
                FProgressRail(progress: progress)
            }
        }
    }
}

/// Full-bleed hairline progress rail that sits directly under the session bar.
struct FProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gBorder.opacity(0.45))
                Capsule()
                    .fill(Color.gPrimary)
                    .frame(width: max(2, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 3)
        .animation(GAnimation.motionSafe(GAnimation.springGentle), value: progress)
        .accessibilityHidden(true)
    }
}

/// Header for the setup modals: title, subtitle, and a trailing close chip.
struct FModalHeader: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gTitle3)
                    .foregroundColor(.gTextPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.fMeta)
                        .foregroundColor(.gTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .toolbarIconStyle()
            }
            .minTapTarget()
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Containers

/// The standard white card used throughout the feature.
struct FCard<Content: View>: View {
    var padding: CGFloat = FMetrics.cardPadding
    var radius: CGFloat = GRadius.lg
    var accented: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.gSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(accented ? Color.gPrimary.opacity(0.55) : Color.gBorder, lineWidth: accented ? 1.5 : 0.5)
            )
    }
}

/// A tinted inset panel used inside cards (answer comparisons, stat tiles).
struct FInsetPanel<Content: View>: View {
    var fill: Color = .fInset
    var padding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                    .fill(fill)
            )
    }
}

// MARK: - Text bits

/// Small all-caps label above a value.
struct FEyebrow: View {
    let text: String
    var color: Color = .gTextTertiary

    var body: some View {
        Text(text.uppercased())
            .font(.fEyebrow)
            .tracking(0.7)
            .foregroundColor(color)
    }
}

/// "Source: Notebook / Page 3" attribution line.
struct FSourceLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.fMeta)
            .foregroundColor(.gTextTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// Circular badge carrying a glyph — used by explanation and verdict rows.
struct FBadge: View {
    let systemName: String
    var tint: Color = .gSecondary
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.14)))
    }
}

/// A / B / C / D badge on multiple-choice rows.
struct FLetterBadge: View {
    let letter: String
    var filled: Bool = false
    var tint: Color = .gPrimary

    var body: some View {
        Text(letter)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(filled ? .white : .gTextTertiary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(filled ? tint : Color.gElevated))
    }
}

// MARK: - Controls

/// Pill chip used for counts, difficulty and topic tags.
struct FChip: View {
    let title: String
    var isSelected: Bool = false
    var isInteractive: Bool = true
    var tint: Color = .gPrimary
    var onTap: (() -> Void)? = nil

    var body: some View {
        let label = Text(title)
            .font(.fMetaStrong)
            .foregroundColor(isSelected ? .white : .gTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? tint : Color.gElevated)
            )
            .contentShape(Capsule())

        if isInteractive, let onTap {
            Button(action: onTap) { label }
                .buttonStyle(GScaleButtonStyle())
                .frame(minHeight: 44)
        } else {
            label
        }
    }
}

/// Segmented control styled like Home's Grid/List toggle.
struct FSegmented<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let active = item == selection
                Button {
                    animateMotionSafe(GAnimation.springFast) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.fMetaStrong)
                        .foregroundColor(active ? .gTextPrimary : .gTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: GRadius.sm, style: .continuous)
                                    .fill(Color.gSurface)
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "f_segment", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 40)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: GRadius.md, style: .continuous)
                .fill(Color.gElevated)
        )
    }
}

/// Compact secondary action ("Edit", "Select all", "Clear").
struct FMiniButton: View {
    let title: String
    var tint: Color = .gTextPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.fMetaStrong)
                .foregroundColor(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.gElevated))
                .contentShape(Capsule())
        }
        .buttonStyle(GScaleButtonStyle())
        .frame(minHeight: 44)
    }
}

/// The feature's primary action button — a gold pill sized to its label.
struct FPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.fBodyStrong)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(.white)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 26)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 44)
            .background(Capsule().fill(Color.gPrimary))
            .opacity(isDisabled ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(GScaleButtonStyle())
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
    }
}

/// Neutral counterpart to `FPrimaryButton`.
struct FSecondaryButton: View {
    let title: String
    var isDisabled: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.fBodyStrong)
                .foregroundColor(.gTextPrimary)
                .padding(.horizontal, 22)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: 44)
                .background(Capsule().fill(Color.gElevated))
                .opacity(isDisabled ? 0.45 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(GScaleButtonStyle())
        .disabled(isDisabled)
    }
}

// MARK: - Question navigator
//
// The strip of pips along the bottom of the quiz and results screens. It turns
// the leftover band under the content into the session's map: how far along you
// are, what you got right, and a way back to any answered question.

struct FQuestionNavigator: View {
    enum Pip: Equatable {
        case upcoming
        case current
        case correct
        case incorrect
    }

    let pips: [Pip]
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pips.indices, id: \.self) { idx in
                let pip = pips[idx]
                let dot = Capsule()
                    .fill(fill(for: pip))
                    .frame(width: pip == .current ? 22 : 8, height: 8)

                if let onSelect, pip == .correct || pip == .incorrect {
                    Button { onSelect(idx) } label: {
                        dot.frame(width: 20, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Question \(idx + 1), \(pip == .correct ? "correct" : "incorrect")")
                } else {
                    dot.accessibilityHidden(true)
                }
            }
        }
        .animation(GAnimation.motionSafe(GAnimation.springFast), value: pips)
    }

    private func fill(for pip: Pip) -> Color {
        switch pip {
        case .upcoming: return Color.gBorder
        case .current: return Color.gPrimary
        case .correct: return Color.fCorrect.opacity(0.75)
        case .incorrect: return Color.fWrong.opacity(0.75)
        }
    }
}

// MARK: - Layout helper

/// Centers content in a reading column and keeps it optically centered in the
/// available height, so leftover space is split above and below rather than
/// pooling at the bottom of the screen. Once the content outgrows the viewport
/// it scrolls normally from the top.
struct FCenteredColumn<Content: View>: View {
    var maxWidth: CGFloat = FMetrics.contentWidth
    var horizontalPadding: CGFloat = GSpacing.lg
    var verticalPadding: CGFloat = GSpacing.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
