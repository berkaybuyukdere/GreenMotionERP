import Foundation
import UIKit

/// UTF-8 CSV (Excel-compatible) + PDF exports for work hours: **one table per user** (User, Date, Clock in, Clock out, Hour total) + per-user **Total monthly** row, blank spacing between users.
enum WorkTimeExportHelper {

    private static let dayKeyInputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let exportDateColumnFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let exportTimeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Groups entries by `userId`; each group sorted by `dayKey`. Groups ordered by display name.
    private static func entriesGroupedByUser(_ entries: [WorkTimeEntry]) -> [[WorkTimeEntry]] {
        let grouped = Dictionary(grouping: entries, by: \.userId)
        let sortedIds = grouped.keys.sorted { a, b in
            let na = grouped[a]?.first?.userDisplayName ?? a
            let nb = grouped[b]?.first?.userDisplayName ?? b
            if na != nb { return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending }
            return a < b
        }
        return sortedIds.compactMap { uid in
            grouped[uid]?.sorted { $0.dayKey < $1.dayKey }
        }.filter { !$0.isEmpty }
    }

    private static func hourTotalString(minutes: Int) -> String {
        String(format: "%.1f", Double(minutes) / 60.0)
    }

    /// Holiday / day-off row label in exports (PDF + Excel HTML).
    private static var freeDayLabel: String { "Free".localized }

    private static func clockCells(for e: WorkTimeEntry) -> (clockIn: String, clockOut: String, hours: String) {
        if e.isHoliday {
            return (freeDayLabel, freeDayLabel, freeDayLabel)
        }
        return (
            exportTimeOnlyFormatter.string(from: e.clockIn),
            exportTimeOnlyFormatter.string(from: e.clockOut),
            hourTotalString(minutes: e.totalMinutes)
        )
    }

    private static func dateColumn(from dayKey: String) -> String {
        guard let d = dayKeyInputFormatter.date(from: dayKey) else { return dayKey }
        return exportDateColumnFormatter.string(from: d)
    }

    // MARK: - CSV (opens in Excel)

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    private static let csvBlankLine = ",,,,"

    private static var exportColumnHeaders: [String] {
        [
            "User".localized,
            "Date".localized,
            "Clock In".localized,
            "Clock Out".localized,
            "Hour total".localized
        ]
    }

