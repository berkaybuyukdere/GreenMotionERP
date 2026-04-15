import UIKit
import PDFKit

class ExitPDFGenerator {
    static let shared = ExitPDFGenerator()
    
    private init() {}
    
    private func normalizedSignatureForPDF(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
    
    private func isTurkeyPDF(franchiseId: String?) -> Bool {
        let normalizedFranchise = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalizedFranchise.hasPrefix("TR") { return true }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased() == "TR"
    }
    
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
        let storageImageLoader = StorageImageLoader.shared
        var resolvedSignatureImage: UIImage?
        
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
        
        if let signatureURL = exit.customerSignatureURL,
           !signatureURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dispatchGroup.enter()
            storageImageLoader.loadImage(from: signatureURL) { image in
                resolvedSignatureImage = image
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
                images: sortedImages,
                signatureImage: resolvedSignatureImage
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(exit: ExitIslemi, arac: Arac, images: [UIImage], signatureImage: UIImage?) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            var yPosition: CGFloat = 50
            let margin: CGFloat = 25
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.70
            let isTurkeyLayout = isTurkeyPDF(franchiseId: exit.franchiseId)
            
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
                
                if isTurkeyLayout {
                    let timestamp = "\(dateFormatter.string(from: exit.exitTarihi))"
                    let timestampAttributes: [NSAttributedString.Key: Any] = [
                        .font: SwissPDFHelper.helveticaBold(size: 11),
                        .foregroundColor: UIColor.systemGreen
                    ]
                    let timestampRect = CGRect(x: xPosition + 8, y: yPosition + 8, width: imageWidth - 16, height: 22)
                    timestamp.draw(in: timestampRect, withAttributes: timestampAttributes)
                } else {
                    // Keep non-TR overlay behavior unchanged.
                    let stampText = "\(exit.aracPlaka)\n\(arac.marka) \(arac.model)\n\(dateFormatter.string(from: exit.exitTarihi))"
                    let stampAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 10),
                        .foregroundColor: UIColor.white,
                        .strokeColor: UIColor.black,
                        .strokeWidth: -2.5
                    ]
                    let stampRect = CGRect(x: xPosition + 8, y: yPosition + 8, width: imageWidth - 16, height: 50)
                    stampText.draw(in: stampRect, withAttributes: stampAttributes)
                }
                
                columnCount += 1
                
                if columnCount == 2 {
                    yPosition += imageHeight + 15
                    xPosition = margin
                    columnCount = 0
                } else {
                    xPosition = margin + imageWidth + margin
                }
            }
            
            // If last row has one image, advance to next row before adding signature block.
            if columnCount == 1 {
                yPosition += imageHeight + 15
                xPosition = margin
                columnCount = 0
            }
            
            if let signatureImage {
                let cg = context.cgContext
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helveticaBold(size: 10),
                    .foregroundColor: SwissPDFHelper.black
                ]
                let infoAttributes: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helvetica(size: 12),
                    .foregroundColor: SwissPDFHelper.darkGray
                ]
                
                let sectionHeight: CGFloat = 128
                if yPosition + sectionHeight > pageHeight - margin - 30 {
                    addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                    context.beginPage()
                    yPosition = 50
                }
                
                yPosition += 8
                "CUSTOMER SIGNATURE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                yPosition += 14
                
                let signatureRect = CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: 80)
                let signaturePath = UIBezierPath(roundedRect: signatureRect, cornerRadius: 8)
                cg.setFillColor(UIColor.white.cgColor)
                cg.addPath(signaturePath.cgPath)
                cg.fillPath()
                cg.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
                cg.setLineWidth(1)
                cg.addPath(signaturePath.cgPath)
                cg.strokePath()
                
                let normalizedSignature = normalizedSignatureForPDF(signatureImage)
                let fittedSignatureRect = aspectFitRect(imageSize: normalizedSignature.size, in: signatureRect.insetBy(dx: 8, dy: 8))
                normalizedSignature.draw(in: fittedSignatureRect)
                yPosition += 88
                
                "PLATE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                exit.aracPlaka.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
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

