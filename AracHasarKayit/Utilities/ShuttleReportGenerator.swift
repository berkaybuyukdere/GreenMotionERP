import Foundation
import PDFKit
import UIKit

/// Generates daily shuttle reports in PDF and CSV formats
class ShuttleReportGenerator {
    static let shared = ShuttleReportGenerator()
    
    private init() {}
    
    // MARK: - PDF Generation
    
    func generatePDFReport(for session: ShuttleSession) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "Green Motion Shuttle",
            kCGPDFContextAuthor: session.driverName,
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
            
            var yPosition: CGFloat = 60
            
            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let titleText = "Daily Shuttle Report"
            let titleSize = titleText.size(withAttributes: titleAttributes)
            let titleRect = CGRect(x: (pageWidth - titleSize.width) / 2, y: yPosition, width: titleSize.width, height: titleSize.height)
            titleText.draw(in: titleRect, withAttributes: titleAttributes)
            
            yPosition += titleSize.height + 30
            
            // Date and Driver Info
            let infoFont = UIFont.systemFont(ofSize: 14)
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: infoFont,
                .foregroundColor: UIColor.darkGray
            ]
            
            let infoLines = [
                "Date: \(session.formattedDate)",
                "Driver: \(session.driverName)",
                "Duration: \(session.duration)",
                ""
            ]
            
            for line in infoLines {
                let lineSize = line.size(withAttributes: infoAttributes)
                let lineRect = CGRect(x: 60, y: yPosition, width: pageWidth - 120, height: lineSize.height)
                line.draw(in: lineRect, withAttributes: infoAttributes)
                yPosition += lineSize.height + 8
            }
            
            yPosition += 20
            
            // Summary Box
            let summaryRect = CGRect(x: 60, y: yPosition, width: pageWidth - 120, height: 100)
            
            // Background
            let summaryPath = UIBezierPath(roundedRect: summaryRect, cornerRadius: 10)
            UIColor.systemCyan.withAlphaComponent(0.1).setFill()
            summaryPath.fill()
            UIColor.systemCyan.setStroke()
            summaryPath.lineWidth = 2
            summaryPath.stroke()
            
            // Summary text
            let summaryFont = UIFont.boldSystemFont(ofSize: 18)
            let summaryAttributes: [NSAttributedString.Key: Any] = [
                .font: summaryFont,
                .foregroundColor: UIColor.black
            ]
            
            let totalCustomersText = "Total Customers: \(session.totalCustomers)"
            let totalEntriesText = "Total Entries: \(session.entries.count)"
            
            totalCustomersText.draw(at: CGPoint(x: 80, y: yPosition + 30), withAttributes: summaryAttributes)
            totalEntriesText.draw(at: CGPoint(x: 80, y: yPosition + 60), withAttributes: summaryAttributes)
            
            yPosition += 120
            
            // Table Header
            let headerFont = UIFont.boldSystemFont(ofSize: 12)
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.white
            ]
            
            let headerRect = CGRect(x: 60, y: yPosition, width: pageWidth - 120, height: 30)
            UIColor.systemCyan.setFill()
            UIBezierPath(rect: headerRect).fill()
            
            "Date & Time".draw(at: CGPoint(x: 70, y: yPosition + 8), withAttributes: headerAttributes)
            "Type".draw(at: CGPoint(x: 250, y: yPosition + 8), withAttributes: headerAttributes)
            "Customers".draw(at: CGPoint(x: 400, y: yPosition + 8), withAttributes: headerAttributes)
            
            yPosition += 30
            
            // Table Rows
            let rowFont = UIFont.systemFont(ofSize: 11)
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: rowFont,
                .foregroundColor: UIColor.black
            ]
            
            for (index, entry) in session.entries.enumerated() {
                // Check if we need a new page
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = 60
                    
                    // Redraw header on new page
                    let newHeaderRect = CGRect(x: 60, y: yPosition, width: pageWidth - 120, height: 30)
                    UIColor.systemCyan.setFill()
                    UIBezierPath(rect: newHeaderRect).fill()
                    
                    "Date & Time".draw(at: CGPoint(x: 70, y: yPosition + 8), withAttributes: headerAttributes)
                    "Type".draw(at: CGPoint(x: 250, y: yPosition + 8), withAttributes: headerAttributes)
                    "Customers".draw(at: CGPoint(x: 400, y: yPosition + 8), withAttributes: headerAttributes)
                    
                    yPosition += 30
                }
                
                // Row background (alternating) - soft gray for light mode
                if index % 2 == 0 {
                    let rowBgRect = CGRect(x: 60, y: yPosition, width: pageWidth - 120, height: 25)
                    UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0).setFill() // Soft gray
                    UIBezierPath(rect: rowBgRect).fill()
                }
                
                entry.formattedDateTime.draw(at: CGPoint(x: 70, y: yPosition + 5), withAttributes: rowAttributes)
                entry.entryType.rawValue.draw(at: CGPoint(x: 250, y: yPosition + 5), withAttributes: rowAttributes)
                "\(entry.customerCount)".draw(at: CGPoint(x: 400, y: yPosition + 5), withAttributes: rowAttributes)
                
                yPosition += 25
            }
            
            // Footer
            yPosition = pageHeight - 60
            let footerFont = UIFont.systemFont(ofSize: 10)
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.lightGray
            ]
            
            let footerText = "Generated by Green Motion Shuttle System - \(Date().formatted())"
            let footerSize = footerText.size(withAttributes: footerAttributes)
            let footerRect = CGRect(x: (pageWidth - footerSize.width) / 2, y: yPosition, width: footerSize.width, height: footerSize.height)
            footerText.draw(in: footerRect, withAttributes: footerAttributes)
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
}
