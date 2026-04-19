import UIKit
import PDFKit

class ExitPDFGenerator {
    static let shared = ExitPDFGenerator()
    
    /// Customer-facing confirmation (PDF + email) for vehicle handover/check-out.
    static func checkoutConfirmationText(franchiseId: String, franchiseDisplayName: String = "") -> String {
        let trimmedName = franchiseDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeGM = trimmedName.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let normalizedFranchise = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isTurkey = normalizedFranchise.hasPrefix("TR")

        if isTurkey {
            let closing = (trimmedName.isEmpty || looksLikeGM) ? "Kiralama ekibiniz" : "\(trimmedName) ekibi"
            return """
Sayın Müşterimiz,

Hizmetimizi tercih ettiğiniz için teşekkür ederiz.

Aracın tarafınıza başarıyla teslim edildiğini ve check-out işleminin tamamlandığını bilgilerinize sunarız.

Bu e-posta, araç teslim işleminize ait resmi bilgilendirme niteliğindedir. İlgili teslim evrakı PDF olarak ektedir.

Herhangi bir sorunuz olması halinde bizimle iletişime geçebilirsiniz.

Saygılarımızla,

\(closing)
"""
        }

        let closing = (trimmedName.isEmpty || looksLikeGM) ? "Your rental team" : "Your \(trimmedName) team"
        return """
Dear Customer,

Thank you for choosing our services.

We hereby confirm that the vehicle has been successfully handed over to you and your check-out process is complete.

This email serves as the official confirmation of your check-out operation. The related handover document is attached as PDF.

If you have any questions, please do not hesitate to contact us.

Kind regards,

\(closing)
"""
    }

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
        if let mapImage = UIImage(named: "condition_vehicle_2d") {
            mapImage.draw(in: rect)
        } else {
            context.cgContext.setStrokeColor(UIColor.systemGray3.cgColor)
            context.cgContext.stroke(rect)
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
            context.cgContext.setFillColor(UIColor.systemRed.cgColor)
            context.cgContext.fillEllipse(in: bubble)
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

    private func checkoutLegalParagraphs(language: PDFContentLanguage) -> [String] {
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
    
    func generateExitPDF(exit: ExitIslemi, arac: Arac, language: PDFContentLanguage = .automatic, completion: @escaping (URL?) -> Void) {
        guard !exit.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        
        let storageImageLoader = StorageImageLoader.shared
        var resolvedSignatureImage: UIImage?
        
        // SIRALI İNDİRME - İndeksleri koruyarak
        for (index, urlString) in exit.fotograflar.enumerated() {
            dispatchGroup.enter()
            
            storageImageLoader.loadImage(from: urlString) { image in
                if let image {
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
                signatureImage: resolvedSignatureImage,
                language: language
            )
            
            completion(pdfURL)
        }
    }
    
    private func createPDF(exit: ExitIslemi, arac: Arac, images: [UIImage], signatureImage: UIImage?, language: PDFContentLanguage) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            if !isTurkeyPDF(franchiseId: exit.franchiseId) {
                self.renderLegacyExitPDFContent(
                    context: context,
                    exit: exit,
                    arac: arac,
                    images: images,
                    signatureImage: signatureImage,
                    language: language,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight
                )
                return
            }

            var yPosition: CGFloat = 50
            let margin: CGFloat = 25
            let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
            let imageHeight: CGFloat = imageWidth * 0.70
            let isTurkeyLayout = true
            let resolvedLanguage = language.resolved(forTurkeyFranchise: isTurkeyLayout)
            
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = resolvedLanguage == .turkish ? "Araç Teslim Formu" : "Check Out Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            if isSabihaGokcenPDF(franchiseId: exit.franchiseId) {
                let logoRect = CGRect(x: pageWidth - margin - 108, y: yPosition - 2, width: 108, height: 36)
                drawUSaveLogo(in: context.cgContext, rect: logoRect)
            }
            yPosition += 40
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            
            let rightColumnX = pageWidth - margin - 190
            let mapTitle = resolvedLanguage == .turkish ? "Teslim Hasar Detayı" : "Handover Damage Detail"
            let mapLabelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            mapTitle.draw(at: CGPoint(x: rightColumnX, y: yPosition + 40), withAttributes: mapLabelAttributes)
            let mapRect = CGRect(x: rightColumnX, y: yPosition + 56, width: 190, height: 120)
            drawConditionDamageMap(arac: arac, in: mapRect, context: context)
            
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            let labelWidth: CGFloat = 136
            let valueX: CGFloat = margin + labelWidth + 10
            let valueWidth: CGFloat = rightColumnX - valueX - 12
            func drawRow(_ key: String, _ value: String) {
                key.draw(in: CGRect(x: margin, y: yPosition, width: labelWidth, height: 32), withAttributes: labelAttributes)
                (value as NSString).draw(
                    in: CGRect(x: valueX, y: yPosition, width: valueWidth, height: 48),
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

            drawRow(resolvedLanguage == .turkish ? "Araç Plakası" : "Plate", exit.aracPlaka)
            drawRow(resolvedLanguage == .turkish ? "Araç Markası / Modeli" : "Vehicle", "\(arac.marka) \(arac.model)")
            drawRow(resolvedLanguage == .turkish ? "Kira Başlangıç Tarihi ve Saati" : "Check Out Date", dateFormatter.string(from: exit.exitTarihi))
            if let km = exit.km { drawRow("KM", "\(km)") }
            if let fuel = normalizedFuelDisplay(exit.yakitSeviyesi) {
                drawRow(resolvedLanguage == .turkish ? "Teslim Yakıtı" : "Fuel", fuel)
            }
            if let pu = (exit.pickUpBranch ?? exit.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
                drawRow(resolvedLanguage == .turkish ? "Alış şubesi" : "Pick-up branch", pu)
            }
            if let pd = exit.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
                drawRow(resolvedLanguage == .turkish ? "Bırakış şubesi" : "Drop-off branch", pd)
            }
            drawRow(resolvedLanguage == .turkish ? "Total Fotoğraflar" : "TOTAL PHOTOS", "\(images.count)")
            if !exit.notlar.isEmpty {
                drawRow(resolvedLanguage == .turkish ? "Notlar" : "Notes", exit.notlar)
            }
            yPosition = max(yPosition + 8, mapRect.maxY + 14)
            
            let noteText = checkoutLegalParagraphs(language: resolvedLanguage).joined(separator: "\n\n")
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: {
                    let p = NSMutableParagraphStyle()
                    p.lineSpacing = 4
                    p.paragraphSpacing = 8
                    return p
                }()
            ]
            let noteHeight = ceil((noteText as NSString).boundingRect(
                with: CGSize(width: pageWidth - (2 * margin), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: noteAttrs,
                context: nil
            ).height) + 4
            if yPosition + noteHeight > pageHeight - margin - 30 {
                addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                context.beginPage()
                yPosition = 50
            }
            (noteText as NSString).draw(
                in: CGRect(x: margin, y: yPosition, width: pageWidth - (2 * margin), height: noteHeight),
                withAttributes: noteAttrs
            )
            yPosition += noteHeight + 12

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
                "CUSTOMER INFORMATION & SIGNATURE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
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

                let customerName = exit.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
                let customerEmail = (exit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                "CUSTOMER".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                (customerName.isEmpty ? "Not provided" : customerName).draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
                yPosition += 16

                "EMAIL".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                (customerEmail.isEmpty ? "Not provided" : customerEmail).draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
                yPosition += 16

                "PLATE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: labelAttributes)
                exit.aracPlaka.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: infoAttributes)
                yPosition += 16
            }
            
            // Photos after signature + legal section
            var xPosition = margin
            var columnCount = 0
            for (_, image) in images.enumerated() {
                if yPosition + imageHeight + 50 > pageHeight - margin - 30 {
                    addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                    context.beginPage()
                    yPosition = 50
                    xPosition = margin
                    columnCount = 0
                }

                let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
                let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)
                UIGraphicsGetCurrentContext()?.interpolationQuality = .high
                image.draw(in: fittedRect)

                let stamp = dateFormatter.string(from: exit.exitTarihi)
                let stampAttrs: [NSAttributedString.Key: Any] = [
                    .font: SwissPDFHelper.helveticaBold(size: 11),
                    .foregroundColor: UIColor.systemGreen
                ]
                stamp.draw(in: CGRect(x: xPosition + 8, y: yPosition + 8, width: imageWidth - 16, height: 24), withAttributes: stampAttrs)

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

    /// Check‑out PDF without condition map or long legal text (non‑Turkey franchises).
    private func renderLegacyExitPDFContent(
        context: UIGraphicsPDFRendererContext,
        exit: ExitIslemi,
        arac: Arac,
        images: [UIImage],
        signatureImage: UIImage?,
        language: PDFContentLanguage,
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) {
        var yPosition: CGFloat = 50
        let margin: CGFloat = 25
        let imageWidth: CGFloat = (pageWidth - (3 * margin)) / 2
        let imageHeight: CGFloat = imageWidth * 0.70
        let resolvedLanguage = language.resolved(forTurkeyFranchise: false)

        context.beginPage()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.black
        ]
        let title = resolvedLanguage == .turkish ? "Araç Teslim Formu" : "Check Out Report"
        title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
        yPosition += 40

        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let labelWidth: CGFloat = 136
        let valueX: CGFloat = margin + labelWidth + 10
        let valueWidth: CGFloat = pageWidth - margin - valueX - 8

        func drawRow(_ key: String, _ value: String) {
            key.draw(in: CGRect(x: margin, y: yPosition, width: labelWidth, height: 32), withAttributes: labelAttributes)
            (value as NSString).draw(
                in: CGRect(x: valueX, y: yPosition, width: valueWidth, height: 48),
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

        drawRow(resolvedLanguage == .turkish ? "Araç Plakası" : "Plate", exit.aracPlaka)
        drawRow(resolvedLanguage == .turkish ? "Araç Markası / Modeli" : "Vehicle", "\(arac.marka) \(arac.model)")
        drawRow(resolvedLanguage == .turkish ? "Kira Başlangıç Tarihi ve Saati" : "Check Out Date", dateFormatter.string(from: exit.exitTarihi))
        if let km = exit.km { drawRow("KM", "\(km)") }
        if let fuel = normalizedFuelDisplay(exit.yakitSeviyesi) {
            drawRow(resolvedLanguage == .turkish ? "Teslim Yakıtı" : "Fuel", fuel)
        }
        if let pu = (exit.pickUpBranch ?? exit.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty {
            drawRow(resolvedLanguage == .turkish ? "Alış şubesi" : "Pick-up branch", pu)
        }
        if let pd = exit.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pd.isEmpty {
            drawRow(resolvedLanguage == .turkish ? "Bırakış şubesi" : "Drop-off branch", pd)
        }
        drawRow(resolvedLanguage == .turkish ? "Total Fotoğraflar" : "TOTAL PHOTOS", "\(images.count)")
        if !exit.notlar.isEmpty {
            drawRow(resolvedLanguage == .turkish ? "Notlar" : "Notes", exit.notlar)
        }

        yPosition += 8

        if let signatureImage {
            let cg = context.cgContext
            let sigLabelAttributes: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 10),
                .foregroundColor: SwissPDFHelper.black
            ]
            let sigInfoAttributes: [NSAttributedString.Key: Any] = [
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
            "CUSTOMER INFORMATION & SIGNATURE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sigLabelAttributes)
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

            let customerName = exit.customerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let customerEmail = (exit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            "CUSTOMER".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sigLabelAttributes)
            (customerName.isEmpty ? "Not provided" : customerName).draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: sigInfoAttributes)
            yPosition += 16

            "EMAIL".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sigLabelAttributes)
            (customerEmail.isEmpty ? "Not provided" : customerEmail).draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: sigInfoAttributes)
            yPosition += 16

            "PLATE".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sigLabelAttributes)
            exit.aracPlaka.draw(at: CGPoint(x: margin + 86, y: yPosition), withAttributes: sigInfoAttributes)
            yPosition += 16
        }

        var xPosition = margin
        var columnCount = 0
        for (index, image) in images.enumerated() {
            if yPosition + imageHeight + 50 > pageHeight - margin - 30 {
                addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
                context.beginPage()
                yPosition = 50
                xPosition = margin
                columnCount = 0
            }

            let slotRect = CGRect(x: xPosition, y: yPosition, width: imageWidth, height: imageHeight)
            let fittedRect = aspectFitRect(imageSize: image.size, in: slotRect)
            UIGraphicsGetCurrentContext()?.interpolationQuality = .high
            image.draw(in: fittedRect)

            let stamp = dateFormatter.string(from: exit.exitTarihi)
            let stampAttrs: [NSAttributedString.Key: Any] = [
                .font: SwissPDFHelper.helveticaBold(size: 11),
                .foregroundColor: UIColor.systemGreen
            ]
            let labelRect = CGRect(x: xPosition + 8, y: yPosition + 8, width: imageWidth - 16, height: 40)
            let fullLabel = "Photo \(index + 1)\n\(stamp)"
            fullLabel.draw(in: labelRect, withAttributes: stampAttrs)

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

        addCopyright(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
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

