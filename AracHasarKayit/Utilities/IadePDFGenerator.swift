import UIKit
import PDFKit

class IadePDFGenerator {
    static let shared = IadePDFGenerator()
    
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func generateIadePDF(iade: IadeIslemi, arac: Arac, completion: @escaping (URL?) -> Void) {
        guard !iade.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImages: [UIImage] = []
        
        let imageManager = FirebaseImageManager.shared
        
        for urlString in iade.fotograflar {
            dispatchGroup.enter()
            
            imageManager.loadImage(urlString) { (image: UIImage?) in
                if let image = image {
                    downloadedImages.append(image)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            guard !downloadedImages.isEmpty else {
                completion(nil)
                return
            }
            
            let pdfURL = self.createPDF(
                iade: iade,
                arac: arac,
                images: downloadedImages
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(iade: IadeIslemi, arac: Arac, images: [UIImage]) -> URL? {
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
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Return Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
            
            var info = """
            Plate: \(iade.aracPlaka)
            Vehicle: \(arac.marka) \(arac.model)
            Return Date: \(dateFormatter.string(from: iade.iadeTarihi))
            """
            
            if !iade.notlar.isEmpty {
                info += "\nNotes: \(iade.notlar)"
            }
            
            info.draw(in: CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: 100), withAttributes: infoAttributes)
            yPosition += 120
            
            var xPosition: CGFloat = margin
            var columnCount = 0
            
            for (index, image) in images.enumerated() {
                if yPosition + imageHeight + 50 > pageHeight - margin {
                    context.beginPage()
                    yPosition = 50
                    xPosition = margin
                    columnCount = 0
                }
                
                let imageRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                image.draw(in: imageRect)
                
                let labelText = "Photo \(index + 1)"
                let labelDate = dateFormatter.string(from: iade.iadeTarihi)
                let fullLabel = "\(labelText)\n\(labelDate)"
                
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 11),
                    .foregroundColor: UIColor.blue
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
        
        let filename = "return_report_\(Date().timeIntervalSince1970).pdf"
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