    static func buildCSV(entries: [WorkTimeEntry], monthTitle: String) -> String {
        _ = monthTitle // Kept for call-site compatibility; export is per-user tables only.
        let groups = entriesGroupedByUser(entries)
        var lines: [String] = []

        for (gIndex, rows) in groups.enumerated() {
            if gIndex > 0 {
                lines.append(csvBlankLine)
                lines.append(csvBlankLine)
                lines.append(csvBlankLine)
            }

            lines.append(exportColumnHeaders.joined(separator: ","))

            var userMinutes = 0
            for e in rows {
                userMinutes += e.totalMinutes
                let clocks = clockCells(for: e)
                let row = [
                    csvEscape(e.userDisplayName),
                    csvEscape(dateColumn(from: e.dayKey)),
                    csvEscape(clocks.clockIn),
                    csvEscape(clocks.clockOut),
                    csvEscape(clocks.hours)
                ]
                lines.append(row.joined(separator: ","))
            }

            let totalRow = [
                csvEscape("Total monthly".localized),
                "",
                "",
                "",
                csvEscape(hourTotalString(minutes: userMinutes))
            ]
            lines.append(totalRow.joined(separator: ","))
        }

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
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2
        let colWidths: [CGFloat] = [118, 108, 100, 100, 89] // sums to `contentWidth` (A4 minus margins)
        let headerHeight: CGFloat = 18
        let rowHeight: CGFloat = 16
        let totalRowHeight: CGFloat = 20
        let userSectionGap: CGFloat = 22
        let bottomMargin: CGFloat = 44

        let fontRegular = UIFont(name: "Helvetica", size: 9) ?? UIFont.systemFont(ofSize: 9)
        let fontBold = UIFont(name: "Helvetica-Bold", size: 9) ?? UIFont.boldSystemFont(ofSize: 9)
        let fontTitle = UIFont(name: "Helvetica-Bold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        let fontSubtitle = UIFont(name: "Helvetica", size: 10) ?? UIFont.systemFont(ofSize: 10)

        let headers = exportColumnHeaders
        let groups = entriesGroupedByUser(entries)

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin

            func drawTitleBlock() {
                title.draw(at: CGPoint(x: margin, y: y),
                           withAttributes: [.font: fontTitle, .foregroundColor: UIColor.label])
                y += 22
                monthTitle.draw(at: CGPoint(x: margin, y: y),
                                withAttributes: [.font: fontSubtitle, .foregroundColor: UIColor.secondaryLabel])
                y += 14
                let gen = "Generated: ".localized + Date().formatted(date: .abbreviated, time: .shortened)
                gen.draw(at: CGPoint(x: margin, y: y),
                         withAttributes: [.font: fontSubtitle, .foregroundColor: UIColor.secondaryLabel])
                y += 20
            }

            func startPage(isFirst: Bool) {
                ctx.beginPage()
                y = margin
                if isFirst {
                    drawTitleBlock()
                } else {
                    let cont = title + " · " + monthTitle
                    cont.draw(at: CGPoint(x: margin, y: y),
                              withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])
                    y += 18
                }
            }

            func drawHeaderRow() {
                let cg = ctx.cgContext
                cg.setFillColor(UIColor(white: 0.90, alpha: 1).cgColor)
                cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: headerHeight))
                cg.setStrokeColor(UIColor.systemGray3.cgColor)
                cg.setLineWidth(0.5)
                var x = margin
                for (i, w) in colWidths.enumerated() {
                    if i > 0 {
                        cg.move(to: CGPoint(x: x, y: y))
                        cg.addLine(to: CGPoint(x: x, y: y + headerHeight))
                        cg.strokePath()
                    }
                    let r = CGRect(x: x + 4, y: y + 4, width: w - 8, height: headerHeight - 8)
                    headers[i].draw(in: r, withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])
                    x += w
                }
                cg.setLineWidth(0.7)
                cg.move(to: CGPoint(x: margin, y: y))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: y))
                cg.move(to: CGPoint(x: margin, y: y + headerHeight))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: y + headerHeight))
                cg.strokePath()
                y += headerHeight
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageHeight - bottomMargin {
                    startPage(isFirst: false)
                }
            }

            func drawDataRow(_ e: WorkTimeEntry, rowIndex: Int) {
                ensureSpace(rowHeight)
                let cg = ctx.cgContext
                if e.isHoliday {
                    cg.setFillColor(UIColor.systemGreen.withAlphaComponent(0.24).cgColor)
                    cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                } else if rowIndex % 2 == 0 {
                    cg.setFillColor(UIColor.systemGray6.withAlphaComponent(0.9).cgColor)
                    cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                }
                let clocks = clockCells(for: e)
                let cells: [String] = [
                    e.userDisplayName,
                    dateColumn(from: e.dayKey),
                    clocks.clockIn,
                    clocks.clockOut,
                    clocks.hours
                ]
                var x = margin
                for (i, text) in cells.enumerated() {
                    let r = CGRect(x: x + 4, y: y + 3, width: colWidths[i] - 8, height: rowHeight - 6)
                    let cellFont = (i == 0) ? fontBold : fontRegular
                    text.draw(in: r, withAttributes: [.font: cellFont, .foregroundColor: UIColor.label])
                    x += colWidths[i]
                }
                cg.setStrokeColor(UIColor.systemGray4.cgColor)
                cg.setLineWidth(0.3)
                cg.move(to: CGPoint(x: margin, y: y + rowHeight))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: y + rowHeight))
                cg.strokePath()
                y += rowHeight
            }

            func drawTotalMonthlyRow(userTotalMinutes: Int) {
                ensureSpace(totalRowHeight)
                let cg = ctx.cgContext
                cg.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
                cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: totalRowHeight))
                cg.setStrokeColor(UIColor.systemGray3.cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: margin, y: y))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: y))
                cg.move(to: CGPoint(x: margin, y: y + totalRowHeight))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: y + totalRowHeight))
                cg.strokePath()

                let label = "Total monthly".localized
                let labelWidth = colWidths[0] + colWidths[1] + colWidths[2] + colWidths[3] - 8
                label.draw(in: CGRect(x: margin + 4, y: y + 4, width: labelWidth, height: totalRowHeight - 8),
                           withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])
                let hrs = hourTotalString(minutes: userTotalMinutes)
                let hx = margin + colWidths[0] + colWidths[1] + colWidths[2] + colWidths[3]
                hrs.draw(in: CGRect(x: hx + 4, y: y + 4, width: colWidths[4] - 8, height: totalRowHeight - 8),
                         withAttributes: [.font: fontBold, .foregroundColor: UIColor.label])

                // Double rule under the hour-total column only
                let ux1 = hx + 4
                let ux2 = hx + colWidths[4] - 4
                let lineY = y + totalRowHeight - 4
                cg.setStrokeColor(UIColor.label.cgColor)
                cg.setLineWidth(0.55)
                cg.move(to: CGPoint(x: ux1, y: lineY))
                cg.addLine(to: CGPoint(x: ux2, y: lineY))
                cg.strokePath()
                cg.move(to: CGPoint(x: ux1, y: lineY + 1.9))
                cg.addLine(to: CGPoint(x: ux2, y: lineY + 1.9))
                cg.strokePath()
                y += totalRowHeight
            }

            startPage(isFirst: true)

            for (gIndex, rows) in groups.enumerated() {
                if gIndex > 0 {
                    ensureSpace(userSectionGap)
                    y += userSectionGap
                }

                let userTotal = rows.reduce(0) { $0 + $1.totalMinutes }

                ensureSpace(headerHeight)
                drawHeaderRow()

                for (idx, e) in rows.enumerated() {
                    if y + rowHeight > pageHeight - bottomMargin {
                        startPage(isFirst: false)
                        drawHeaderRow()
                    }
                    drawDataRow(e, rowIndex: idx)
                }

                if y + totalRowHeight > pageHeight - bottomMargin {
                    startPage(isFirst: false)
                }
                drawTotalMonthlyRow(userTotalMinutes: userTotal)
                y += 8
            }
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
