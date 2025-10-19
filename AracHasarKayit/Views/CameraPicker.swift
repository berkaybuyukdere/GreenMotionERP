import SwiftUI
import UIKit
import AVFoundation

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIViewController {
        // Use the new landscape-optimized camera view
        let landscapeCameraView = LandscapeCameraView(selectedImage: $selectedImage)
        let hostingController = UIHostingController(rootView: landscapeCameraView)
        hostingController.modalPresentationStyle = .fullScreen
        
        return hostingController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No additional updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.selectedImage = image
            parent.dismiss()
        }
        
        func didCancel() {
            parent.dismiss()
        }
    }
}
