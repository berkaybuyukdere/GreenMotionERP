import UIKit
import PDFKit

class IadeRaporManager {
    static let shared = IadeRaporManager()
    
    private init() {}
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func exportToPDF(iadeler: [IadeIslemi], viewController: UIViewController?) {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = 50
            let leftMargin: CGFloat = 30
            let rightMargin: CGFloat = 30
            let pageWidth = pageSize.width - leftMargin - rightMargin
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Return Process Report"
            title.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let currentDate = "Report Date: \(dateFormatter.string(from: Date()))"
            currentDate.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 30
            
            let statsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.darkGray
            ]
            let toplamFoto = iadeler.flatMap { $0.fotograflar }.count
            let stats = "Total Returns: \(iadeler.count) | Total Photos: \(toplamFoto)"
            stats.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: statsAttributes)
            yPosition += 40
            
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.white
            ]
            
            let headerRect = CGRect(x: leftMargin, y: yPosition, width: pageWidth, height: 25)
            context.cgContext.setFillColor(UIColor.purple.cgColor)
            context.cgContext.fill(headerRect)
            
            "Plate".draw(at: CGPoint(x: leftMargin + 5, y: yPosition + 7), withAttributes: headerAttributes)
            "Return Date".draw(at: CGPoint(x: leftMargin + 120, y: yPosition + 7), withAttributes: headerAttributes)
            "Photos".draw(at: CGPoint(x: leftMargin + 320, y: yPosition + 7), withAttributes: headerAttributes)
            "Notes".draw(at: CGPoint(x: leftMargin + 400, y: yPosition + 7), withAttributes: headerAttributes)
            yPosition += 30
            
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.black
            ]
            
            for (index, iade) in iadeler.enumerated() {
                if yPosition > pageSize.height - 50 {
                    context.beginPage()
                    yPosition = 50
                }
                
                if index % 2 == 0 {
                    let rowRect = CGRect(x: leftMargin, y: yPosition - 5, width: pageWidth, height: 20)
                    context.cgContext.setFillColor(UIColor(white: 0.95, alpha: 1.0).cgColor)
                    context.cgContext.fill(rowRect)
                }
                
                iade.aracPlaka.draw(at: CGPoint(x: leftMargin + 5, y: yPosition), withAttributes: rowAttributes)
                dateFormatter.string(from: iade.iadeTarihi).draw(at: CGPoint(x: leftMargin + 120, y: yPosition), withAttributes: rowAttributes)
                "\(iade.fotograflar.count)".draw(at: CGPoint(x: leftMargin + 335, y: yPosition), withAttributes: rowAttributes)
                
                let notlarKisaltilmis = String(iade.notlar.prefix(20))
                notlarKisaltilmis.draw(at: CGPoint(x: leftMargin + 400, y: yPosition), withAttributes: rowAttributes)
                
                yPosition += 22
            }
        }
        
        let filename = "return_report_\(Date().timeIntervalSince1970).pdf"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            print("✅ İade PDF kaydedildi: \(fileURL.path)")
            shareFile(at: fileURL, viewController: viewController)
        } catch {
            print("❌ PDF oluşturma hatası: \(error)")
        }
    }
    
    func exportToXLSX(iadeler: [IadeIslemi], viewController: UIViewController?) {
        var csvString = "Plate\tReturn Date\tPhotos\tNotes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        for iade in iadeler {
            let notlarTemiz = iade.notlar.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            
            csvString += "\(iade.aracPlaka)\t\(dateFormatter.string(from: iade.iadeTarihi))\t\(iade.fotograflar.count)\t\(notlarTemiz)\n"
        }
        
        let filename = "return_report_\(Date().timeIntervalSince1970).xlsx"
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Excel kaydedildi: \(fileURL.path)")
            shareFile(at: fileURL, viewController: viewController)
        } catch {
            print("❌ XLSX oluşturma hatası: \(error)")
        }
    }
    
    private func shareFile(at url: URL, viewController: UIViewController?) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = viewController?.view
            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        viewController?.present(activityVC, animated: true)
    }
}
