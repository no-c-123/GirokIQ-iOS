import SwiftUI

// MARK: - Canvas Type Enum
enum CanvasType: String, CaseIterable {
    case infinite, fixed
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
    
    let backgroundColors: [(name: String, hex: String)] = [
        ("Warm White", "#FDFBF7"),
        ("Cream", "#F5F0E6"),
        ("Light Gray", "#E5E5E5"),
        ("Kraft Brown", "#D4B895"),
        ("Charcoal", "#333333"),
        ("Midnight Blue", "#1A233A"),
        ("Black", "#0F0F0E")
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "#0F0F0E").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        coverPreviewSection
                        
                        nameSection
                        
                        canvasTypeSection
                        
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
                            .foregroundColor(Color(hex: "#0F0F0E"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(hex: "#C9A84C"))
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .padding(.top, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#0F0F0E").opacity(0), Color(hex: "#0F0F0E")],
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
            .toolbarBackground(Color(hex: "#0F0F0E"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    .fill(Color(hex: selectedBgColorHex))
                
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
                .foregroundColor(.white)
                .padding(16)
                .background(Color(hex: "#1A1A1A"))
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
                    .foregroundColor(isSelected ? Color(hex: "#C9A84C") : .white)
                
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 15))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.custom("PlusJakartaSans-Medium", size: 12))
                    .foregroundColor(Color.white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#1A1A1A"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color(hex: "#C9A84C") : Color.clear, lineWidth: 2)
            )
        }
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
                                    .fill(Color(hex: "#1A1A1A"))
                                
                                Image(systemName: pattern.icon)
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(isSelected ? Color(hex: "#C9A84C") : .white.opacity(0.7))
                            }
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color(hex: "#C9A84C") : Color.clear, lineWidth: 2)
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
                                    .fill(Color(hex: bg.hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#C9A84C"))
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
                .foregroundColor(Color(hex: "#C9A84C"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(hex: "#C9A84C").opacity(0.1))
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
                                .stroke(Color.white.opacity(0.2), style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .background(Color.white.opacity(0.02))
                            
                            Image(systemName: "plus")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(height: 150)
                        
                        Text("Import Template")
                            .font(.custom("PlusJakartaSans-Medium", size: 13))
                            .foregroundColor(.white)
                            .padding(.top, 4)
                        
                        Text("PDF or Image")
                            .font(.custom("PlusJakartaSans-Medium", size: 11))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Text("Canvas size is set by the template's dimensions.")
                .font(.custom("PlusJakartaSans-Medium", size: 12))
                .foregroundColor(Color.white.opacity(0.4))
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
                        .fill(Color(hex: "#1A1A1A"))
                    
                    Image(systemName: template.icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(height: 150)
                
                Text(template.name)
                    .font(.custom("PlusJakartaSans-Medium", size: 13))
                    .foregroundColor(.white)
                    .padding(.top, 4)
                
                Text(template.sizeName)
                    .font(.custom("PlusJakartaSans-Medium", size: 11))
                    .foregroundColor(Color.white.opacity(0.4))
            }
        }
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.custom("PlusJakartaSans-Medium", size: 12))
            .foregroundColor(Color.white.opacity(0.4))
            .padding(.horizontal, 24)
    }
    
    // MARK: - Helpers
    
    private func isDarkColor(hex: String) -> Bool {
        let darkColors = ["#333333", "#1A233A", "#0F0F0E"]
        return darkColors.contains(hex.uppercased())
    }
    
    private func createNotebook() {
        Task {
            guard let userId = authViewModel.currentUserId else { return }
            _ = await viewModel.createNotebook(
                userId: userId,
                name: name.isEmpty ? "Untitled Notebook" : name
            )
            dismiss()
        }
    }
}

