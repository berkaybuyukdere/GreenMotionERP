import UIKit
import PDFKit

class ExitPDFGenerator {
    static let shared = ExitPDFGenerator()
    
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
    
    private func addCopyright(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) {
        let copyrightText = PDFExportBranding.copyrightLine
        let copyrightAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        
        let textSize = copyrightText.size(withAttributes: copyrightAttributes)
        let copyrightY = pageHeight - margin - 15
        let copyrightX = (pageWidth - textSize.width) / 2
        
        copyrightText.draw(at: CGPoint(x: copyrightX, y: copyrightY), withAttributes: copyrightAttributes)
    }
    
    func generateExitPDF(exit: ExitIslemi, arac: Arac, completion: @escaping (URL?) -> Void) {
        guard !exit.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        
        let imageManager = CachedImageManager.shared
        
        // SIRALI İNDİRME - İndeksleri koruyarak
        for (index, urlString) in exit.fotograflar.enumerated() {
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
                exit: exit,
                arac: arac,
                images: sortedImages
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(exit: ExitIslemi, arac: Arac, images: [UIImage]) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            var yPosition: CGFloat = 50
            let margin: CGFloat = 25
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.70
            
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Check Out Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            
            var info = """
            Plate: \(exit.aracPlaka)
            Vehicle: \(arac.marka) \(arac.model)
            Check Out Date: \(dateFormatter.string(from: exit.exitTarihi))
            """
            if let km = exit.km {
                info += "\nKM: \(km)"
            }
            if let fuel = normalizedFuelDisplay(exit.yakitSeviyesi) {
                info += "\nFuel: \(fuel)"
            }
            
            if !exit.notlar.isEmpty {
                info += "\nNotes: \(exit.notlar)"
            }
            
            info.draw(in: CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: 90), withAttributes: infoAttributes)
            yPosition += 100
            
            var xPosition: CGFloat = margin
            var columnCount = 0
            
            // SIRALI FOTOĞRAFLAR
            for (index, image) in images.enumerated() {
                if yPosition + imageHeight + 50 > pageHeight - margin - 30 {
                    // Add copyright before new page
                    addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                    
                    context.beginPage()
                    yPosition = 50
                    xPosition = margin
                    columnCount = 0
                }
                
                let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)

                // (opsiyonel) PDF çıktısını keskinleştirmek için:
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high

                image.draw(in: fittedRect)
                
                // STAMP - SOL ÜSTTE ARAÇ BİLGİLERİ (FOTOĞRAFI KAPATMAYACAK ŞEKİLDE)
                let stampText = "\(exit.aracPlaka)\n\(arac.marka) \(arac.model)\n\(dateFormatter.string(from: exit.exitTarihi))"
                
                // Beyaz yazı + siyah stroke (kontrast için)
                let stampAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 10),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -2.5  // Negatif değer = fill + stroke
                ]
                
                // SOL ÜSTTE STAMP (FOTOĞRAFI KAPATMAYACAK ŞEKİLDE - KÜÇÜK)
                let stampRect = CGRect(x: xPosition + 8, y: yPosition + 8, width: imageWidth - 16, height: 50)
                
                stampText.draw(in: stampRect, withAttributes: stampAttributes)
                
                columnCount += 1
                
                if columnCount == 2 {
                    yPosition += imageHeight + 15
                    xPosition = margin
                    columnCount = 0
                } else {
                    xPosition = margin + imageWidth + margin
                }
            }
            
            // Add copyright at the end of last page
            addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
        }
        
        let fn = DateFormatter()
        fn.locale = Locale(identifier: "en_US_POSIX")
        fn.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "exit_report_\(fn.string(from: exit.exitTarihi)).pdf"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try pdfData.write(to: fileURL)
            print("✅ Exit PDF kaydedildi: \(fileURL.path)")
            HapticManager.shared.pdfGenerated()  // PDF HAPTIC
            return fileURL
        } catch {
            print("❌ Exit PDF kaydetme hatası: \(error)")
            HapticManager.shared.error()  // ERROR HAPTIC
            return nil
        }

    }
    
    private func normalizedFuelDisplay(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let numerator = trimmed.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        if let parsed = Int(numerator) {
            return "\(min(8, max(0, parsed)))/8"
        }
        return trimmed
    }
}

