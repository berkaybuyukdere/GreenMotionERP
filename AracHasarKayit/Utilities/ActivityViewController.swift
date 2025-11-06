import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        // Filter out invalid URLs and ensure file access
        let validItems = activityItems.compactMap { item -> Any? in
            if let url = item as? URL {
                // Ensure file exists and is accessible
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("⚠️ File does not exist at path: \(url.path)")
                    return nil
                }
                
                // Start accessing security-scoped resource if needed
                if url.startAccessingSecurityScopedResource() {
                    // File is accessible, return it
                    return url
                } else {
                    // Try without security scope (for app's own files)
                    return url
                }
            }
            return item
        }
        
        guard !validItems.isEmpty else {
            print("❌ No valid items to share")
            return UIActivityViewController(activityItems: [], applicationActivities: nil)
        }
        
        let controller = UIActivityViewController(activityItems: validItems, applicationActivities: applicationActivities)
        
        // Configure for iPad
        if let popover = controller.popoverPresentationController {
            // Get the current window scene for iPad support
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window.rootViewController?.view
            }
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Handle completion
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            // Stop accessing security-scoped resources
            for item in validItems {
                if let url = item as? URL {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if let error = error {
                print("❌ Share error: \(error.localizedDescription)")
            } else if completed {
                print("✅ Share completed: \(activityType?.rawValue ?? "unknown")")
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}
