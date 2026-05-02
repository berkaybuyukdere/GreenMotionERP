import Foundation
import PDFKit
import UIKit

/// Generates daily shuttle reports in PDF and CSV formats
class ShuttleReportGenerator {
    static let shared = ShuttleReportGenerator()
    
    private init() {}
    
    // MARK: - Session Report (Called when session ends)
    
    func generateSessionReport(session: ShuttleSession) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if let url = self.generatePDFReport(for: session) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShuttleReportGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PDF report"]))
                }
            }
        }
    }
    
    // MARK: - PDF Generation
    
    func generatePDFReport(for session: ShuttleSession) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: PDFExportBranding.pdfMetadataCreatorShuttle,
            kCGPDFContextAuthor: PDFExportBranding.pdfMetadataAuthor,
            kCGPDFContextTitle: "Shuttle Report - \(session.formattedDate)"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { (context) in
            context.beginPage()
            let ctx = context.cgContext
            
            // MARK: - SWISS DESIGN HEADER (Minimal, no colors)
            var yPosition: CGFloat = 60
            
            let companyName = PDFExportBranding.genericCompanyTitle
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: companyFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let subtitle = UserDefaults.standard.selectedCountry.name.uppercased()
            let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
            subtitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: subtitleFont, .foregroundColor: SwissPDFHelper.mediumGray])
            yPosition += 40
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageWidth - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // Title
            let titleFont = SwissPDFHelper.helveticaBold(size: 24)
            let titleText = "Daily Shuttle Report"
            titleText.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: titleFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 35
            
            // Date and Driver Info
            let infoFont = SwissPDFHelper.helvetica(size: 10)
            let infoLabelFont = SwissPDFHelper.helveticaBold(size: 10)
            
            "Date:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: infoLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(session.formattedDate)".draw(at: CGPoint(x: 120, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            "Driver:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: infoLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(session.driverName)".draw(at: CGPoint(x: 120, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 18
            
            "Duration:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: infoLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(session.duration)".draw(at: CGPoint(x: 120, y: yPosition), withAttributes: [.font: infoFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 30
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageWidth - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // Summary - No boxes, just clean lines
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            let summaryBoldFont = SwissPDFHelper.helveticaBold(size: 14)
            
            "Total Customers:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(session.totalCustomers)".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 20
            
            "Total Entries:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(session.entries.count)".draw(at: CGPoint(x: 200, y: yPosition - 2), withAttributes: [.font: summaryBoldFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 30
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageWidth - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // Table Header - Bold, underlined
            let headerFont = SwissPDFHelper.helveticaBold(size: 9)
            let headerY = yPosition
            "DATE & TIME".draw(at: CGPoint(x: 60, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "TYPE".draw(at: CGPoint(x: 250, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "CUSTOMERS".draw(at: CGPoint(x: 400, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            
            // Underline header
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: headerY + 12), to: CGPoint(x: pageWidth - 60, y: headerY + 12), width: 0.5)
            yPosition += 20
            
            // Table Rows
            let rowFont = SwissPDFHelper.helvetica(size: 9)
            
            for (index, entry) in session.entries.enumerated() {
                // Check if we need a new page
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = 60
                    
                    // Redraw header on new page
                    let newHeaderY = yPosition
                    "DATE & TIME".draw(at: CGPoint(x: 60, y: newHeaderY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    "TYPE".draw(at: CGPoint(x: 250, y: newHeaderY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    "CUSTOMERS".draw(at: CGPoint(x: 400, y: newHeaderY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: newHeaderY + 12), to: CGPoint(x: pageWidth - 60, y: newHeaderY + 12), width: 0.5)
                    yPosition += 20
                }
                
                // No alternating colors - just clean lines
                entry.formattedDateTime.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                entry.entryType.rawValue.draw(at: CGPoint(x: 250, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                "\(entry.customerCount)".draw(at: CGPoint(x: 400, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                
                // Thin separator line
                if index < session.entries.count - 1 {
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition + 12), to: CGPoint(x: pageWidth - 60, y: yPosition + 12), width: 0.25)
                }
                
                yPosition += 18
            }
            
            // Footer
            let footerY = pageHeight - 30
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 20), to: CGPoint(x: pageWidth - 60, y: footerY - 20), width: 0.25)
            
            let footerFont = SwissPDFHelper.helveticaThin(size: 7)
            let footerText = "\(PDFExportBranding.copyrightLine) • \(UserDefaults.standard.selectedCountry.name)"
            footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
            "1".draw(at: CGPoint(x: pageWidth - 80, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
        }
        
        // Save to temporary file
        let fileName = "shuttle_report_\(session.date.formatted(date: .abbreviated, time: .omitted)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: url)
            print("âœ… PDF report saved: \(url)")
            return url
        } catch {
            print("âŒ Error saving PDF: \(error)")
            return nil
        }
    }
    
    // MARK: - CSV Generation
    
    func generateCSVReport(for session: ShuttleSession) -> URL? {
        var csvText = "Shuttle Daily Report\n"
        csvText += "\(UserDefaults.standard.selectedCountry.name)\n"
        csvText += "Date,\(session.formattedDate)\n"
        csvText += "Driver,\(session.driverName)\n"
        csvText += "Duration,\(session.duration)\n"
        csvText += "Total Customers,\(session.totalCustomers)\n"
        csvText += "Total Entries,\(session.entries.count)\n"
        csvText += "\n"
        csvText += "Date & Time,Type,Customers\n"
        
        for entry in session.entries {
            let dateTime = entry.formattedDateTime.replacingOccurrences(of: ",", with: ";")
            let type = entry.entryType.rawValue.replacingOccurrences(of: ",", with: ";")
            csvText += "\(dateTime),\(type),\(entry.customerCount)\n"
        }

        csvText += "\n\(PDFExportBranding.csvGeneratedByLine)\n"

        let fileName = "shuttle_report_\(session.date.formatted(date: .abbreviated, time: .omitted)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvText.write(to: url, atomically: true, encoding: .utf8)
            print("âœ… CSV report saved: \(url)")
            return url
        } catch {
            print("âŒ Error saving CSV: \(error)")
            return nil
        }
    }
    
    // MARK: - Excel-compatible CSV (with UTF-8 BOM)
    
    func generateExcelCSVReport(for session: ShuttleSession) -> URL? {
        guard let csvURL = generateCSVReport(for: session) else { return nil }
        
        // Add UTF-8 BOM for Excel compatibility
        do {
            let csvData = try Data(contentsOf: csvURL)
            var dataWithBOM = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM
            dataWithBOM.append(csvData)
            
            let fileName = "shuttle_report_excel_\(session.date.formatted(date: .abbreviated, time: .omitted)).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            try dataWithBOM.write(to: url)
            print("âœ… Excel-compatible CSV saved: \(url)")
            return url
        } catch {
            print("âŒ Error creating Excel CSV: \(error)")
            return nil
        }
    }

    // MARK: - Monthly entries report (canonical `shuttleEntries`, matches Daily Shuttle Reports screen)

    /// Builds a PDF from top-level shuttle entries (same collection as `DailyShuttleReportView`).
    /// Use this instead of aggregating empty `shuttleSessions` when entries are stored only in `shuttleEntries`.
    func generateShuttleEntriesMonthlyReportPDF(entries: [ShuttleEntry], monthLabel: String) -> URL? {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let totalCustomers = sorted.reduce(0) { $0 + $1.customerCount }
        let pickupRows = sorted.filter { $0.entryType == .pickup }
        let dropoffRows = sorted.filter { $0.entryType == .dropoff }
        let pickupCustomers = pickupRows.reduce(0) { $0 + $1.customerCount }
        let dropoffCustomers = dropoffRows.reduce(0) { $0 + $1.customerCount }

        let pdfMetaData = [
            kCGPDFContextCreator: PDFExportBranding.pdfMetadataCreatorShuttle,
            kCGPDFContextAuthor: PDFExportBranding.pdfMetadataAuthor,
            kCGPDFContextTitle: "Shuttle Entries — \(monthLabel)"
        ] as [String: Any]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeStyle = .short

        let data = renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            var y: CGFloat = 60

            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            PDFExportBranding.genericCompanyTitle.draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: companyFont, .foregroundColor: SwissPDFHelper.black])
            y += 25

            let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
            UserDefaults.standard.selectedCountry.name.uppercased().draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: subtitleFont, .foregroundColor: SwissPDFHelper.mediumGray])
            y += 40

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 28

            let titleFont = SwissPDFHelper.helveticaBold(size: 22)
            "Shuttle entries report".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: titleFont, .foregroundColor: SwissPDFHelper.black])
            y += 28

            let metaFont = SwissPDFHelper.helvetica(size: 10)
            let labelFont = SwissPDFHelper.helveticaBold(size: 10)
            "Month:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            monthLabel.draw(at: CGPoint(x: 110, y: y), withAttributes: [.font: metaFont, .foregroundColor: SwissPDFHelper.black])
            y += 16

            "Total rows:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            "\(sorted.count)".draw(at: CGPoint(x: 130, y: y), withAttributes: [.font: metaFont, .foregroundColor: SwissPDFHelper.black])
            y += 16

            "Customers (all):".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            "\(totalCustomers)".draw(at: CGPoint(x: 160, y: y), withAttributes: [.font: metaFont, .foregroundColor: SwissPDFHelper.black])
            y += 16

            "Pickups / drop-offs (customers):".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: labelFont, .foregroundColor: SwissPDFHelper.black])
            "\(pickupCustomers) / \(dropoffCustomers)".draw(at: CGPoint(x: 230, y: y), withAttributes: [.font: metaFont, .foregroundColor: SwissPDFHelper.black])
            y += 28

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 22

            let headerFont = SwissPDFHelper.helveticaBold(size: 8)
            let rowFont = SwissPDFHelper.helvetica(size: 8)
            let headerY = y
            "DATE & TIME".draw(at: CGPoint(x: 60, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "TYPE".draw(at: CGPoint(x: 200, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "QTY".draw(at: CGPoint(x: 270, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "DRIVER".draw(at: CGPoint(x: 320, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: headerY + 11), to: CGPoint(x: pageRect.width - 60, y: headerY + 11), width: 0.5)
            y = headerY + 20

            func truncate(_ s: String, maxLen: Int) -> String {
                guard s.count > maxLen else { return s }
                return String(s.prefix(maxLen - 1)) + "…"
            }

            for (index, entry) in sorted.enumerated() {
                if y > pageRect.height - 90 {
                    context.beginPage()
                    y = 60
                    let hy = y
                    "DATE & TIME".draw(at: CGPoint(x: 60, y: hy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    "TYPE".draw(at: CGPoint(x: 200, y: hy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    "QTY".draw(at: CGPoint(x: 270, y: hy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    "DRIVER".draw(at: CGPoint(x: 320, y: hy), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: hy + 11), to: CGPoint(x: pageRect.width - 60, y: hy + 11), width: 0.5)
                    y = hy + 20
                }

                let dt = dateTimeFormatter.string(from: entry.timestamp)
                let typeStr = entry.entryType.rawValue
                let driver = truncate(entry.driverName, maxLen: 36)

                dt.draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                typeStr.draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                "\(entry.customerCount)".draw(at: CGPoint(x: 270, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                driver.draw(at: CGPoint(x: 320, y: y), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])

                if index < sorted.count - 1 {
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y + 11), to: CGPoint(x: pageRect.width - 60, y: y + 11), width: 0.2)
                }
                y += 15
            }

            let footerY = pageRect.height - 28
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 14), to: CGPoint(x: pageRect.width - 60, y: footerY - 14), width: 0.25)
            let footerFont = SwissPDFHelper.helveticaThin(size: 7)
            let footerText = "\(PDFExportBranding.copyrightLine) • \(UserDefaults.standard.selectedCountry.name)"
            footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
        }

        let safeMonth = monthLabel.replacingOccurrences(of: " ", with: "_")
        let fileName = "shuttle_entries_\(safeMonth).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("Shuttle entries PDF write error: \(error)")
            return nil
        }
    }
}
