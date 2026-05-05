import SwiftUI

// MARK: - Canvas Type Enum
enum CanvasType: String, CaseIterable {
    case infinite, fixed
}

enum DimensionPreset: String, CaseIterable, Identifiable {
    case a4     = "A4"
    case letter = "Letter"
    case a5     = "A5"
    case custom = "Custom"

    var id: String { rawValue }

    var pageDimensions: PageDimensions? {
        switch self {
        case .a4:     return .a4
        case .letter: return .letter
        case .a5:     return .a5
        case .custom: return nil   // caller computes from mm fields
        }
    }

    var displayWidth: String {
        switch self {
        case .a4:     return "210"
        case .letter: return "216"
        case .a5:     return "148"
        case .custom: return ""
        }
    }

    var displayHeight: String {
        switch self {
        case .a4:     return "297"
        case .letter: return "279"
        case .a5:     return "210"
        case .custom: return ""
        }
    }
}

struct NotebookTemplate: Identifiable {
    let id = UUID()
    let name: String
    let sizeName: String
    let icon: String
}

// MARK: - New Notebook Sheet

struct NewNotebookSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    
    @AppStorage("newNotebook_canvasType") private var canvasType: CanvasType = .infinite
    @AppStorage("newNotebook_pattern") private var selectedPattern: BackgroundPattern = .blank
    @AppStorage("newNotebook_bgColorHex") private var selectedBgColorHex: String = "#0F0F0E"
    
    // Fixed template: selected preset and optional custom override
    @State private var selectedPreset: DimensionPreset = .a4
    @State private var isCustomDimensions: Bool = false
    @State private var customWidthMM: String = "210"   // A4 width in mm
    @State private var customHeightMM: String = "297"  // A4 height in mm
    
    let backgroundColors: [(name: String, hex: String)] = [
        ("Default", "#0F0F0E"),
        ("Warm White", "#FDFBF7"),
        ("Cream", "#F5F0E6"),
        ("Light Gray", "#E5E5E5"),
        ("Kraft Brown", "#D4B895"),
        ("Charcoal", "#333333"),
        ("Midnight Blue", "#1A233A"),
        ("Black", "#000000")
    ]
    
    let prebuiltTemplates = [
        NotebookTemplate(name: "Blank Page", sizeName: "A4", icon: "doc.plaintext"),
        NotebookTemplate(name: "Lined Page", sizeName: "A4", icon: "line.horizontal.3"),
        NotebookTemplate(name: "Cornell Notes", sizeName: "Letter", icon: "sidebar.left"),
        NotebookTemplate(name: "Weekly Planner", sizeName: "A4", icon: "calendar"),
        NotebookTemplate(name: "Dot Grid Journal", sizeName: "A5", icon: "circle.grid.cross"),
        NotebookTemplate(name: "Sketch Page", sizeName: "Custom", icon: "pencil.and.outline"),
        NotebookTemplate(name: "Music Sheet", sizeName: "Letter", icon: "music.note.list"),
        NotebookTemplate(name: "Math Grid", sizeName: "A4", icon: "squareshape.split.3x3")
    ]

    private var resolvedDimensions: PageDimensions {
        if canvasType == .infinite { return .a4 }  // unused for infinite
        if selectedPreset != .custom, let dims = selectedPreset.pageDimensions {
            return dims
        }
        // Custom: convert mm → points (1mm = 2.8346pt)
        let w = (Double(customWidthMM) ?? 210) * 2.8346
        let h = (Double(customHeightMM) ?? 297) * 2.8346
        return PageDimensions(widthPt: w, heightPt: h)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.gBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        coverPreviewSection
                        
                        nameSection
                        
                        canvasTypeSection
                        
                        if canvasType == .fixed {
                            dimensionsSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        patternSection
                        
                        backgroundColorSection
                        
                        if canvasType == .fixed {
                            templateSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Extra padding at bottom for sticky button
                        Spacer().frame(height: 100)
                    }
                    .padding(.vertical, 24)
                }
                
                // Sticky Create Button
                VStack {
                    Button {
                        createNotebook()
                    } label: {
                        Text("Create Notebook")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.gPrimary)
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .padding(.top, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.gBackground.opacity(0), Color.gBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gTextSecondary)
                        .font(.custom("PlusJakartaSans-Medium", size: 15))
                }
            }
            .toolbarBackground(Color.gBackground, for: .navigationBar)
            .onAppear {
                isNameFocused = true
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: canvasType)
        }
    }
    
    // MARK: - Sections
    
    private var coverPreviewSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background Color
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedBgColorHex.uppercased() == "#0F0F0E" ? Color.gBackground : Color(hex: selectedBgColorHex))
                
                // Paper Texture Overlay
                Image(systemName: "circle.grid.cross")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.03)
                    .blendMode(.multiply)
                
                // Pattern Overlay
                Image(systemName: selectedPattern.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Color.primary.opacity(0.1))
                
                // Title
                VStack {
                    Spacer()
                    Text(name.isEmpty ? "Untitled Notebook" : name)
                        .font(.custom("InstrumentSerif-Regular", size: 20))
                        .foregroundColor(isDarkColor(hex: selectedBgColorHex) ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
            .frame(width: 160, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
            .animation(.easeInOut(duration: 0.3), value: selectedBgColorHex)
            .animation(.easeInOut(duration: 0.3), value: selectedPattern)
        }
    }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Untitled Notebook", text: $name)
                .font(.custom("PlusJakartaSans-Medium", size: 15))
                .foregroundColor(.gTextPrimary)
                .padding(16)
                .background(Color.gSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($isNameFocused)
        }
        .padding(.horizontal, 24)
    }
    
    private var canvasTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("CANVAS TYPE")
            
            HStack(spacing: 12) {
                canvasTypeCard(
                    type: .infinite,
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Infinite Canvas",
                    subtitle: "No page boundaries. Zoom and pan freely."
                )
                
                canvasTypeCard(
                    type: .fixed,
                    icon: "doc.text",
                    title: "Fixed Template",
                    subtitle: "Page-sized canvas. Use pre-made or custom templates."
                )
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func canvasTypeCard(type: CanvasType, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = canvasType == type
        return Button {
            canvasType = type
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? Color.gPrimary : .gTextPrimary)
                
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 15))
                    .foregroundColor(.gTextPrimary)
                
                Text(subtitle)
                    .font(.custom("PlusJakartaSans-Medium", size: 12))
                    .foregroundColor(.gTextSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.gPrimary : Color.clear, lineWidth: 2)
            )
        }
    }
    
    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PAGE SIZE")

            // Preset pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DimensionPreset.allCases) { preset in
                        let isSelected = selectedPreset == preset
                        Button {
                            selectedPreset = preset
                            if preset != .custom {
                                customWidthMM = preset.displayWidth
                                customHeightMM = preset.displayHeight
                            }
                        } label: {
                            Text(preset.rawValue)
                                .font(.custom("PlusJakartaSans-Medium", size: 13))
                                .foregroundColor(isSelected ? Color.gBackground : .gTextPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.gPrimary : Color.gSurface)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // Custom input fields — shown when preset == .custom
            if selectedPreset == .custom {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Width (mm)")
                            .font(.custom("PlusJakartaSans-Medium", size: 11))
                            .foregroundColor(.gTextSecondary)
                        TextField("210", text: $customWidthMM)
                            .keyboardType(.decimalPad)
                            .font(.custom("PlusJakartaSans-Medium", size: 15))
                            .foregroundColor(.gTextPrimary)
                            .padding(12)
                            .background(Color.gSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Height (mm)")
                            .font(.custom("PlusJakartaSans-Medium", size: 11))
                            .foregroundColor(.gTextSecondary)
                        TextField("297", text: $customHeightMM)
                            .keyboardType(.decimalPad)
                            .font(.custom("PlusJakartaSans-Medium", size: 15))
                            .foregroundColor(.gTextPrimary)
                            .padding(12)
                            .background(Color.gSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Helper text
            Text(selectedPreset == .custom
                 ? "Enter dimensions in millimetres."
                 : "\(selectedPreset.rawValue): \(selectedPreset.displayWidth) × \(selectedPreset.displayHeight) mm")
                .font(.custom("PlusJakartaSans-Medium", size: 12))
                .foregroundColor(.gTextSecondary)
                .padding(.horizontal, 24)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPreset)
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PAPER PATTERN")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BackgroundPattern.allCases, id: \.self) { pattern in
                        let isSelected = selectedPattern == pattern
                        Button {
                            selectedPattern = pattern
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.gSurface)
                                
                                Image(systemName: pattern.icon)
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(isSelected ? Color.gPrimary : .gTextSecondary)
                            }
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.gPrimary : Color.clear, lineWidth: 2)
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var backgroundColorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BACKGROUND")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(backgroundColors, id: \.name) { bg in
                        let isSelected = selectedBgColorHex == bg.hex
                        Button {
                            selectedBgColorHex = bg.hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(bg.hex.uppercased() == "#0F0F0E" ? Color.gBackground : Color(hex: bg.hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().stroke(Color.gBorderStrong, lineWidth: 1)
                                    )
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color.gPrimary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TEMPLATE")
            
            Button {
                canvasType = .infinite
            } label: {
                HStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("Switch to Infinite Canvas")
                        .font(.custom("PlusJakartaSans-Medium", size: 13))
                }
                .foregroundColor(Color.gPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gPrimary.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(prebuiltTemplates) { template in
                    templateCard(template)
                }
                
                // Import Template Card
                Button {
                    // Open file picker logic would go here
                } label: {
                    VStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.gBorderStrong, style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .background(Color.gSurface)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 24))
                                .foregroundColor(.gTextSecondary)
                        }
                        .frame(height: 150)
                        
                        Text("Import Template")
                            .font(.custom("PlusJakartaSans-Medium", size: 13))
                            .foregroundColor(.gTextPrimary)
                            .padding(.top, 4)
                        
                        Text("PDF or Image")
                            .font(.custom("PlusJakartaSans-Medium", size: 11))
                            .foregroundColor(.gTextSecondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Text("Canvas size is set by the template's dimensions.")
                .font(.custom("PlusJakartaSans-Medium", size: 12))
                .foregroundColor(.gTextSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }
    
    private func templateCard(_ template: NotebookTemplate) -> some View {
        Button {
            // Select template logic
        } label: {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gSurface)
                    
                    Image(systemName: template.icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.gTextSecondary)
                }
                .frame(height: 150)
                
                Text(template.name)
                    .font(.custom("PlusJakartaSans-Medium", size: 13))
                    .foregroundColor(.gTextPrimary)
                    .padding(.top, 4)
                
                Text(template.sizeName)
                    .font(.custom("PlusJakartaSans-Medium", size: 11))
                    .foregroundColor(.gTextSecondary)
            }
        }
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.custom("PlusJakartaSans-Medium", size: 12))
            .foregroundColor(.gTextSecondary)
            .padding(.horizontal, 24)
    }
    
    // MARK: - Helpers
    
    private func isDarkColor(hex: String) -> Bool {
        if hex.uppercased() == "#0F0F0E" {
            return colorScheme == .dark
        }
        let darkColors = ["#333333", "#1A233A", "#000000"]
        return darkColors.contains(hex.uppercased())
    }
    
    private func createNotebook() {
        Task {
            guard let userId = authViewModel.currentUserId else { return }
            _ = await viewModel.createNotebook(
                userId: userId,
                name: name.isEmpty ? "Untitled Notebook" : name,
                canvasType: canvasType.rawValue,
                pageDimensions: canvasType == .fixed ? resolvedDimensions : nil,
                backgroundPattern: selectedPattern,
                backgroundColorHex: selectedBgColorHex
            )
            dismiss()
        }
    }
}

