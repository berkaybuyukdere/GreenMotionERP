import SwiftUI
import PencilKit

struct PhotoEditorView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var showingSaveSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                CanvasViewRepresentable(canvasView: $canvasView, toolPicker: $toolPicker, image: image)
                    .edgesIgnoringSafeArea(.all)
            }
            .navigationTitle("Fotoğraf Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("İptal") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Temizle butonu
                        Button {
                            canvasView.drawing = PKDrawing()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                        }
                        
                        // Kaydet butonu
                        Button {
                            saveEditedImage()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .alert("Kaydedildi", isPresented: $showingSaveSuccess) {
                Button("Tamam", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Fotoğraf başarıyla galerinize kaydedildi.")
            }
        }
    }
    
    func saveEditedImage() {
        // Canvas'ı görüntüyle birleştir
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let editedImage = renderer.image { context in
            // Orijinal görüntüyü çiz
            image.draw(at: .zero)
            
            // Canvas çizimini üzerine ekle
            let drawing = canvasView.drawing
            let imageRect = CGRect(origin: .zero, size: image.size)
            drawing.image(from: imageRect, scale: UIScreen.main.scale).draw(in: imageRect)
        }
        
        // Tarih ve saat ekle
        let finalImage = addTimestamp(to: editedImage)
        
        // Galeriye kaydet
        UIImageWriteToSavedPhotosAlbum(finalImage, nil, nil, nil)
        showingSaveSuccess = true
    }
    
    func addTimestamp(to image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // Orijinal resmi çiz
            image.draw(at: .zero)
            
            // Tarih ve saat
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
            let timestamp = dateFormatter.string(from: Date())
            
            // Metin özellikleri
            let fontSize = min(image.size.width * 0.04, 40)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.0
            ]
            
            // Sağ alt köşeye yerleştir
            let textSize = timestamp.size(withAttributes: attributes)
            let padding = image.size.width * 0.03
            let textPoint = CGPoint(
                x: image.size.width - textSize.width - padding,
                y: image.size.height - textSize.height - padding
            )
            
            // Arka plan
            let backgroundRect = CGRect(
                x: textPoint.x - 10,
                y: textPoint.y - 5,
                width: textSize.width + 20,
                height: textSize.height + 10
            )
            let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 5)
            UIColor.black.withAlphaComponent(0.6).setFill()
            path.fill()
            
            // Metni çiz
            timestamp.draw(at: textPoint, withAttributes: attributes)
        }
    }
}

struct CanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    let image: UIImage
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        
        // Arka plan olarak görüntüyü ekle
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = canvasView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.insertSubview(imageView, at: 0)
        
        // Tool picker'ı göster
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
