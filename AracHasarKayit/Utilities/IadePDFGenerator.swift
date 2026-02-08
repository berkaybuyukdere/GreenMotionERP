import UIKit
import PDFKit

class IadePDFGenerator {
    static let shared = IadePDFGenerator()
    
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
    
    func generateIadePDF(iade: IadeIslemi, arac: Arac, completion: @escaping (URL?) -> Void) {
        guard !iade.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        
        let imageManager = CachedImageManager.shared
        
        // SIRALI İNDİRME - İndeksleri koruyarak
        for (index, urlString) in iade.fotograflar.enumerated() {
            dispatchGroup.enter()
            
            imageManager.loadImage(urlString) { (image: UIImage?) in
                if let image = image {
                    downloadedImagesWithIndex.append((image: image, index: index))
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            guard !downloadedImagesWithIndex.isEmpty else {
                completion(nil)
                return
            }
            
            // SIRALI DÜZENLEME - İndekse göre sırala
            let sortedImages = downloadedImagesWithIndex.sorted { $0.index < $1.index }.map { $0.image }
            
            let pdfURL = self.createPDF(
                iade: iade,
                arac: arac,
                images: sortedImages
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
            var yPosition: CGFloat = 32
            let margin: CGFloat = 24
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.68
            
            context.beginPage()
            let cg = context.cgContext
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 30),
                .foregroundColor: SwissPDFHelper.black
            ]
            NSString(string: "Return").draw(
                in: CGRect(x: margin, y: yPosition, width: 220, height: 36),
                withAttributes: titleAttributes
            )
            yPosition += 42
            SwissPDFHelper.drawHorizontalLine(
                context: cg,
                from: CGPoint(x: margin, y: yPosition),
                to: CGPoint(x: pageWidth - margin, y: yPosition),
                width: 0.75
            )
            yPosition += 14
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helvetica(size: 12),
                .foregroundColor: SwissPDFHelper.darkGray
            ]
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 10),
                .foregroundColor: SwissPDFHelper.black
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
            
            "PLATE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            iade.aracPlaka.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
            yPosition += 18
            "VEHICLE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            "\(arac.marka) \(arac.model)".draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
            yPosition += 18
            "RETURN DATE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            dateFormatter.string(from: iade.iadeTarihi).draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
            yPosition += 18
            "TOTAL PHOTOS".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            "\(images.count)".draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
            yPosition += 20
            
            if !iade.notlar.isEmpty {
                "NOTES".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                iade.notlar.draw(
                    in: CGRect(x: margin + 86, y: yPosition, width: pageWidth - margin - (margin + 86), height: 36),
                    withAttributes: infoAttributes
                )
                yPosition += 44
            }
            
            SwissPDFHelper.drawHorizontalLine(
                context: cg,
                from: CGPoint(x: margin, y: yPosition),
                to: CGPoint(x: pageWidth - margin, y: yPosition),
                width: 0.5
            )
            yPosition += 16
            
            var xPosition: CGFloat = margin
            var columnCount = 0
            
            // SIRALI FOTOĞRAFLAR
            for (index, image) in images.enumerated() {
                if yPosition + imageHeight + 54 > pageHeight - margin {
                    context.beginPage()
                    yPosition = 32
                    xPosition = margin
                    columnCount = 0
                }
                
                let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                let cardRect = slotRect.insetBy(dx: -4, dy: -4)
                let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 10)
                cg.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
                cg.setLineWidth(1)
                cg.addPath(cardPath.cgPath)
                cg.strokePath()
                
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)

                // (opsiyonel) PDF çıktısını keskinleştirmek için:
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high

                image.draw(in: fittedRect)
                
                // LABEL - SADECE TEXT (ARKA PLAN YOK)
                let labelText = "Photo \(index + 1)"
                let labelDate = dateFormatter.string(from: iade.iadeTarihi)
                let fullLabel = "\(labelText)\n\(labelDate)"
                
                // Beyaz yazı + siyah stroke (kontrast için)
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helveticaBold(size: 11),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3.0  // Negatif değer = fill + stroke
                ]
                
                // SOL ÜSTTE LABEL (ARKA PLAN YOK)
                let labelRect = CGRect(x: xPosition + 10, y: yPosition + 10, width: imageWidth - 20, height: 40)
                
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
