import UIKit

class IadePDFGenerator {
    static let shared = IadePDFGenerator()

    /// Customer-facing confirmation (PDF + email). Turkey franchises get Turkish copy; others English.
    static func returnConfirmationText(franchiseId: String, franchiseDisplayName: String = "") -> String {
        let trimmed = franchiseDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeGM = trimmed.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let normalizedFranchise = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isTurkey = normalizedFranchise.hasPrefix("TR")

        if isTurkey {
            let closing = (trimmed.isEmpty || looksLikeGM) ? "Kiralama ekibiniz" : "\(trimmed) ekibi"
            return """
Sayın Müşterimiz,

Hizmetimizi tercih ettiğiniz için teşekkür ederiz.

Aracı lokasyonumuzda başarıyla iade ettiğinizi ve iade işleminizin tamamlandığını bilgilerinize sunarız.

Bu e-posta, araç iadenize ait resmi bilgilendirme niteliğindedir. Nihai araç kontrolü en fazla dört gün sürebilir; bu süreçte tespit edilecek bir durum olması halinde sizinle iletişime geçilecektir.

Herhangi bir sorunuz olması halinde bizimle iletişime geçebilirsiniz.

Saygılarımızla,

\(closing)
"""
        }

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
        (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .hasPrefix("TR")
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

    // Downscales images before embedding into PDF to keep
    // attachment size reliable for SMTP limits and first-try delivery.
    private func optimizedImageForPDF(_ image: UIImage) -> UIImage {
        let normalized = TurkeyCaptureImageOrientation.preparedForPdf(image)
        let maxDimension: CGFloat = 1800
        let logical = TurkeyCaptureImageOrientation.logicalPixelSize(of: normalized)
        let width = logical.width
        let height = logical.height
        guard width > 0, height > 0 else { return normalized }
        
        let largestSide = max(width, height)
        let scaleRatio = min(1.0, maxDimension / largestSide)
        let targetSize = CGSize(width: floor(width * scaleRatio), height: floor(height * scaleRatio))
        guard targetSize.width > 1, targetSize.height > 1 else { return normalized }
        
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
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
    
    func generateIadePDF(
        iade: IadeIslemi,
        arac: Arac,
        franchiseDisplayName: String = "",
        language: PDFContentLanguage = .automatic,
        signatureImageOverride: UIImage? = nil,
        turkeyNavContractDisplay: String? = nil,
        staffSignerNameFallback: String? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        guard !iade.fotograflar.isEmpty else {
            completion(nil)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var downloadedImagesWithIndex: [(image: UIImage, index: Int)] = []
        var downloadedDamageImagesWithIndex: [(image: UIImage, index: Int)] = []
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

        let damagePhotoURLs = arac.hasarKayitlari
            .filter { !$0.fotograflar.isEmpty }
            .sorted { ($0.markerNumber ?? 9999) < ($1.markerNumber ?? 9999) }
            .flatMap { $0.fotograflar }
        for (index, urlString) in damagePhotoURLs.enumerated() {
            dispatchGroup.enter()
            imageLoader.loadImage(from: urlString) { image in
                defer { dispatchGroup.leave() }
                guard let image else { return }
                downloadedDamageImagesWithIndex.append((image: image, index: index))
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
            let sortedDamageImages = downloadedDamageImagesWithIndex
                .sorted { $0.index < $1.index }
                .map { self.optimizedImageForPDF($0.image) }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let pdfURL = self.createPDF(
                    iade: iade,
                    arac: arac,
                    images: sortedImages,
                    damageImages: sortedDamageImages,
                    signatureImage: resolvedSignatureImage,
                    franchiseDisplayName: franchiseDisplayName,
                    language: language,
                    turkeyNavContractDisplay: turkeyNavContractDisplay,
                    staffSignerNameFallback: staffSignerNameFallback
                )
                DispatchQueue.main.async {
                    completion(pdfURL)
                }
            }
        }
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

    /// TR return PDF bytes using in-memory photos (e.g. signature overlay preview before URLs exist).
    func makeTurkeyReturnPdfDataForSignatureOverlay(
        iade: IadeIslemi,
        arac: Arac,
        vehiclePhotos: [UIImage],
        damagePhotos: [UIImage],
        franchiseDisplayName: String,
        turkeyNavContractDisplay: String?,
        staffSignerNameFallback: String?
    ) -> Data? {
        guard isTurkeyPDF(franchiseId: iade.franchiseId), !vehiclePhotos.isEmpty else { return nil }
        return buildTurkeyReturnPdfDocumentData(
            iade: iade,
            arac: arac,
            images: vehiclePhotos,
            damageImages: damagePhotos,
            signatureImage: nil,
            franchiseDisplayName: franchiseDisplayName,
            turkeyNavContractDisplay: turkeyNavContractDisplay,
            staffSignerNameFallback: staffSignerNameFallback
        )
    }

    /// TR return PDF with customer signature baked into the form (wizard final step).
    func makeTurkeyReturnPdfDataWithCustomerSignature(
        iade: IadeIslemi,
        arac: Arac,
        vehiclePhotos: [UIImage],
        damagePhotos: [UIImage],
        franchiseDisplayName: String,
        turkeyNavContractDisplay: String?,
        staffSignerNameFallback: String?,
        customerSignature: UIImage?
    ) -> Data? {
        guard isTurkeyPDF(franchiseId: iade.franchiseId), !vehiclePhotos.isEmpty else { return nil }
        return buildTurkeyReturnPdfDocumentData(
            iade: iade,
            arac: arac,
            images: vehiclePhotos,
            damageImages: damagePhotos,
            signatureImage: customerSignature,
            franchiseDisplayName: franchiseDisplayName,
            turkeyNavContractDisplay: turkeyNavContractDisplay,
            staffSignerNameFallback: staffSignerNameFallback
        )
    }

    private func buildTurkeyReturnPdfDocumentData(
        iade: IadeIslemi,
        arac: Arac,
        images: [UIImage],
        damageImages: [UIImage],
        signatureImage: UIImage?,
        franchiseDisplayName: String,
        turkeyNavContractDisplay: String?,
        staffSignerNameFallback: String?
    ) -> Data {
        let plate = iade.aracPlaka.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        let branch = (iade.dropOffBranch ?? iade.pickUpBranch ?? iade.bayiAdi)?.trimmingCharacters(in: .whitespacesAndNewlines)
        func notEmpty(_ s: String) -> String? { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s.trimmingCharacters(in: .whitespacesAndNewlines) }

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
        let mapper = iade.vehicleItemsChecklist ?? [:]
        let notesTrimmed = iade.notlar.trimmingCharacters(in: .whitespacesAndNewlines)
        let navFromRecord = notEmpty(iade.navKodu ?? "")
        let navFromArg = notEmpty(turkeyNavContractDisplay ?? "")
        let navContract = navFromRecord ?? navFromArg
        let contractNoValue = navContract ?? (plate.isEmpty ? nil : plate)
        let pickB = (iade.pickUpBranch ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dropB = (iade.dropOffBranch ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let branchRoute: String? = {
            if pickB.isEmpty && dropB.isEmpty { return nil }
            return "Çıkış şubesi: \(pickB.isEmpty ? "—" : pickB)  →  İade: \(dropB.isEmpty ? "—" : dropB)"
        }()
        let staffSig = TurkeyStaffPdfSignatureStore.loadSignatureImage()
        let staffNm = TurkeyStaffPdfSignatureStore.loadDisplayName(fallbackProfileFullName: staffSignerNameFallback)
        let payload = VehicleReturnPdfData(
            contractNo: contractNoValue,
            contractDate: dateFormatter.string(from: iade.iadeTarihi),
            contractPeriod: notEmpty(pickB),
            branch: notEmpty(dropB) ?? notEmpty(branch ?? ""),
            franchiseLegalTitle: notEmpty(franchiseDisplayName),
            branchRoutingLine: notEmpty(branchRoute ?? ""),
            customerFullName: notEmpty(iade.customerFullName),
            customerId: notEmpty(iade.customerNationalId ?? ""),
            customerPhone: nil,
            customerBirth: notEmpty(iade.customerEmail ?? ""),
            driverLicenseNo: nil,
            driverFullName: notEmpty(iade.customerFullName),
            testDriverFullName: notEmpty(iade.testDriverFullName),
            driverLicenseDate: nil,
            driverAddress: nil,
            returnDate: dateFormatter.string(from: iade.iadeTarihi),
            returnTime: timeFormatter.string(from: iade.iadeTarihi),
            returnLocation: branch,
            odometer: iade.km.map { String($0) },
            vehicleModel: notEmpty("\(arac.marka) \(arac.model)"),
            vehiclePlate: plate.isEmpty ? nil : plate,
            vehicleColor: nil,
            vehicleFuelType: normalizedFuelDisplay(iade.yakitSeviyesi),
            vehicleClass: nil,
            vehicleVIN: nil,
            fuelRatio: normalizedFuelRatio(iade.yakitSeviyesi),
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
            renterName: notEmpty(iade.customerFullName),
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
            timestamp: dateTimeFormatter.string(from: iade.iadeTarihi)
        )
        return TurkeyVehicleFormPdfBuilder().generatePdf(data: payload, kind: .vehicleReturn)
    }

    private func createPDF(
        iade: IadeIslemi,
        arac: Arac,
        images: [UIImage],
        damageImages: [UIImage],
        signatureImage: UIImage?,
        franchiseDisplayName: String,
        language: PDFContentLanguage,
        turkeyNavContractDisplay: String?,
        staffSignerNameFallback: String?
    ) -> URL? {
        let pdfData: Data
        if isTurkeyPDF(franchiseId: iade.franchiseId) {
            pdfData = buildTurkeyReturnPdfDocumentData(
                iade: iade,
                arac: arac,
                images: images,
                damageImages: damageImages,
                signatureImage: signatureImage,
                franchiseDisplayName: franchiseDisplayName,
                turkeyNavContractDisplay: turkeyNavContractDisplay,
                staffSignerNameFallback: staffSignerNameFallback
            )
        } else if FranchiseCapabilityMatrix.isSwitzerland(franchiseId: iade.franchiseId) {
            let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
            let dt = DateFormatter(); dt.dateFormat = "dd.MM.yyyy HH:mm"
            let branch = SwissReportPDFTemplate.branchName(
                franchiseId: iade.franchiseId,
                explicit: (iade.dropOffBranch ?? iade.pickUpBranch ?? iade.bayiAdi)
            )
            let fuel = normalizedFuelDisplay(iade.yakitSeviyesi)
                ?? (iade.km.map { "\($0) km" } ?? "—")
            pdfData = SwissReportPDFTemplate.renderHandover(
                kind: .returnReport,
                branch: branch,
                plate: iade.aracPlaka,
                vehicle: "\(arac.marka) \(arac.model)".trimmingCharacters(in: .whitespaces),
                dateText: dt.string(from: iade.iadeTarihi),
                fuelText: fuel,
                photoCount: images.count,
                customerName: iade.customerFullName,
                customerEmail: iade.customerEmail ?? "",
                signature: signatureImage,
                photos: images,
                photoStampDate: df.string(from: iade.iadeTarihi),
                signatureCaption: "Customer Signature · Vehicle Return"
            )
        } else {
            let pageWidth: CGFloat = 595
            let pageHeight: CGFloat = 842
            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
            pdfData = renderer.pdfData { context in
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
        let hasCustomerSection = signatureImage != nil

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

    private func normalizedFuelRatio(_ raw: String?) -> CGFloat? {
        guard let display = normalizedFuelDisplay(raw) else { return nil }
        let numerator = display.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? display
        guard let parsed = Int(numerator) else { return nil }
        return CGFloat(min(8, max(0, parsed))) / 8.0
    }

}
