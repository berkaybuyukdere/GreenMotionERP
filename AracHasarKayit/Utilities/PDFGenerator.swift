import UIKit
import PDFKit

class PDFGenerator {
    static let shared = PDFGenerator()
    
    private init() {}
    
    private func isTurkeyPDF(franchiseId: String?) -> Bool {
        let normalizedFranchise = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalizedFranchise.hasPrefix("TR") { return true }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased() == "TR"
    }

    private func isGermanyPDF(franchiseId: String?) -> Bool {
        let f = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if f.hasPrefix("DE") { return true }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased() == "DE"
    }

    private func isSabihaGokcenPDF(franchiseId: String?) -> Bool {
        let f = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return f.contains("SABIHA") || f.contains("SAW")
    }

    private func isSwitzerlandPDF(franchiseId: String?) -> Bool {
        let f = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if f.hasPrefix("CH") { return true }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased() == "CH"
    }

    private func reservationCodeFieldLabel(franchiseId: String?) -> String {
        if isTurkeyPDF(franchiseId: franchiseId) { return "NAV Code" }
        if isGermanyPDF(franchiseId: franchiseId) { return "RNT Code" }
        return "RES Code"
    }

    /// Strips known prefixes and applies a single canonical prefix (never "RES-RNT").
    private func displayReservationCode(_ raw: String, franchiseId: String?) -> String {
        var c = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let upper = c.uppercased()
        for p in ["RES-", "RNT-", "NAV-"] {
            if upper.hasPrefix(p) {
                c = String(c.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if c.isEmpty { return "" }
        if isTurkeyPDF(franchiseId: franchiseId) { return "NAV-\(c)" }
        if isGermanyPDF(franchiseId: franchiseId) { return "RNT-\(c)" }
        return "RES-\(c)"
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

    private func drawUSaveLogoIfNeeded(franchiseId: String?, in rect: CGRect) {
        guard isSabihaGokcenPDF(franchiseId: franchiseId),
              let logo = UIImage(named: "usave_logo") else { return }
        logo.draw(in: rect)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func generateHasarPDF(
        hasar: HasarKaydi,
        aracPlaka: String,
        aracKM: Int,
        vehicleBrand: String = "",
        vehicleModel: String = "",
        language: PDFContentLanguage = .automatic,
        completion: @escaping (URL?) -> Void
    ) {
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
                vehicleBrand: vehicleBrand,
                vehicleModel: vehicleModel,
                images: orderedTuples,
                language: language
            )
            completion(pdfURL)
        }
    }
    
    private func createPDF(
        hasar: HasarKaydi,
        aracPlaka: String,
        aracKM: Int,
        vehicleBrand: String,
        vehicleModel: String,
        images: [(image: UIImage, isHandover: Bool)],
        language: PDFContentLanguage
    ) -> URL? {
        if isSwitzerlandPDF(franchiseId: hasar.franchiseId) {
            return writeSwitzerlandPDF(
                hasar: hasar,
                aracPlaka: aracPlaka,
                vehicleBrand: vehicleBrand,
                vehicleModel: vehicleModel,
                images: images
            )
        }

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
            let isTurkeyLayout = isTurkeyPDF(franchiseId: hasar.franchiseId)
            let resolvedLanguage = language.resolved(forTurkeyFranchise: isTurkeyLayout)
            
            context.beginPage()
            
            // BAŞLIK
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = resolvedLanguage == .turkish ? "Hasar Raporu" : "Damage Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            drawUSaveLogoIfNeeded(
                franchiseId: hasar.franchiseId,
                in: CGRect(x: pageWidth - margin - 108, y: yPosition - 2, width: 108, height: 36)
            )
            yPosition += 40
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            
            let resLine = displayReservationCode(hasar.resKodu, franchiseId: hasar.franchiseId)
            let resLabel = reservationCodeFieldLabel(franchiseId: hasar.franchiseId)
            // BİLGİLER (KM omitted from PDF header per product policy)
            let info = """
            Plate: \(aracPlaka)
            \(resLabel): \(resLine)
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
                
                let labelDate = isHandover ? dateFormatter.string(from: hasar.handoverTarihi) : dateFormatter.string(from: hasar.tarih)
                if isTurkeyLayout {
                    let timestampAttributes: [NSAttributedString.Key: Any] = [
                        .font: SwissPDFHelper.helveticaBold(size: 11),
                        .foregroundColor: UIColor.systemGreen
                    ]
                    let timestampRect = CGRect(x: xPosition + 10, y: yPosition + 10, width: imageWidth - 20, height: 24)
                    labelDate.draw(in: timestampRect, withAttributes: timestampAttributes)
                } else {
                    let labelText = isHandover ? "HANDOVER" : "RETURN"
                    let fullLabel = "\(labelText)\n\(labelDate)"
                    let labelAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: UIColor.red
                    ]
                    let labelSize = fullLabel.boundingRect(
                        with: CGSize(width: fittedRect.width - 20, height: 100),
                        options: [.usesLineFragmentOrigin],
                        attributes: labelAttributes,
                        context: nil
                    ).size
                    let labelX = fittedRect.origin.x + fittedRect.width - labelSize.width - 10
                    let labelY = fittedRect.origin.y + fittedRect.height - labelSize.height - 10
                    let labelRect = CGRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)
                    fullLabel.draw(in: labelRect, withAttributes: labelAttributes)
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
        }
        
        let fileBase = Validators.damageReportExportFileBase(resKodu: hasar.resKodu, fallbackDate: hasar.tarih)
        let filename = "\(fileBase).pdf"
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

    private func writeSwitzerlandPDF(
        hasar: HasarKaydi,
        aracPlaka: String,
        vehicleBrand: String,
        vehicleModel: String,
        images: [(image: UIImage, isHandover: Bool)]
    ) -> URL? {
        let resLine = displayReservationCode(hasar.resKodu, franchiseId: hasar.franchiseId)
        let resLabel = reservationCodeFieldLabel(franchiseId: hasar.franchiseId)
        guard let pdfData = SwitzerlandDamageReportPDFLayout.render(
            hasar: hasar,
            aracPlaka: aracPlaka,
            vehicleBrand: vehicleBrand,
            vehicleModel: vehicleModel,
            resCodeLine: resLine,
            resLabel: resLabel,
            images: images
        ) else { return nil }

        let fileBase = Validators.damageReportExportFileBase(resKodu: hasar.resKodu, fallbackDate: hasar.tarih)
        let filename = "\(fileBase).pdf"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        do {
            try pdfData.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ CH PDF kaydetme hatası: \(error)")
            return nil
        }
    }
}
