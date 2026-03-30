import UIKit
import PDFKit

class IadePDFGenerator {
    static let shared = IadePDFGenerator()
    static let returnConfirmationText = """
Dear Customer,

Thank you for choosing Green Motion.

We hereby confirm that you have successfully returned the vehicle at our Hofwiesenstrasse 36 location.

This message serves as the official confirmation of your vehicle return. Please note that the final vehicle inspection may take up to four days. Should any irregularities be identified during this process, we will contact you accordingly.

If you have any further questions, please do not hesitate to contact us.

Kind regards,

Your Green Motion Zurich Team
"""
    
    private init() {}
    
    // Downscales images before embedding into PDF to keep
    // attachment size reliable for SMTP limits and first-try delivery.
    private func optimizedImageForPDF(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1800
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return image }
        
        let largestSide = max(width, height)
        let scaleRatio = min(1.0, maxDimension / largestSide)
        let targetSize = CGSize(width: floor(width * scaleRatio), height: floor(height * scaleRatio))
        guard targetSize.width > 1, targetSize.height > 1 else { return image }
        
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        
        // Convert to JPEG to avoid very large PNG payloads.
        if let jpegData = resized.jpegData(compressionQuality: 0.68),
           let compressed = UIImage(data: jpegData) {
            return compressed
        }
        return resized
    }
    
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
    
    func generateIadePDF(iade: IadeIslemi, arac: Arac, signatureImageOverride: UIImage? = nil, completion: @escaping (URL?) -> Void) {
        guard !iade.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        var resolvedSignatureImage: UIImage? = signatureImageOverride
        
        // IMPORTANT:
        // CachedImageManager uses URLSession and may fail for Firebase Storage URLs that require
        // Storage fallback / authenticated retrieval. UI image rendering uses StorageImageLoader,
        // so we must use the same loader to keep PDF photo count consistent.
        let imageLoader = StorageImageLoader.shared
        
        // SIRALI İNDİRME - İndeksleri koruyarak
        for (index, urlString) in iade.fotograflar.enumerated() {
            dispatchGroup.enter()
            
            imageLoader.loadImage(from: urlString) { image in
                defer { dispatchGroup.leave() }
                guard let image else { return }
                downloadedImagesWithIndex.append((image: image, index: index))
            }
        }
        
        if resolvedSignatureImage == nil,
           let signatureURL = iade.customerSignatureURL {
            dispatchGroup.enter()
            imageLoader.loadImage(from: signatureURL) { image in
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
            let sortedImages = downloadedImagesWithIndex
                .sorted { $0.index < $1.index }
                .map { self.optimizedImageForPDF($0.image) }
            
            let pdfURL = self.createPDF(
                iade: iade,
                arac: arac,
                images: sortedImages,
                signatureImage: resolvedSignatureImage
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(iade: IadeIslemi, arac: Arac, images: [UIImage], signatureImage: UIImage?) -> URL? {
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
            yPosition += 48
            
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
            
            yPosition += 8
            
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
                
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)

                // (opsiyonel) PDF çıktısını keskinleştirmek için:
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high

                image.draw(in: fittedRect)
                
                // LABEL - SADECE TEXT (ARKA PLAN YOK)
                let labelText = "Photo \(index + 1)"
                let labelDate = dateFormatter.string(from: iade.iadeTarihi)
                let fullLabel = "\(labelText)\n\(labelDate)"
                
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helveticaBold(size: 11),
                    .foregroundColor: UIColor.systemGreen
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
            
            // If last row has a single image, move yPosition to next row to avoid overlap.
            if columnCount == 1 {
                yPosition += imageHeight + 15
                xPosition = margin
                columnCount = 0
            }
            
            let trimmedName = iade.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedEmail = (iade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCustomerSection = signatureImage != nil || !trimmedEmail.isEmpty
            
            if hasCustomerSection {
                let sectionHeight: CGFloat = 170
                if yPosition + sectionHeight > pageHeight - margin {
                    context.beginPage()
                    yPosition = 32
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
                
                if let signatureImage = signatureImage {
                    let normalizedSignature = normalizedSignatureForPDF(signatureImage)
                    let fittedSignatureRect = aspectFitRect(imageSize: normalizedSignature.size, in: signatureRect.insetBy(dx: 8, dy: 8))
                    normalizedSignature.draw(in: fittedSignatureRect)
                }
                yPosition += 88
                
                "NAME".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                trimmedName.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
                yPosition += 18
                "EMAIL".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                trimmedEmail.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
                yPosition += 20
            }

            let noteParagraphStyle = NSMutableParagraphStyle()
            noteParagraphStyle.lineSpacing = 2
            let noteAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helvetica(size: 10),
                .foregroundColor: SwissPDFHelper.darkGray,
                .paragraphStyle: noteParagraphStyle
            ]
            let noteText = IadePDFGenerator.returnConfirmationText
            let noteWidth = pageWidth - (2 * margin)
            let noteMeasuredHeight = ceil((noteText as NSString).boundingRect(
                with: CGSize(width: noteWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: noteAttributes,
                context: nil
            ).height)
            let noteTotalHeight = 14 + noteMeasuredHeight + 8

            if yPosition + noteTotalHeight > pageHeight - margin {
                context.beginPage()
                yPosition = 32
            }

            "NOTE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            yPosition += 14
            (noteText as NSString).draw(
                in: CGRect(x: margin, y: yPosition, width: noteWidth, height: noteMeasuredHeight + 4),
                withAttributes: noteAttributes
            )
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
