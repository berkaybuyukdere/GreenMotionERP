import UIKit
import PDFKit

class PDFGenerator {
    static let shared = PDFGenerator()
    
    private init() {}
    
    private func aspectFitRect(imageSize: CGSize, in boundingRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return boundingRect }
        let imageAspect = imageSize.width / imageSize.height
        let rectAspect = boundingRect.width / boundingRect.height

        var drawSize = CGSize.zero
        if imageAspect > rectAspect {
            // Genişlik sınır
            drawSize.width = boundingRect.width
            drawSize.height = boundingRect.width / imageAspect
        } else {
            // Yükseklik sınır
            drawSize.height = boundingRect.height
            drawSize.width = boundingRect.height * imageAspect
        }

        let origin = CGPoint(
            x: boundingRect.origin.x + (boundingRect.width - drawSize.width) / 2,
            y: boundingRect.origin.y + (boundingRect.height - drawSize.height) / 2
        )
        return CGRect(origin: origin, size: drawSize)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func generateHasarPDF(hasar: HasarKaydi, aracPlaka: String, aracKM: Int, completion: @escaping (URL?) -> Void) {
        guard !hasar.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        let imageManager = CachedImageManager.shared
        // ✅ İndirme sırasını sabitlemek için index bilgisiyle topla
        var downloadedWithIndex: [(index: Int, image: UIImage)] = []

        for (index, urlString) in hasar.fotograflar.enumerated() {
            dispatchGroup.enter()
            imageManager.loadImage(urlString) { (image: UIImage?) in
                if let image = image {
                    downloadedWithIndex.append((index: index, image: image))
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            guard !downloadedWithIndex.isEmpty else {
                completion(nil)
                return
            }
            
            // ✅ Diziyi indeksine göre sırala; 0.daima handover
            let orderedTuples: [(image: UIImage, isHandover: Bool)] = downloadedWithIndex
                .sorted(by: { $0.index < $1.index })
                .map { (image: $0.image, isHandover: $0.index == 0) }
            
            let pdfURL = self.createPDF(
                hasar: hasar,
                aracPlaka: aracPlaka,
                aracKM: aracKM,
                images: orderedTuples
            )
            completion(pdfURL)
        }
    }
    
    private func createPDF(hasar: HasarKaydi, aracPlaka: String, aracKM: Int, images: [(image: UIImage, isHandover: Bool)]) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            var yPosition: CGFloat = 50
            let margin: CGFloat = 25
            // LANDSCAPE ASPECT: Make photos wider (1.5:1 aspect ratio for landscape orientation)
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth / 1.5  // Landscape aspect ratio
            
            context.beginPage()
            
            // BAŞLIK
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Damage Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            
            // BİLGİLER
            let info = """
            Plate: \(aracPlaka)
            RES Code: \(hasar.resKodu)
            KM: \(aracKM)
            Date: \(dateFormatter.string(from: hasar.tarih))
            Handover Date: \(dateFormatter.string(from: hasar.handoverTarihi))
            """
            
            info.draw(in: CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: 100), withAttributes: infoAttributes)
            yPosition += 110
            
            var xPosition: CGFloat = margin
            var columnCount = 0
            
            for imageData in images {
                let image = imageData.image
                let isHandover = imageData.isHandover
                
                if yPosition + imageHeight + 50 > pageHeight - margin {
                    context.beginPage()
                    yPosition = 50
                    xPosition = margin
                    columnCount = 0
                }
                
                let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)

                // Draw the image with high quality
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high
                image.draw(in: fittedRect)
                
                // LABEL INSIDE PHOTO - RED COLOR, BOTTOM RIGHT, NO BACKGROUND
                let labelText = isHandover ? "HANDOVER" : "RETURN"
                let labelDate = isHandover ? dateFormatter.string(from: hasar.handoverTarihi) : dateFormatter.string(from: hasar.tarih)
                let fullLabel = "\(labelText)\n\(labelDate)"
                
                // Red text without background - positioned at the BOTTOM RIGHT INSIDE the photo
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: UIColor.red
                ]
                
                // Calculate label size
                let labelSize = fullLabel.boundingRect(
                    with: CGSize(width: fittedRect.width - 20, height: 100),
                    options: [.usesLineFragmentOrigin],
                    attributes: labelAttributes,
                    context: nil
                ).size
                
                // Position at BOTTOM RIGHT of the fitted image
                let labelX = fittedRect.origin.x + fittedRect.width - labelSize.width - 10
                let labelY = fittedRect.origin.y + fittedRect.height - labelSize.height - 10
                let labelRect = CGRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)
                
                fullLabel.draw(in: labelRect, withAttributes: labelAttributes)
                
                columnCount += 1
                
                if columnCount == 2 {
                    yPosition += imageHeight + 15
                    xPosition = margin
                    columnCount = 0
                } else {
                    xPosition = margin + imageWidth + margin
                }
            }
        }
        
        let filename = "damage_report_\(Date().timeIntervalSince1970).pdf"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try pdfData.write(to: fileURL)
            print("✅ PDF kaydedildi: \(fileURL.path)")
            return fileURL
        } catch {
            print("❌ PDF kaydetme hatası: \(error)")
            return nil
        }
    }
}
