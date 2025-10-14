import UIKit

class ImageManager {
    static let shared = ImageManager()
    
    private init() {}
    
    private let maxImageSize: CGFloat = 1600
    private let compressionQuality: CGFloat = 0.75
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func saveImage(_ image: UIImage, withDate date: Date = Date(), isHandover: Bool = false) -> String? {
        guard let resizedImage = smartResize(image, maxSize: maxImageSize) else {
            print("Görüntü yeniden boyutlandırılamadı")
            return nil
        }
        
        guard let watermarkedImage = addWatermark(to: resizedImage, date: date, isHandover: isHandover) else {
            print("Watermark eklenemedi")
            return nil
        }
        
        let filename = UUID().uuidString + ".jpg"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        guard let data = watermarkedImage.jpegData(compressionQuality: compressionQuality) else {
            print("JPEG verisi oluşturulamadı")
            return nil
        }
        
        do {
            try data.write(to: fileURL)
            let sizeKB = data.count / 1024
            print("✅ Resim kaydedildi: \(filename), Boyut: \(sizeKB) KB")
            return filename
        } catch {
            print("❌ Resim kaydetme hatası: \(error)")
            return nil
        }
    }
    
    func loadImage(_ filename: String) -> UIImage? {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    func deleteImage(_ filename: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func deleteImages(_ filenames: [String]) {
        filenames.forEach { deleteImage($0) }
    }
    
    private func smartResize(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        let widthRatio = maxSize / size.width
        let heightRatio = maxSize / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func addWatermark(to image: UIImage, date: Date, isHandover: Bool) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        
        let watermarkedImage = renderer.image { context in
            image.draw(at: .zero)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            let dateString = dateFormatter.string(from: date)
            
            // SADECE TARİH - GREEN MOTION AG KALDIRILDI
            let text = dateString
            
            let fontSize = min(image.size.width * 0.035, 36)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .strokeColor: UIColor.black,
                .strokeWidth: -2.5
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let padding = image.size.width * 0.025
            let textRect = CGRect(
                x: padding,
                y: padding,
                width: textSize.width,
                height: textSize.height
            )
            
            let backgroundRect = textRect.insetBy(dx: -8, dy: -4)
            let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 6)
            UIColor.black.withAlphaComponent(0.6).setFill()
            path.fill()
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        return watermarkedImage
    }
}
