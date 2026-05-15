import SwiftUI
import UIKit

/// GoodNotes-style screenshot preview sheet.
/// Presented modally from the lasso overlay when the user taps Screenshot.
struct LassoScreenshotPreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background — matches GoodNotes aesthetic
                Color.black.opacity(0.92).ignoresSafeArea()
                
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    // Image card with white background and shadow
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                        .padding(32)
                }
            }
            .navigationTitle("Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [image])
                .presentationDetents([.medium, .large])
        }
    }
}

/// UIActivityViewController wrapper for the share sheet.
/// Separate from the existing ShareSheet in SettingsView to avoid file coupling.
private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
