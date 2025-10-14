import UIKit
import PDFKit

class PDFGenerator {
    static let shared = PDFGenerator()
    
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func generateHasarPDF(hasar: HasarKaydi, aracPlaka: String, aracKM: Int, completion: @escaping (URL?) -> Void) {
        guard !hasar.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        // Fotoğrafları Firebase'den indir
        let dispatchGroup = DispatchGroup()
        var downloadedImages: [(image: UIImage, isHandover: Bool)] = []
        
        for (index, urlString) in hasar.fotograflar.enumerated() {
            dispatchGroup.enter()
            
            FirebaseImageManager.shared.loadImage(urlString) { image in
                if let image = image {
                    let isHandover = index == 0
                    downloadedImages.append((image: image, isHandover: isHandover))
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            guard !downloadedImages.isEmpty else {
                completion(nil)
                return
            }
            
            // PDF oluştur
            let pdfURL = self.createPDF(
                hasar: hasar,
                aracPlaka: aracPlaka,
                aracKM: aracKM,
                images: downloadedImages
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
            let margin: CGFloat = 30
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.75
            
            context.beginPage()
            
            // TITLE
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
            
            // INFO
            let info = """
            Plate: \(aracPlaka)
            RES Code: \(hasar.resKodu)
            KM: \(aracKM)
            Date: \(dateFormatter.string(from: hasar.tarih))
            Handover Date: \(dateFormatter.string(from: hasar.handoverTarihi))
            """
            
            info.draw(in: CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: 100), withAttributes: infoAttributes)
            yPosition += 120
            
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
                
                let imageRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                image.draw(in: imageRect)
                
                // Sadece label'da tarih
                let labelText = isHandover ? "HANDOVER" : "RETURN"
                let labelDate = isHandover ? dateFormatter.string(from: hasar.handoverTarihi) : dateFormatter.string(from: Date())
                let fullLabel = "\(labelText)\n\(labelDate)"
                
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 11),
                    .foregroundColor: UIColor.red
                ]
                
                let labelRect = CGRect(x: xPosition + 10, y: yPosition + imageHeight - 45, width: imageWidth - 20, height: 40)
                fullLabel.draw(in: labelRect, withAttributes: labelAttributes)
                
                columnCount += 1
                
                if columnCount == 2 {
                    yPosition += imageHeight + 20
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
            HapticManager.shared.pdfGenerated()  // PDF HAPTIC
            return fileURL
        } catch {
            print("❌ PDF kaydetme hatası: \(error)")
            HapticManager.shared.error()  // ERROR HAPTIC
            return nil
        }
    }
}
