import UIKit

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

        if normalizedFranchise.hasPrefix("DE") {
            return """
Dear Customer,

Thank you for choosing our services.

We hereby confirm that the vehicle has been successfully handed over to you and your check-out process is complete.

This email serves as the official confirmation of your check-out operation. The related handover document is attached as PDF.

If you have any questions, please do not hesitate to contact us.

Kind regards,

Germany Düsseldorf
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
        (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .hasPrefix("TR")
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
    
    private func turkeyDamageDetailLines(from arac: Arac) -> [String] {
        arac.hasarKayitlari
            .sorted { ($0.markerNumber ?? 9999) < ($1.markerNumber ?? 9999) }
            .map { h in
                let zone = (h.damageZone ?? "—").replacingOccurrences(of: "_", with: " ")
                let num = h.markerNumber.map { "#\($0)" } ?? ""
                let type = (h.damageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let sev = (h.damageSeverity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let note = h.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
                var parts: [String] = []
                if !type.isEmpty { parts.append(type) }
                if !sev.isEmpty { parts.append(sev) }
                if !note.isEmpty, note.count < 90 { parts.append(note) }
                let tail = parts.joined(separator: " · ")
                return "\(num)  \(zone)  \(tail)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    /// Maps checkout (`ExitIslemi`) + vehicle into the shared TR programmatic form payload (same structure as return PDF).
    private func turkeyVehicleFormData(
        exit: ExitIslemi,
        arac: Arac,
        images: [UIImage],
        damageImages: [UIImage],
        signatureImage: UIImage?,
        franchiseDisplayName: String,
        staffSignerNameFallback: String?
    ) -> VehicleReturnPdfData {
        let plate = exit.aracPlaka.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        let branch = (exit.pickUpBranch ?? exit.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines)
        func notEmpty(_ s: String) -> String? { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s.trimmingCharacters(in: .whitespacesAndNewlines) }

        var navDigits = (exit.navKodu ?? exit.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        while navDigits.uppercased().hasPrefix("NAV-") || navDigits.uppercased().hasPrefix("RES-") || navDigits.uppercased().hasPrefix("RNT-") {
            navDigits = String(navDigits.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let navContract = navDigits.isEmpty ? nil : "NAV-\(navDigits)"

        let res = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        let damagePoints: [DamagePoint] = arac.hasarKayitlari
            .filter {
                let zone = $0.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !zone.isEmpty
            }
            .compactMap { damage in
                guard let p = VehicleViewBlock.normalizedRefPointOnCanvas(
                    conditionViewBlockId: damage.conditionViewBlockId,
                    conditionPointX: damage.conditionPointX,
                    conditionPointY: damage.conditionPointY
                ) else { return nil }
                return DamagePoint(x: p.x, y: p.y, label: damage.markerNumber.map(String.init))
            }
        let mapper = exit.vehicleItemsChecklist ?? [:]
        let notesTrimmed = exit.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
        let pickupOrBranch = notEmpty(exit.pickUpBranch ?? exit.bayiAdi ?? "")
        let drop = notEmpty(exit.dropOffBranch ?? "")
        let pickB = (exit.pickUpBranch ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dropB = (exit.dropOffBranch ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let branchRoute: String? = {
            if pickB.isEmpty && dropB.isEmpty { return nil }
            return "Teslim şubesi: \(pickB.isEmpty ? "—" : pickB)  →  Hedef: \(dropB.isEmpty ? "—" : dropB)"
        }()
        let staffSig = TurkeyStaffPdfSignatureStore.loadSignatureImage()
        let staffNm = TurkeyStaffPdfSignatureStore.loadDisplayName(fallbackProfileFullName: staffSignerNameFallback)

        return VehicleReturnPdfData(
            contractNo: navContract ?? (plate.isEmpty ? nil : plate),
            contractDate: dateFormatter.string(from: exit.exitTarihi),
            contractPeriod: res.isEmpty ? nil : res,
            branch: branch,
            franchiseLegalTitle: notEmpty(franchiseDisplayName),
            branchRoutingLine: notEmpty(branchRoute ?? ""),
            customerFullName: notEmpty(exit.customerFullName),
            customerId: notEmpty(exit.customerNationalId ?? ""),
            customerPhone: nil,
            customerBirth: notEmpty(exit.customerEmail ?? ""),
            driverLicenseNo: nil,
            driverFullName: notEmpty(exit.customerFullName),
            testDriverFullName: notEmpty(exit.testDriverFullName),
            driverLicenseDate: nil,
            driverAddress: nil,
            returnDate: dateFormatter.string(from: exit.exitTarihi),
            returnTime: timeFormatter.string(from: exit.exitTarihi),
            returnLocation: pickupOrBranch ?? drop ?? branch,
            odometer: exit.km.map { String($0) },
            vehicleModel: notEmpty("\(arac.marka) \(arac.model)"),
            vehiclePlate: plate.isEmpty ? nil : plate,
            vehicleColor: nil,
            vehicleFuelType: normalizedFuelDisplay(exit.yakitSeviyesi),
            vehicleClass: nil,
            vehicleVIN: nil,
            fuelRatio: normalizedFuelRatio(exit.yakitSeviyesi),
            items: VehicleItems(
                antenna: mapper["anten"],
                jackSet: mapper["avadanlik"],
                spareTire: mapper["yedek_lastik"],
                plateHolder: mapper["plakalik"],
                safetyKit: mapper["trafik_seti"],
                hgsTag: mapper["hgs_etiketi"],
                fireExt: mapper["yangin_tupu"],
                registration: mapper["ruhsat"],
                insurance: mapper["trafik_policesi"],
                floorMats: mapper["paspas"],
                washerFluid: mapper["cam_suyu"],
                underguard: mapper["pandizot"],
                wipers: mapper["silecek"],
                pump: mapper["lastik_kompresoru"],
                navigation: mapper["navigasyon"],
                childSeat: mapper["cocuk_koltugu"],
                chains: mapper["zincir"],
                tireBrand: mapper["lastik_markasi"]
            ),
            damagePoints: damagePoints,
            renterName: notEmpty(exit.customerFullName),
            deliveredByName: staffNm,
            renterSignature: signatureImage,
            deliveredSignature: staffSig,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            headerPlateAccent: plate.isEmpty ? nil : plate,
            headerVehicleModelGray: "\(arac.marka) \(arac.model)".trimmingCharacters(in: .whitespacesAndNewlines),
            useNavContractFieldLabel: true,
            damageDetailLines: turkeyDamageDetailLines(from: arac),
            vehiclePhotos: images,
            damagePhotos: damageImages,
            timestamp: dateTimeFormatter.string(from: exit.exitTarihi)
        )
    }

    func generateExitPDF(
        exit: ExitIslemi,
        arac: Arac,
        franchiseDisplayName: String = "",
        staffSignerNameFallback: String? = nil,
        language: PDFContentLanguage = .automatic,
        completion: @escaping (URL?) -> Void
    ) {
        guard !exit.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        var downloadedDamageImagesWithIndex: [(image: UIImage, index: Int)] = []

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

        let damagePhotoURLs = arac.hasarKayitlari.flatMap(\.fotograflar)
        for (index, urlString) in damagePhotoURLs.enumerated() {
            dispatchGroup.enter()
            storageImageLoader.loadImage(from: urlString) { image in
                defer { dispatchGroup.leave() }
                guard let image else { return }
                downloadedDamageImagesWithIndex.append((image: image, index: index))
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
            let sortedDamageImages = downloadedDamageImagesWithIndex
                .sorted { $0.index < $1.index }
                .map { $0.image }

            DispatchQueue.global(qos: .userInitiated).async {
                let pdfURL = self.createPDF(
                    exit: exit,
                    arac: arac,
                    images: sortedImages,
                    damageImages: sortedDamageImages,
                    signatureImage: resolvedSignatureImage,
                    language: language,
                    franchiseDisplayName: franchiseDisplayName,
                    staffSignerNameFallback: staffSignerNameFallback
                )
                DispatchQueue.main.async {
                    completion(pdfURL)
                }
            }
        }
    }

    /// TR checkout PDF bytes using in-memory photos (signature overlay preview).
    func makeTurkeyCheckoutPdfDataForSignatureOverlay(
        exit: ExitIslemi,
        arac: Arac,
        vehiclePhotos: [UIImage],
        damagePhotos: [UIImage],
        franchiseDisplayName: String,
        staffSignerNameFallback: String?
    ) -> Data? {
        guard isTurkeyPDF(franchiseId: exit.franchiseId), !vehiclePhotos.isEmpty else { return nil }
        let payload = turkeyVehicleFormData(
            exit: exit,
            arac: arac,
            images: vehiclePhotos,
            damageImages: damagePhotos,
            signatureImage: nil,
            franchiseDisplayName: franchiseDisplayName,
            staffSignerNameFallback: staffSignerNameFallback
        )
        return TurkeyVehicleFormPdfBuilder().generatePdf(data: payload, kind: .vehicleCheckout)
    }

    /// TR checkout PDF with customer signature baked into the form (wizard final step).
    func makeTurkeyCheckoutPdfDataWithCustomerSignature(
        exit: ExitIslemi,
        arac: Arac,
        vehiclePhotos: [UIImage],
        damagePhotos: [UIImage],
        franchiseDisplayName: String,
        staffSignerNameFallback: String?,
        customerSignature: UIImage?
    ) -> Data? {
        guard isTurkeyPDF(franchiseId: exit.franchiseId), !vehiclePhotos.isEmpty else { return nil }
        let payload = turkeyVehicleFormData(
            exit: exit,
            arac: arac,
            images: vehiclePhotos,
            damageImages: damagePhotos,
            signatureImage: customerSignature,
            franchiseDisplayName: franchiseDisplayName,
            staffSignerNameFallback: staffSignerNameFallback
        )
        return TurkeyVehicleFormPdfBuilder().generatePdf(data: payload, kind: .vehicleCheckout)
    }
    
    private func createPDF(
        exit: ExitIslemi,
        arac: Arac,
        images: [UIImage],
        damageImages: [UIImage],
        signatureImage: UIImage?,
        language: PDFContentLanguage,
        franchiseDisplayName: String,
        staffSignerNameFallback: String?
    ) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let pdfData: Data
        if isTurkeyPDF(franchiseId: exit.franchiseId) {
            let payload = turkeyVehicleFormData(
                exit: exit,
                arac: arac,
                images: images,
                damageImages: damageImages,
                signatureImage: signatureImage,
                franchiseDisplayName: franchiseDisplayName,
                staffSignerNameFallback: staffSignerNameFallback
            )
            pdfData = TurkeyVehicleFormPdfBuilder().generatePdf(data: payload, kind: .vehicleCheckout)
        } else if FranchiseCapabilityMatrix.swissStyleReportPdfEnabled(franchiseId: exit.franchiseId) {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let branchExplicit = FranchiseCapabilityMatrix.isGermany(franchiseId: exit.franchiseId)
                ? nil
                : (exit.pickUpBranch ?? exit.bayiAdi)
            let branch = SwissReportPDFTemplate.branchName(
                franchiseId: exit.franchiseId,
                explicit: branchExplicit
            )
            let fuel = normalizedFuelDisplay(exit.yakitSeviyesi)
                ?? (exit.km.map { "\($0) km" } ?? "—")
            let photosFirstPage = FranchiseCapabilityMatrix.isGermany(franchiseId: exit.franchiseId) ? 4 : nil
            pdfData = SwissReportPDFTemplate.renderHandover(
                kind: .checkout,
                branch: branch,
                plate: exit.aracPlaka,
                vehicle: "\(arac.marka) \(arac.model)".trimmingCharacters(in: .whitespaces),
                dateText: df.string(from: exit.exitTarihi),
                fuelText: fuel,
                photoCount: images.count,
                customerName: exit.customerFullName,
                customerEmail: exit.customerEmail ?? "",
                signature: signatureImage,
                photos: images,
                photoStampDate: df.string(from: exit.exitTarihi),
                signatureCaption: "Customer Signature · Check Out",
                photosOnFirstPage: photosFirstPage
            )
        } else {
            pdfData = renderer.pdfData { context in
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
            }
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

    private func normalizedFuelEighths(_ raw: String?) -> Int? {
        guard let display = normalizedFuelDisplay(raw) else { return nil }
        let numerator = display.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? display
        guard let parsed = Int(numerator) else { return nil }
        return min(8, max(0, parsed))
    }

    private func normalizedFuelRatio(_ raw: String?) -> CGFloat? {
        guard let eighths = normalizedFuelEighths(raw) else { return nil }
        return CGFloat(eighths) / 8.0
    }
}

