import UIKit

/// Fleet handover inspection PDF — all vehicle damage records, green-branded layout.
enum FleetInspectionReportPDF {
    static func render(context: FleetInspectionContext, arac: Arac, damages: [HasarKaydi]) -> Data {
        let pageW: CGFloat = 595.2
        let pageH: CGFloat = 841.8
        let margin: CGFloat = 42
        let green = UIColor(red: 0.22, green: 0.78, blue: 0.45, alpha: 1)
        let dark = UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
        let muted = UIColor(red: 0.45, green: 0.48, blue: 0.52, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let df = DateFormatter()
        df.dateFormat = "dd MMM yyyy, HH:mm"
        let sorted = damages.sorted { $0.tarih > $1.tarih }

        return renderer.pdfData { ctx in
            var y = margin

            func newPageIfNeeded(_ extra: CGFloat) {
                if y + extra > pageH - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            func drawHeader() {
                ctx.beginPage()
                y = margin
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: dark
                ]
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: muted
                ]
                "Fleet Inspection Handover System".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                green.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y + 30, width: pageW - margin * 2, height: 3)).fill()
                y += 42
                "\(arac.marka) \(arac.model) · \(arac.plaka)".draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
                y += 16
                "Inspection \(context.inspectionId) · \(df.string(from: Date()))".draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
                y += 14
                "Customer: \(context.customerName) · \(context.reservationCode)".draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
                y += 22
            }

            drawHeader()

            let boxAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: muted
            ]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: dark
            ]
            let summary: [(String, String)] = [
                ("Handover", "\(context.handoverDate) \(context.handoverTime) · \(context.mileageHandover) · fuel \(context.fuelHandover)"),
                ("Return", "\(context.returnDate) \(context.returnTime) · \(context.mileageReturn) · fuel \(context.fuelReturn)"),
                ("Status", context.rentalStatus),
                ("Branch", context.branchName)
            ]
            for (label, value) in summary {
                newPageIfNeeded(20)
                label.draw(at: CGPoint(x: margin, y: y), withAttributes: boxAttrs)
                value.draw(at: CGPoint(x: margin + 72, y: y), withAttributes: valAttrs)
                y += 18
            }
            y += 12

            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: green
            ]
            "Damage register (\(sorted.count))".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            if sorted.isEmpty {
                let emptyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: muted
                ]
                "No damage records on file for this vehicle.".draw(at: CGPoint(x: margin, y: y), withAttributes: emptyAttrs)
                y += 20
            } else {
                let colHeaders = ["#", "Area", "Date", "RES", "KM", "Status", "Notes"]
                let colX: [CGFloat] = [margin, margin + 22, margin + 100, margin + 175, margin + 250, margin + 295, margin + 360]
                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                green.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: pageW - margin * 2, height: 16)).fill()
                for (i, h) in colHeaders.enumerated() {
                    h.draw(at: CGPoint(x: colX[i], y: y + 3), withAttributes: headerAttrs)
                }
                y += 20

                for (idx, d) in sorted.enumerated() {
                    newPageIfNeeded(22)
                    if idx % 2 == 0 {
                        UIColor(white: 0.96, alpha: 1).setFill()
                        UIBezierPath(rect: CGRect(x: margin, y: y - 2, width: pageW - margin * 2, height: 18)).fill()
                    }
                    let rowAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 8),
                        .foregroundColor: dark
                    ]
                    let cells = [
                        "\(idx + 1)",
                        d.damageZone ?? "—",
                        df.string(from: d.tarih),
                        d.resKodu,
                        "\(d.km)",
                        d.durum.rawValue,
                        String(d.notlar.prefix(40))
                    ]
                    for (i, cell) in cells.enumerated() {
                        cell.draw(at: CGPoint(x: colX[i], y: y), withAttributes: rowAttrs)
                    }
                    y += 18
                }
            }

            y += 16
            newPageIfNeeded(40)
            let footAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: muted
            ]
            "© Green Motion — Confidential fleet inspection report. Generated from live vehicle data.".draw(
                in: CGRect(x: margin, y: y, width: pageW - margin * 2, height: 30),
                withAttributes: footAttrs
            )
        }
    }
}
