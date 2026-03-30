import Foundation
import UIKit

enum WorkTimeExportHelper {

    // MARK: - CSV

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    /// Build a clean CSV with columns: Employee, Clock In, Clock Out, Hours, Notes
    /// + a TOTAL row at the bottom.
    static func buildCSV(entries: [WorkTimeEntry], monthTitle: String) -> String {
        let headers = [
            "Employee".localized,
            "Clock In".localized,
            "Clock Out".localized,
            "Hours".localized,
            "Notes".localized
        ]
        var lines: [String] = [headers.joined(separator: ",")]

        let sorted = entries.sorted { lhs, rhs in
            if lhs.userId != rhs.userId { return lhs.userId < rhs.userId }
            return lhs.dayKey < rhs.dayKey
        }

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale.current
        timeFmt.dateStyle = .short
        timeFmt.timeStyle = .short

        var totalMinutes = 0
        for e in sorted {
            totalMinutes += e.totalMinutes
            let hoursDec = String(format: "%.2f", Double(e.totalMinutes) / 60.0)
            let row = [
                csvEscape(e.userDisplayName),
                csvEscape(timeFmt.string(from: e.clockIn)),
                csvEscape(timeFmt.string(from: e.clockOut)),
                hoursDec,
                csvEscape(e.notes)
            ]
            lines.append(row.joined(separator: ","))
        }

        // Total row
        let totalHours = String(format: "%.2f", Double(totalMinutes) / 60.0)
        let totalRow = [
            csvEscape("Total".localized + " — " + monthTitle),
            "",
            "",
            totalHours,
            ""
        ]
        lines.append(totalRow.joined(separator: ","))

        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    static func writeTempCSV(_ contents: String) throws -> URL {
        let name = "WorkHours-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = contents.data(using: .utf8) else {
            throw NSError(domain: "WorkTimeExport", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
        }
        try data.write(to: url)
        return url
    }

    // MARK: - PDF

    static func makePDF(entries: [WorkTimeEntry], title: String, monthTitle: String) -> URL? {
        let pageWidth: CGFloat = 595   // A4
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let colWidths: [CGFloat] = [130, 100, 100, 60, 165]   // Employee | Clock In | Clock Out | Hrs | Notes
        let headerHeight: CGFloat = 18
        let rowHeight: CGFloat = 16
        let tableTop: CGFloat = 130

        let fontRegular = UIFont(name: "Helvetica", size: 8) ?? UIFont.systemFont(ofSize: 8)
        let fontBold    = UIFont(name: "Helvetica-Bold", size: 8) ?? UIFont.boldSystemFont(ofSize: 8)
        let fontTitle   = UIFont(name: "Helvetica-Bold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        let fontSubtitle = UIFont(name: "Helvetica", size: 9) ?? UIFont.systemFont(ofSize: 9)

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let sorted = entries.sorted { lhs, rhs in
            if lhs.userId != rhs.userId { return lhs.userId < rhs.userId }
            return lhs.dayKey < rhs.dayKey
        }

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale.current
        timeFmt.dateStyle = .short
        timeFmt.timeStyle = .short

        let colHeaders = [
            "Employee".localized,
            "Clock In".localized,
            "Clock Out".localized,
            "Hours".localized,
            "Notes".localized
        ]
        let totalMinutesAll = sorted.reduce(0) { $0 + $1.totalMinutes }
        let totalHoursStr = String(format: "%.2f h", Double(totalMinutesAll) / 60.0)

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            var remainingEntries = sorted[...]
            var isFirstPage = true

            func beginPage() {
                ctx.beginPage()
                let cgCtx = ctx.cgContext

                if isFirstPage {
                    // Title block
                    title.draw(at: CGPoint(x: margin, y: margin),
                               withAttributes: [.font: fontTitle, .foregroundColor: UIColor.label])
                    y = margin + 24
                    monthTitle.draw(at: CGPoint(x: margin, y: y),
                                    withAttributes: [.font: fontSubtitle, .foregroundColor: UIColor.secondaryLabel])
                    y += 14
                    let genDate = "Generated: ".localized + Date().formatted(date: .abbreviated, time: .shortened)
                    genDate.draw(at: CGPoint(x: margin, y: y),
                                 withAttributes: [.font: fontSubtitle, .foregroundColor: UIColor.secondaryLabel])
                    y = tableTop
                    isFirstPage = false
                } else {
                    y = margin
                }

                // Draw column header row background
                cgCtx.setFillColor(UIColor.systemTeal.withAlphaComponent(0.15).cgColor)
                cgCtx.fill(CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: headerHeight))

                // Column header borders
                cgCtx.setStrokeColor(UIColor.systemGray3.cgColor)
                cgCtx.setLineWidth(0.5)
                var x: CGFloat = margin
                for (i, w) in colWidths.enumerated() {
                    if i > 0 {
                        cgCtx.move(to: CGPoint(x: x, y: y))
                        cgCtx.addLine(to: CGPoint(x: x, y: y + headerHeight))
                        cgCtx.strokePath()
                    }
                    // Header text
                    let headerRect = CGRect(x: x + 3, y: y + 3, width: w - 6, height: headerHeight - 6)
                    colHeaders[i].draw(in: headerRect,
                                       withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])
                    x += w
                }
                // Top & bottom border of header
                cgCtx.setLineWidth(0.7)
                cgCtx.move(to: CGPoint(x: margin, y: y))
                cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                cgCtx.strokePath()
                cgCtx.move(to: CGPoint(x: margin, y: y + headerHeight))
                cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y + headerHeight))
                cgCtx.strokePath()

