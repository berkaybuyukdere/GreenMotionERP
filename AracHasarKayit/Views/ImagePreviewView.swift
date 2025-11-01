import SwiftUI

struct ImagePreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale *= delta
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        if scale < 1.0 {
                                            withAnimation {
                                                scale = 1.0
                                                offset = .zero
                                            }
                                        } else if scale > 4.0 {
                                            withAnimation {
                                                scale = 4.0
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1.0 {
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) { location in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    let tapX = location.x - geometry.size.width / 2
                                    let tapY = location.y - geometry.size.height / 2
                                    offset = CGSize(width: -tapX, height: -tapY)
                                    lastOffset = offset
                                }
                            }
                        }
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .navigationTitle("Photo Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

enum PhotoPreviewItem: Identifiable {
    case url(String)
    case image(UIImage)
    
    var id: String {
        switch self {
        case .url(let url): return url
        case .image(let img): return img.hashValue.description
        }
    }
}

// MARK: - Camera View for Office Returns
struct OfficeReturnCameraView: View {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        OfficeReturnCameraViewController(capturedImage: $capturedImage)
            .ignoresSafeArea()
    }
}

struct OfficeReturnCameraViewController: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OfficeReturnCameraViewController
        
        init(_ parent: OfficeReturnCameraViewController) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

