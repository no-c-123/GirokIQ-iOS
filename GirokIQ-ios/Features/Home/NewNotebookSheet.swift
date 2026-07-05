import SwiftUI

// MARK: - New Notebook Modal (portrait + landscape)

struct NewNotebookSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    @AppStorage("newNotebook_pattern") private var selectedPattern: BackgroundPattern = .blank
    @AppStorage("newNotebook_bgColorHex") private var selectedBgColorHex: String = "#FDFBF7"

    // Reduced palette to match the reference modal
    private let coverColors: [(name: String, hex: String)] = [
        ("Warm White", "#FDFBF7"),
        ("Cream", "#F5F0E6"),
        ("Sand", "#D4B895"),
        ("Light Gray", "#E5E5E5"),
        ("Charcoal", "#333333"),
        ("Midnight Blue", "#1A233A"),
        ("Black", "#000000")
    ]

    private var panelBackground: Color {
        colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F6F1E7")
    }

    private var panelSurface: Color {
        colorScheme == .dark ? Color(hex: "#242424") : Color(hex: "#FBF8F2")
    }

    private var panelStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var labelColor: Color { colorScheme == .dark ? .gTextSecondary : .gTextSecondary }

    private var previewTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Notebook" : trimmed
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color.black
                    .opacity(isLandscape ? 0.40 : 0.25)
                    .ignoresSafeArea()

                if isLandscape {
                    landscapeDialog(in: geo.size)
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                } else {
                    portraitBottomSheet(in: geo.size)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(GAnimation.motionSafe(.spring(response: 0.32, dampingFraction: 0.86)) ?? .default, value: isLandscape)
            .onAppear { isNameFocused = true }
        }
    }

    // MARK: - Landscape (wide dialog)

    private func landscapeDialog(in size: CGSize) -> some View {
        let maxWidth: CGFloat = min(size.width - 96, 760)
        let height: CGFloat = min(size.height - 120, 420)

        return HStack(spacing: 0) {
            // Preview (left)
            VStack(spacing: 10) {
                coverPreview(style: .landscape)
                Text("LIVE PREVIEW")
                    .font(.gCaption2.weight(.semibold))
                    .foregroundColor(labelColor.opacity(0.85))
                    .tracking(0.6)
            }
            .padding(24)
            .frame(width: 220)

            Rectangle()
                .fill(panelStroke)
                .frame(width: 1)

            // Form (right)
            VStack(alignment: .leading, spacing: 16) {
                dialogHeader(title: "New notebook")

                dialogLabel("NAME")
                nameField

                dialogLabel("PAPER PATTERN")
                patternRow

                dialogLabel("COVER COLOR")
                colorRow

                Spacer(minLength: 0)

                primaryButton(title: "Create notebook", action: createNotebook)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: maxWidth, height: height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 28, x: 0, y: 18)
    }

    // MARK: - Portrait (bottom sheet)

    private func portraitBottomSheet(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                Capsule()
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12))
                    .frame(width: 44, height: 5)
                    .padding(.top, 10)

                HStack {
                    Text("New notebook")
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 20)

                coverPreview(style: .portrait)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    dialogLabel("NAME")
                    nameField

                    dialogLabel("PAPER PATTERN")
                    patternRow

                    dialogLabel("COVER COLOR")
                    colorRow
                }
                .padding(.horizontal, 20)

                primaryButton(title: "Create notebook", action: createNotebook)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(panelStroke, lineWidth: 1)
                    )
                    // Keep the panel from shrinking when the keyboard appears.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Components

    private func dialogHeader(title: String) -> some View {
        HStack {
            Spacer()
            Text(title)
                .font(.gSubheadline.weight(.semibold))
                .foregroundColor(.gTextPrimary)
            Spacer()
            closeButton
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.gIconSmall.weight(.semibold))
                .foregroundColor(.gTextSecondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(panelSurface.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private func dialogLabel(_ text: String) -> some View {
        Text(text)
            .font(.gCaption2.weight(.semibold))
            .foregroundColor(labelColor)
            .tracking(0.6)
    }

    private var nameField: some View {
        TextField("Untitled Notebook", text: $name)
            .font(.gSubheadline)
            .foregroundColor(.gTextPrimary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(panelSurface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.gPrimary.opacity(0.45), lineWidth: 1)
                    )
            )
            .focused($isNameFocused)
            .textInputAutocapitalization(.sentences)
            .disableAutocorrection(true)
            .accessibilityLabel("Notebook name")
    }

    private var patternRow: some View {
        HStack(spacing: 10) {
            ForEach(BackgroundPattern.allCases, id: \.self) { pattern in
                let isSelected = selectedPattern == pattern
                Button {
                    selectedPattern = pattern
                } label: {
                    Group {
                        if pattern == .isometric {
                            Text("3D")
                                .font(.gCaption.weight(.semibold))
                        } else {
                            Image(systemName: pattern.icon)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(isSelected ? .gPrimary : .gTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(panelSurface.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.gPrimary.opacity(0.75) : panelStroke, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pattern.displayName)
            }
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(coverColors, id: \.hex) { item in
                    let isSelected = selectedBgColorHex.uppercased() == item.hex.uppercased()
                    Button {
                        selectedBgColorHex = item.hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.10), lineWidth: 1)
                                )

                            if isSelected {
                                Circle()
                                    .stroke(Color.gPrimary, lineWidth: 2)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                }
            }

            ColorPicker(
                "Custom",
                selection: Binding(
                    get: { Color(hex: selectedBgColorHex) },
                    set: { selectedBgColorHex = $0.hexString }
                ),
                supportsOpacity: false
            )
            .font(.gCaption.weight(.semibold))
            .foregroundColor(.gTextSecondary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(panelSurface.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(panelStroke, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum CoverPreviewStyle { case landscape, portrait }

    private func coverPreview(style: CoverPreviewStyle) -> some View {
        let size: CGSize = (style == .landscape)
        ? CGSize(width: 150, height: 200)
        : CGSize(width: 132, height: 180)

        return NotebookLiveCoverPreview(
            title: previewTitle,
            pattern: selectedPattern,
            backgroundColorHex: selectedBgColorHex
        )
        .frame(width: size.width, height: size.height)
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.gSubheadline.weight(.semibold))
                .foregroundColor(.black.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.gPrimary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Actions

    private func createNotebook() {
        Task {
            guard let userId = authViewModel.currentUserId else { return }
            _ = await viewModel.createNotebook(
                userId: userId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Notebook" : name,
                canvasType: "infinite",
                pageDimensions: nil,
                backgroundPattern: selectedPattern,
                backgroundColorHex: selectedBgColorHex
            )
            dismiss()
        }
    }

    // MARK: - Helpers

}