                y += headerHeight
            }

            beginPage()

            // Data rows
            for (rowIdx, entry) in sorted.enumerated() {
                let bottomLimit = pageHeight - margin - rowHeight - 20
                if y + rowHeight > bottomLimit {
                    beginPage()
                }

                let cgCtx = ctx.cgContext
                // Alternating background
                if rowIdx % 2 == 0 {
                    cgCtx.setFillColor(UIColor.systemGray6.cgColor)
                    cgCtx.fill(CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight))
                }

                let hoursDec = String(format: "%.2f", Double(entry.totalMinutes) / 60.0)
                let cells = [
                    entry.userDisplayName,
                    timeFmt.string(from: entry.clockIn),
                    timeFmt.string(from: entry.clockOut),
                    hoursDec,
                    entry.notes
                ]

                var x: CGFloat = margin
                for (i, cell) in cells.enumerated() {
                    let cellRect = CGRect(x: x + 3, y: y + 3, width: colWidths[i] - 6, height: rowHeight - 6)
                    cell.draw(in: cellRect,
                              withAttributes: [.font: fontRegular, .foregroundColor: UIColor.label])
                    x += colWidths[i]
                }

                // Bottom border
                cgCtx.setStrokeColor(UIColor.systemGray4.cgColor)
                cgCtx.setLineWidth(0.3)
                cgCtx.move(to: CGPoint(x: margin, y: y + rowHeight))
                cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y + rowHeight))
                cgCtx.strokePath()

                y += rowHeight
                _ = remainingEntries.dropFirst()
            }

            // Total row
            let totalRowH: CGFloat = 20
            if y + totalRowH > pageHeight - margin {
                beginPage()
            }
            let cgCtx = ctx.cgContext
            cgCtx.setFillColor(UIColor.systemTeal.withAlphaComponent(0.18).cgColor)
            cgCtx.fill(CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: totalRowH))
            cgCtx.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.6).cgColor)
            cgCtx.setLineWidth(0.8)
            cgCtx.move(to: CGPoint(x: margin, y: y))
            cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            cgCtx.strokePath()
            cgCtx.move(to: CGPoint(x: margin, y: y + totalRowH))
            cgCtx.addLine(to: CGPoint(x: pageWidth - margin, y: y + totalRowH))
            cgCtx.strokePath()

            let totalLabel = "Total".localized + " — " + monthTitle
            totalLabel.draw(in: CGRect(x: margin + 3, y: y + 5, width: colWidths[0] - 6, height: totalRowH - 6),
                            withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])
            // Hours column x
            var totalHrsX = margin + colWidths[0] + colWidths[1] + colWidths[2]
            totalHoursStr.draw(in: CGRect(x: totalHrsX + 3, y: y + 5, width: colWidths[3] - 6, height: totalRowH - 6),
                               withAttributes: [.font: fontBold, .foregroundColor: UIColor.systemTeal])
            _ = totalHrsX
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkHours-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
