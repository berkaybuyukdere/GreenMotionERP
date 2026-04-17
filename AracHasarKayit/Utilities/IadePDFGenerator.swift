import UIKit
import PDFKit

class IadePDFGenerator {
    static let shared = IadePDFGenerator()

    /// Customer-facing confirmation (PDF + email). Avoids hard-coded trade names; optional franchise display name.
    static func returnConfirmationText(franchiseDisplayName: String = "") -> String {
        let trimmed = franchiseDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeGM = trimmed.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let closing = (trimmed.isEmpty || looksLikeGM) ? "Your rental team" : "Your \(trimmed) team"
        return """
Dear Customer,

Thank you for choosing our services.

We hereby confirm that you have successfully returned the vehicle at our location.

This message serves as the official confirmation of your vehicle return. Please note that the final vehicle inspection may take up to four days. Should any irregularities be identified during this process, we will contact you accordingly.

If you have any further questions, please do not hesitate to contact us.

Kind regards,

\(closing)
"""
    }
    
    private init() {}
    
    private func isTurkeyPDF(franchiseId: String?) -> Bool {
        let normalizedFranchise = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalizedFranchise.hasPrefix("TR") { return true }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased() == "TR"
    }

    private func isSabihaGokcenPDF(franchiseId: String?) -> Bool {
        let normalizedFranchise = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalizedFranchise.contains("SABIHA") || normalizedFranchise.contains("SAW")
    }

    private func drawUSaveLogo(in context: CGContext, rect: CGRect) {
        guard let logo = UIImage(named: "usave_logo") else { return }
        context.saveGState()
        context.setBlendMode(.screen)
        logo.draw(in: rect)
        context.restoreGState()
    }

