import UIKit
import CoreImage

/// Options for condition-form PDF (e-signature QR is franchise-scoped via URL + Firestore path).
struct ConditionFormPDFOptions {
    var signatureQRToken: String?
    var franchiseIdForQR: String?
}

final class ConditionFormPDFGenerator {
    static let shared = ConditionFormPDFGenerator()

    private let renderQueue = DispatchQueue(label: "condition-form-pdf-render", qos: .userInitiated)

    private init() {}

    /// Generates a shareable PDF file URL in background. Caller can pass the URL directly to ActivityViewController.
    func generateConditionFormPDF(
        arac: Arac,
        damages: [HasarKaydi],
        options: ConditionFormPDFOptions = ConditionFormPDFOptions(),
        completion: @escaping (URL?) -> Void
    ) {
        let entries = damages.sorted { $0.tarih > $1.tarih }
        renderQueue.async {
            let filename = self.conditionFormFilename(plate: arac.plakaFormatli, date: Date())
            guard
                let data = self.createPDFData(arac: arac, damages: entries, options: options),
                let url = self.writeToTemporaryDirectory(data: data, filename: filename)
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Generates PDF data on demand without persisting it permanently.
    func generateConditionFormPDFData(
        arac: Arac,
        damages: [HasarKaydi],
        options: ConditionFormPDFOptions = ConditionFormPDFOptions(),
        completion: @escaping (Data?) -> Void
    ) {
        let entries = damages.sorted { $0.tarih > $1.tarih }
        renderQueue.async {
            let data = self.createPDFData(arac: arac, damages: entries, options: options)
            DispatchQueue.main.async { completion(data) }
        }
    }

    private func createPDFData(arac: Arac, damages: [HasarKaydi], options: ConditionFormPDFOptions) -> Data? {
        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let margin: CGFloat = 24
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 13) ?? UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor(white: 0.12, alpha: 1)
        ]
        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor(white: 0.18, alpha: 1)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 10) ?? UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor(white: 0.18, alpha: 1)
        ]
        let microAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica", size: 8) ?? UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor(white: 0.35, alpha: 1)
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let pdfData = renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            var y: CGFloat = margin + 4

            // Header title bar (gray)
            let titleBar = CGRect(x: margin, y: y, width: pageW - margin * 2, height: 24)
            cg.setFillColor(UIColor(white: 0.90, alpha: 1).cgColor)
            cg.fill(titleBar)
            cg.setStrokeColor(UIColor(white: 0.65, alpha: 1).cgColor)
            cg.stroke(titleBar)
            "Vehicle Condition Report Form - OUT".draw(
                at: CGPoint(x: titleBar.minX + 8, y: titleBar.minY + 5),
                withAttributes: titleAttrs
            )
            y = titleBar.maxY + 8

            // Info grid (black/gray typography)
            let leftBox = CGRect(x: margin, y: y, width: (pageW - margin * 2) * 0.62, height: 64)
            let rightBox = CGRect(x: leftBox.maxX + 6, y: y, width: (pageW - margin * 2) - leftBox.width - 6, height: 64)
            for box in [leftBox, rightBox] {
                cg.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                cg.fill(box)
                cg.setStrokeColor(UIColor(white: 0.72, alpha: 1).cgColor)
                cg.stroke(box)
            }
            "Customer: -".draw(at: CGPoint(x: leftBox.minX + 8, y: leftBox.minY + 8), withAttributes: bodyAttrs)
            "Reg No: \(arac.plakaFormatli)".draw(at: CGPoint(x: leftBox.minX + 8, y: leftBox.minY + 22), withAttributes: bodyAttrs)
            "Vehicle Type: \(arac.marka) \(arac.model)".draw(at: CGPoint(x: leftBox.minX + 8, y: leftBox.minY + 36), withAttributes: bodyAttrs)
            "Smoking is not permitted in the vehicle.".draw(at: CGPoint(x: rightBox.minX + 8, y: rightBox.minY + 8), withAttributes: bodyAttrs)
            "Generated: \(dateFormatter.string(from: Date()))".draw(at: CGPoint(x: rightBox.minX + 8, y: rightBox.minY + 26), withAttributes: microAttrs)
            "Vehicle Excess: 0.00 CHF".draw(at: CGPoint(x: rightBox.minX + 8, y: rightBox.minY + 42), withAttributes: microAttrs)
            y = leftBox.maxY + 10

            // 2D map area
            let mapRect = CGRect(x: margin, y: y, width: pageW - (margin * 2), height: 300)
            cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            cg.fill(mapRect)
            cg.setStrokeColor(UIColor(white: 0.70, alpha: 1).cgColor)
            cg.stroke(mapRect)

            if let image = UIImage(named: "condition_vehicle_2d") {
                image.draw(in: mapRect)
            }

            for damage in damages where damage.isConditionForm == true {
                guard
                    let blockId = damage.conditionViewBlockId,
                    let block = VehicleViewBlock.block(id: blockId),
                    let nx = damage.conditionPointX,
                    let ny = damage.conditionPointY
                else { continue }

                let ref = block.normToRef(CGPoint(x: nx, y: ny))
                let px = mapRect.minX + (ref.x / VehicleRef.canvasWidth) * mapRect.width
                let py = mapRect.minY + (ref.y / VehicleRef.canvasHeight) * mapRect.height

                let markerR: CGFloat = 8
                let markerRect = CGRect(x: px - markerR, y: py - markerR, width: markerR * 2, height: markerR * 2)
                cg.setFillColor(UIColor(red: 0.85, green: 0.08, blue: 0.08, alpha: 1).cgColor)
                cg.fillEllipse(in: markerRect)

                let nText = "\(damage.markerNumber ?? 0)" as NSString
                nText.draw(at: CGPoint(x: px - 3, y: py - 5), withAttributes: [
                    .font: UIFont(name: "Helvetica-Bold", size: 8) ?? UIFont.boldSystemFont(ofSize: 8),
                    .foregroundColor: UIColor.white
                ])
            }

            // Bottom split like source template: legal left / damage info right
            let bottomY = mapRect.maxY + 10
            let colGap: CGFloat = 8
            let bottomReserved: CGFloat = 88
            let leftCol = CGRect(x: margin, y: bottomY, width: (pageW - margin * 2 - colGap) * 0.50, height: pageH - bottomY - margin - bottomReserved)
            let rightCol = CGRect(x: leftCol.maxX + colGap, y: bottomY, width: (pageW - margin * 2 - colGap) * 0.50, height: pageH - bottomY - margin - bottomReserved)
            for box in [leftCol, rightCol] {
                cg.setFillColor(UIColor(white: 0.98, alpha: 1).cgColor)
                cg.fill(box)
                cg.setStrokeColor(UIColor(white: 0.75, alpha: 1).cgColor)
                cg.stroke(box)
            }

            "Vehicle Handover Agreement".draw(at: CGPoint(x: leftCol.minX + 6, y: leftCol.minY + 6), withAttributes: headingAttrs)
            var ly = leftCol.minY + 22
            for line in ConditionFormViewModel.legalInformation {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let bulletLine = "• \(trimmed)" as NSString
                bulletLine.draw(
                    in: CGRect(x: leftCol.minX + 6, y: ly, width: leftCol.width - 12, height: 34),
                    withAttributes: microAttrs
                )
                ly += 28
                if ly > leftCol.maxY - 24 { break }
            }

            "Damage Information".draw(at: CGPoint(x: rightCol.minX + 6, y: rightCol.minY + 6), withAttributes: headingAttrs)
            var ry = rightCol.minY + 22
            for (idx, hasar) in damages.enumerated() {
                if ry > rightCol.maxY - 18 { break }
                let typeText = (hasar.damageType?.isEmpty == false ? hasar.damageType! : hasar.durum.displayTitle)
                let severityText = (hasar.damageSeverity?.isEmpty == false ? hasar.damageSeverity! : hasar.status.rawValue)
                var line = "\(idx + 1)  \(typeText)  \(severityText)"
                if let regionId = hasar.conditionRegionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !regionId.isEmpty,
                   let def = VehicleRegionDef.region(id: regionId) {
                    line += "  \(def.displayName)"
                }
                line.draw(
                    in: CGRect(x: rightCol.minX + 6, y: ry, width: rightCol.width - 12, height: 22),
                    withAttributes: microAttrs
                )
                ry += 16
            }

            // Signature strip + optional e-sign QR + copyright
            let footerTop = pageH - margin - 58
            let footerRect = CGRect(x: margin, y: footerTop, width: pageW - margin * 2, height: 44)
            cg.setStrokeColor(UIColor(white: 0.68, alpha: 1).cgColor)
            cg.stroke(footerRect)

            var signLineX = footerRect.minX + 8
            if let token = options.signatureQRToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty,
               let fid = options.franchiseIdForQR?.trimmingCharacters(in: .whitespacesAndNewlines), !fid.isEmpty,
               let qr = Self.qrCodeImage(from: "https://greenmotionapp-33413.web.app/condition-signature.html?token=\(token)&franchise=\(fid)") {
                let qrSide: CGFloat = 40
                let qrRect = CGRect(x: footerRect.minX + 6, y: footerRect.minY + 2, width: qrSide, height: qrSide)
                qr.draw(in: qrRect)
                signLineX = qrRect.maxX + 10
                "E-signature (scan)".draw(at: CGPoint(x: qrRect.minX, y: qrRect.maxY + 2), withAttributes: microAttrs)
            }

            ("OUT   Signed: _________________________   Date & Time: \(dateFormatter.string(from: Date()))" as NSString)
                .draw(at: CGPoint(x: signLineX, y: footerRect.minY + 14), withAttributes: microAttrs)

            let copyright = "This document is copyrighted. Unauthorized sharing is not permitted." as NSString
            let cSize = copyright.size(withAttributes: microAttrs)
            let cx = (pageW - cSize.width) / 2
            copyright.draw(at: CGPoint(x: cx, y: pageH - margin - 10), withAttributes: microAttrs)
        }

        return pdfData
    }

    private static func qrCodeImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(ciImage: scaled)
    }

    private func normalizedLocationDescription(for hasar: HasarKaydi) -> String {
        // New system: VehicleRegionDef IDs (e.g. "ct_hood", "ts_front_tire")
        if let regionId = hasar.conditionRegionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !regionId.isEmpty,
           let def = VehicleRegionDef.region(id: regionId) {
            let blockName  = VehicleViewBlock.block(id: def.viewBlockId)?.displayName ?? ""
            let pointText  = normalizedPointText(for: hasar)
            return "\(def.displayName) (\(blockName))\(pointText)"
        }
        // Legacy system: CarDamageZone raw values
        if let raw = hasar.damageZone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            if let zone = CarDamageZone(rawValue: raw) {
                return "\(zone.displayName) [legacy]"
            }
            return "\(raw) [legacy]"
        }
        return "No mapped region"
    }

    private func normalizedPointText(for hasar: HasarKaydi) -> String {
        guard let x = hasar.conditionPointX, let y = hasar.conditionPointY else { return " [mapped]" }
        let xPct = Int((x * 100).rounded())
        let yPct = Int((y * 100).rounded())
        return " [\(xPct)%, \(yPct)%]"
    }

    private func conditionFormFilename(plate: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let safePlate = sanitizeFileNameSegment(plate)
        return "\(safePlate) - \(formatter.string(from: date)) - Condition Form.pdf"
    }

    private func sanitizeFileNameSegment(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = value.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let merged = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? "UNKNOWN-PLATE" : merged
    }

    private func writeToTemporaryDirectory(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("❌ Condition form PDF write failed: \(error)")
            return nil
        }
    }
}