    private func drawConditionDamageMap(arac: Arac, in rect: CGRect, context: UIGraphicsPDFRendererContext) {
        let cg = context.cgContext
        if let mapImage = UIImage(named: "condition_vehicle_2d") {
            mapImage.draw(in: rect)
        } else {
            cg.setStrokeColor(UIColor.systemGray3.cgColor)
            cg.stroke(rect)
        }

        let conditionDamages = arac.hasarKayitlari.filter {
            let zone = $0.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !zone.isEmpty
        }
        for (idx, damage) in conditionDamages.enumerated() {
            guard let x = damage.conditionPointX, let y = damage.conditionPointY else { continue }
            let px = rect.minX + (CGFloat(x) / VehicleRef.canvasWidth) * rect.width
            let py = rect.minY + (CGFloat(y) / VehicleRef.canvasHeight) * rect.height
            let bubble = CGRect(x: px - 7, y: py - 7, width: 14, height: 14)
            cg.setFillColor(UIColor.systemRed.cgColor)
            cg.fillEllipse(in: bubble)
            let marker = "\(damage.markerNumber ?? (idx + 1))" as NSString
            marker.draw(
                at: CGPoint(x: px + 9, y: py - 6),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: UIColor.systemRed
                ]
            )
        }
    }

    /// Closing text for non‑Turkey return PDFs (below signature): confirmation + “return complete” notice.
    private func legacyIadeFooterAcknowledgement(resolvedLanguage: PDFContentLanguage) -> String {
        if resolvedLanguage == .turkish {
            return """
            Yukarıdaki bilgi ve fotoğrafların aracı iade ettiğinizi doğru yansıttığını onaylıyorum.

            İade işlemi tamamlanmıştır. Bu belge yalnızca aracı teslim ettiğinize dair bir dokümandır.
            """
        }
        return """
        I confirm that the information and photographs above correctly reflect this vehicle return.

        Return complete. This document serves only as confirmation that you have returned the vehicle.
        """
    }

    private func returnLegalParagraphs(language: PDFContentLanguage) -> [String] {
        if language == .turkish {
            return [
                "1. Kiracı, sözleşmeye konu aracı kullanımına tahsis ettiği üçüncü şahsın; kimlik, ehliyet ve adresine ilişkin bilgileri en geç aracın kendisine teslim anına kadar kiralayana vermek, aksi halde sözleşmeden kaynaklanan haklardan yararlanamayacağını kabul, beyan ve taahhüt eder.",
                "2. Kiracı; aracı tam, eksiksiz ve sağlam olarak teslim almış olup (varsa herhangi bir eksiklik yukarıdaki gibi formda belirtilecektir.) aracın kullanımında gerekli dikkat ve özeni gösterecek, iyi durumda bulunmasını sağlayacaktır. Kullanımı hatasından kaynaklanan, mekanik problemlerde aracın yetkili servisince yapılan tespitte, kullanımdan kaynaklanan bir zarar tespit edilmesi halinde, zararın kendisine rücu edileceğini kabul, beyan ve taahhüt eder.",
                "3. Kiracının araç ile kazaya karışması halinde derhal kiralayanı haberdar etme, kaza tutanaklarını, alkol raporu, ilgili tarafların ehliyet, ruhsatname, trafik sigorta poliçeleri vesair evrakı eksiksiz olarak almak ve kiralayana teslim etmekle yükümlüdür. Aksi halde kiracının tüm haklarından vazgeçeceğini kabul, beyan ve taahhüt eder.",
                "4. Kiracı, yukarıdaki ilk 3 madde ve aracın kullanımından kaynaklanan ücret, kullanım süresi dolmasına rağmen devam eden kullanımdan kaynaklanan ücretler, OGS-HGS, trafik cezaları, İSPARK vesair otopark, gecikmeden kaynaklanan faiz ve kiracıdan kaynaklanan sair tüm ücretlerin yukarıda beyan etmiş olduğu kredi kartı bilgilerinden tahsil edilecek ödenmesini kabul, beyan ve taahhüt eder.",
                "Aracı, iç ve dış temizliği yapılmış ve sorunsuz bir şekilde teslim aldım."
            ]
        }
        return [
            "1. The tenant declares and undertakes that the identity, driver license and address details of any third party assigned to use the rented vehicle are delivered to the lessor no later than the handover moment; otherwise, rights arising from the contract may not be claimed.",
            "2. The tenant accepts that the vehicle has been received complete and in good condition (any deficiency would be listed in this form), will use it with due care, and agrees that any user-caused mechanical or physical damage identified by authorized service may be recourse-charged to the tenant.",
            "3. In case of an accident, the tenant is obliged to immediately notify the lessor and provide complete documentation including accident report, alcohol report, licenses, registration and insurance documents; otherwise, the tenant waives related rights.",
            "4. The tenant accepts and undertakes that all vehicle-use-related charges, overuse charges after contract period, OGS/HGS, traffic fines, parking fees and delay interests may be collected from the declared credit card details.",
            "I confirm that I received the vehicle in clean and proper condition."
        ]
    }
    
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
    
    func generateIadePDF(iade: IadeIslemi, arac: Arac, franchiseDisplayName: String = "", language: PDFContentLanguage = .automatic, signatureImageOverride: UIImage? = nil, completion: @escaping (URL?) -> Void) {
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
                signatureImage: resolvedSignatureImage,
                franchiseDisplayName: franchiseDisplayName,
                language: language
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(iade: IadeIslemi, arac: Arac, images: [UIImage], signatureImage: UIImage?, franchiseDisplayName: String, language: PDFContentLanguage) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            if !isTurkeyPDF(franchiseId: iade.franchiseId) {
                self.renderLegacyIadePDFContent(
                    context: context,
                    iade: iade,
                    arac: arac,
                    images: images,
                    signatureImage: signatureImage,
                    language: language,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight
                )
                return
            }

            var yPosition: CGFloat = 32
            let margin: CGFloat = 24
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.68
            let isTurkeyLayout = true
            let resolvedLanguage = language.resolved(forTurkeyFranchise: isTurkeyLayout)
            
            context.beginPage()
            let cg = context.cgContext
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 30),
                .foregroundColor: SwissPDFHelper.black
            ]
            NSString(string: resolvedLanguage == .turkish ? "Araç İade Formu" : "Return").draw(
                in: CGRect(x: margin, y: yPosition, width: 220, height: 36),
                withAttributes: titleAttributes
            )
            if isSabihaGokcenPDF(franchiseId: iade.franchiseId) {
                let logoRect = CGRect(x: pageWidth - margin - 108, y: yPosition - 2, width: 108, height: 36)
                drawUSaveLogo(in: cg, rect: logoRect)
            }
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
            
            let rightColumnX = pageWidth - margin - 190
            let mapTitle = resolvedLanguage == .turkish ? "İade Hasar Detayı" : "Return Damage Detail"
            mapTitle.draw(at: CGPoint(x: rightColumnX, y: yPosition + 40), withAttributes: labelAttributes)
            let mapRect = CGRect(x: rightColumnX, y: yPosition + 56, width: 190, height: 120)
            drawConditionDamageMap(arac: arac, in: mapRect, context: context)

            let labelWidth: CGFloat = 136
            let valueX: CGFloat = margin + labelWidth + 10
            let valueWidth: CGFloat = rightColumnX - valueX - 12
            func drawRow(_ key: String, _ value: String) {
                key.draw(
                    in: CGRect(x: margin, y: yPosition, width: labelWidth, height: 30),
                    withAttributes: labelAttributes
                )
                let valueRect = CGRect(x: valueX, y: yPosition, width: valueWidth, height: 48)
                (value as NSString).draw(
                    in: valueRect,
                    withAttributes: infoAttributes
                )
                let measured = ceil((value as NSString).boundingRect(
                    with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: infoAttributes,
                    context: nil
                ).height)
                yPosition += max(18, measured + 4)
            }

            drawRow(resolvedLanguage == .turkish ? "Araç Plakası" : "PLATE", iade.aracPlaka)
            drawRow(resolvedLanguage == .turkish ? "Araç Markası / Modeli" : "VEHICLE", "\(arac.marka) \(arac.model)")
            drawRow(resolvedLanguage == .turkish ? "Kira Bitiş Tarihi ve Saati" : "RETURN DATE", dateFormatter.string(from: iade.iadeTarihi))
            if let km = iade.km {
                drawRow("KM", "\(km)")
            }
            if let fuel = normalizedFuelDisplay(iade.yakitSeviyesi) {
                drawRow(resolvedLanguage == .turkish ? "İade Yakıtı" : "FUEL", fuel)
            }
            if let branch = iade.bayiAdi?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                drawRow(resolvedLanguage == .turkish ? "İade Şubesi" : "ENTRY BRANCH", branch)
            }
            drawRow(resolvedLanguage == .turkish ? "Total Fotoğraflar" : "TOTAL PHOTOS", "\(images.count)")
            
            if !iade.notlar.isEmpty {
                drawRow("NOTES", iade.notlar)
            }
            
            yPosition = max(yPosition + 8, mapRect.maxY + 14)
            
            let noteText: String
            if resolvedLanguage == .turkish {
                noteText = returnLegalParagraphs(language: .turkish).joined(separator: "\n\n")
            } else {
                noteText = returnLegalParagraphs(language: .english).joined(separator: "\n\n")
            }

            // Keep signature block on first page, directly under legal text.
            let signatureSectionHeight: CGFloat = 170
            let noteLabelHeight: CGFloat = 14
            let bottomSafetyPadding: CGFloat = 12
            let noteWidth = pageWidth - (2 * margin)
            let maxNoteHeightForFirstPage = max(
                120,
                pageHeight - margin - signatureSectionHeight - bottomSafetyPadding - yPosition - noteLabelHeight
            )

            func makeNoteAttributes(fontSize: CGFloat, lineSpacing: CGFloat, paragraphSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = lineSpacing
                style.paragraphSpacing = paragraphSpacing
                return [
                    .font: SwissPDFHelper.helvetica(size: fontSize),
                    .foregroundColor: SwissPDFHelper.darkGray,
                    .paragraphStyle: style
                ]
            }

            // For Turkish PDFs, use denser typography so signature stays on page 1.
            let primaryNoteAttributes: [NSAttributedString.Key: Any] = {
                if resolvedLanguage == .turkish {
                    return makeNoteAttributes(fontSize: 9, lineSpacing: 2, paragraphSpacing: 4)
                }
                return makeNoteAttributes(fontSize: 10, lineSpacing: 4, paragraphSpacing: 8)
            }()
            var noteAttributes = primaryNoteAttributes
            var noteMeasuredHeight = ceil((noteText as NSString).boundingRect(
                with: CGSize(width: noteWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: noteAttributes,
                context: nil
            ).height)

            if noteMeasuredHeight > maxNoteHeightForFirstPage && resolvedLanguage == .turkish {
                noteAttributes = makeNoteAttributes(fontSize: 8, lineSpacing: 1.5, paragraphSpacing: 3)
                noteMeasuredHeight = ceil((noteText as NSString).boundingRect(
                    with: CGSize(width: noteWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: noteAttributes,
                    context: nil
                ).height)
            }

            "NOTE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
            yPosition += 14
            let drawnNoteHeight = min(noteMeasuredHeight + 4, maxNoteHeightForFirstPage)
            (noteText as NSString).draw(
                in: CGRect(x: margin, y: yPosition, width: noteWidth, height: drawnNoteHeight),
                withAttributes: noteAttributes
            )
            yPosition += drawnNoteHeight + 12

            let trimmedName = iade.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedEmail = (iade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasCustomerSection = signatureImage != nil || !trimmedEmail.isEmpty
            
            if hasCustomerSection {
                // Signature is intentionally kept on page 1 under legal text.
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

            var xPosition: CGFloat = margin
            var columnCount = 0

            // Photos after signature + legal text
            for (_, image) in images.enumerated() {
                if yPosition + imageHeight + 54 > pageHeight - margin {
                    context.beginPage()
                    yPosition = 32
                    xPosition = margin
                    columnCount = 0
                }

                let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high
                image.draw(in: fittedRect)

                let labelDate = dateFormatter.string(from: iade.iadeTarihi)
                let photoLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helveticaBold(size: 11),
                    .foregroundColor: UIColor.systemGreen
                ]
                let labelRect = CGRect(x: xPosition + 10, y: yPosition + 10, width: imageWidth - 20, height: 40)
                labelDate.draw(in: labelRect, withAttributes: photoLabelAttrs)

                columnCount += 1
                if columnCount == 2 {
                    yPosition += imageHeight + 15
                    xPosition = margin
                    columnCount = 0
                } else {
                    xPosition = margin + imageWidth + margin
                }
            }
            if columnCount == 1 {
                yPosition += imageHeight + 15
            }
        }
        
        let fn = DateFormatter()
        fn.locale = Locale(identifier: "en_US_POSIX")
        fn.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "return_report_\(fn.string(from: iade.iadeTarihi)).pdf"
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

    /// Return PDF without condition map or long legal text (non‑Turkey franchises).
    private func renderLegacyIadePDFContent(
        context: UIGraphicsPDFRendererContext,
        iade: IadeIslemi,
        arac: Arac,
        images: [UIImage],
        signatureImage: UIImage?,
        language: PDFContentLanguage,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) {
        var yPosition: CGFloat = 32
        let margin: CGFloat = 24
        let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
        let imageHeight: CGFloat = imageWidth * 0.68
        let resolvedLanguage = language.resolved(forTurkeyFranchise: false)

        context.beginPage()
        let cg = context.cgContext

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: SwissPDFHelper.helveticaBold(size: 30),
            .foregroundColor: SwissPDFHelper.black
        ]
        NSString(string: resolvedLanguage == .turkish ? "Araç İade Formu" : "Return").draw(
            in: CGRect(x: margin, y: yPosition, width: pageWidth - margin * 2, height: 36),
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

        let labelWidth: CGFloat = 136
        let valueX: CGFloat = margin + labelWidth + 10
        let valueWidth: CGFloat = pageWidth - margin - valueX - 8

        func drawRow(_ key: String, _ value: String) {
            key.draw(
                in: CGRect(x: margin, y: yPosition, width: labelWidth, height: 30),
                withAttributes: labelAttributes
            )
            let valueRect = CGRect(x: valueX, y: yPosition, width: valueWidth, height: 48)
            (value as NSString).draw(
                in: valueRect,
                withAttributes: infoAttributes
            )
            let measured = ceil((value as NSString).boundingRect(
                with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: infoAttributes,
                context: nil
            ).height)
            yPosition += max(18, measured + 4)
        }

        drawRow(resolvedLanguage == .turkish ? "Araç Plakası" : "PLATE", iade.aracPlaka)
        drawRow(resolvedLanguage == .turkish ? "Araç Markası / Modeli" : "VEHICLE", "\(arac.marka) \(arac.model)")
        drawRow(resolvedLanguage == .turkish ? "Kira Bitiş Tarihi ve Saati" : "RETURN DATE", dateFormatter.string(from: iade.iadeTarihi))
        if let km = iade.km {
            drawRow("KM", "\(km)")
        }
        if let fuel = normalizedFuelDisplay(iade.yakitSeviyesi) {
            drawRow(resolvedLanguage == .turkish ? "İade Yakıtı" : "FUEL", fuel)
        }
        if let branch = iade.bayiAdi?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            drawRow(resolvedLanguage == .turkish ? "İade Şubesi" : "ENTRY BRANCH", branch)
        }
        drawRow(resolvedLanguage == .turkish ? "Total Fotoğraflar" : "TOTAL PHOTOS", "\(images.count)")

        if !iade.notlar.isEmpty {
            drawRow("NOTES", iade.notlar)
        }

        yPosition += 12

        let trimmedName = iade.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = (iade.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomerSection = signatureImage != nil || !trimmedEmail.isEmpty

        var xPosition: CGFloat = margin
        var columnCount = 0

        for (index, image) in images.enumerated() {
            if yPosition + imageHeight + 54 > pageHeight - margin {
                context.beginPage()
                yPosition = 32
                xPosition = margin
                columnCount = 0
            }

            let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
            let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)
            UIGraphicsGetCurrentContext()?.interpolationQuality = .high
            image.draw(in: fittedRect)

            let labelDate = dateFormatter.string(from: iade.iadeTarihi)
            let photoLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 11),
                .foregroundColor: UIColor.systemGreen
            ]
            let labelRect = CGRect(x: xPosition + 10, y: yPosition + 10, width: imageWidth - 20, height: 40)
            let fullLabel = "Photo \(index + 1)\n\(labelDate)"
            fullLabel.draw(in: labelRect, withAttributes: photoLabelAttrs)

            columnCount += 1
            if columnCount == 2 {
                yPosition += imageHeight + 15
                xPosition = margin
                columnCount = 0
            } else {
                xPosition = margin + imageWidth + margin
            }
        }
        if columnCount == 1 {
            yPosition += imageHeight + 15
        }

        yPosition += 24

        let footerText = legacyIadeFooterAcknowledgement(resolvedLanguage: resolvedLanguage)
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: SwissPDFHelper.helvetica(size: 10),
            .foregroundColor: SwissPDFHelper.darkGray,
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 4
                p.paragraphSpacing = 8
                return p
            }()
        ]
        let footerWidth = pageWidth - 2 * margin
        let signatureBlockHeight: CGFloat = hasCustomerSection ? 210 : 0

        func measureFooterHeight() -> CGFloat {
            ceil((footerText as NSString).boundingRect(
                with: CGSize(width: footerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: footerAttrs,
                context: nil
            ).height)
        }

        var footerHeight = measureFooterHeight()
        let bottomSafety: CGFloat = 28
        var neededBelowPhotos = signatureBlockHeight + 12 + footerHeight + bottomSafety
        if yPosition + neededBelowPhotos > pageHeight - margin {
            context.beginPage()
            yPosition = margin
        }

        if hasCustomerSection {
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
            yPosition += 22
        }

        yPosition += 8
        footerHeight = measureFooterHeight()
        neededBelowPhotos = footerHeight + bottomSafety
        if yPosition + neededBelowPhotos > pageHeight - margin {
            context.beginPage()
            yPosition = margin
        }

        (footerText as NSString).draw(
            in: CGRect(x: margin, y: yPosition, width: footerWidth, height: footerHeight + 8),
            withAttributes: footerAttrs
        )
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
