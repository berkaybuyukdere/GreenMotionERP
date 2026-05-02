import UIKit
import PDFKit

class ServisExportManager {
    static let shared = ServisExportManager()
    
    private init() {}
    
    // CSV Export
    func exportToCSV(servisler: [Servis], viewController: UIViewController?) {
        var csvString = "\u{FEFF}Plate,Service company,Status,Sent at,Completed at,Reasons (labels),Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        for servis in servisler {
            let teslimStr = servis.teslimTarihi != nil ? dateFormatter.string(from: servis.teslimTarihi!) : "-"
            let aciklamaTemiz = servis.aciklama.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
            let nedenler = servis.servisNedenleri.map { $0.displayTitle }.joined(separator: "; ")
            
            csvString += "\(servis.aracPlaka),\(servis.servisFirmaAdi),\(servis.durum.displayTitle),\(dateFormatter.string(from: servis.gonderilmeTarihi)),\(teslimStr),\"\(nedenler)\",\"\(aciklamaTemiz)\"\n"
        }
        
        let fileName = "servis_kayitlari_\(Date().timeIntervalSince1970).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
            shareFile(at: path, viewController: viewController)
        } catch {
            print("CSV oluşturma hatası: \(error)")
        }
    }
    
    // XLSX Export
    func exportToXLSX(servisler: [Servis], viewController: UIViewController?) {
        var csvString = "\u{FEFF}Plate\tService company\tStatus\tSent at\tCompleted at\tReasons\tNotes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        for servis in servisler {
            let teslimStr = servis.teslimTarihi != nil ? dateFormatter.string(from: servis.teslimTarihi!) : "-"
            let aciklamaTemiz = servis.aciklama.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let nedenler = servis.servisNedenleri.map { $0.displayTitle }.joined(separator: "; ")
            
            csvString += "\(servis.aracPlaka)\t\(servis.servisFirmaAdi)\t\(servis.durum.displayTitle)\t\(dateFormatter.string(from: servis.gonderilmeTarihi))\t\(teslimStr)\t\(nedenler)\t\(aciklamaTemiz)\n"
        }
        
        let fileName = "servis_kayitlari_\(Date().timeIntervalSince1970).xlsx"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: path, atomically: true, encoding: .utf8)
            shareFile(at: path, viewController: viewController)
        } catch {
            print("XLSX oluşturma hatası: \(error)")
        }
    }
    
    // PDF Export
    func exportToPDF(servisler: [Servis], viewController: UIViewController?) {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = 50
            let leftMargin: CGFloat = 30
            let rightMargin: CGFloat = 30
            let pageWidth = pageSize.width - leftMargin - rightMargin
            
            // Başlık
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "Servis Kayıtları Raporu"
            title.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            // Tarih
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let currentDate = "Rapor Tarihi: \(dateFormatter.string(from: Date()))"
            currentDate.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 30
            
            // İstatistikler
            let statsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.darkGray
            ]
            let aktifServis = servisler.filter { $0.durum == .serviste }.count
            let tamamlanan = servisler.filter { $0.durum == .tamamlandi }.count
            let iptal = servisler.filter { $0.durum == .iptal }.count
            let stats = "Total: \(servisler.count) | In service: \(aktifServis) | Completed: \(tamamlanan) | Cancelled: \(iptal)"
            stats.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: statsAttributes)
            yPosition += 40
            
            // Tablo başlıkları
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.white
            ]
            
            let headerRect = CGRect(x: leftMargin, y: yPosition, width: pageWidth, height: 25)
            context.cgContext.setFillColor(UIColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1.0).cgColor)
            context.cgContext.fill(headerRect)
            
            "Plate".draw(at: CGPoint(x: leftMargin + 5, y: yPosition + 7), withAttributes: headerAttributes)
            "Company".draw(at: CGPoint(x: leftMargin + 80, y: yPosition + 7), withAttributes: headerAttributes)
            "Status".draw(at: CGPoint(x: leftMargin + 200, y: yPosition + 7), withAttributes: headerAttributes)
            "Sent".draw(at: CGPoint(x: leftMargin + 280, y: yPosition + 7), withAttributes: headerAttributes)
            "Reasons".draw(at: CGPoint(x: leftMargin + 370, y: yPosition + 7), withAttributes: headerAttributes)
            yPosition += 30
            
            // Servisler
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.black
            ]
            
            for (index, servis) in servisler.enumerated() {
                if yPosition > pageSize.height - 50 {
                    context.beginPage()
                    yPosition = 50
                }
                
                // Zebra striping
                if index % 2 == 0 {
                    let rowRect = CGRect(x: leftMargin, y: yPosition - 5, width: pageWidth, height: 20)
                    context.cgContext.setFillColor(UIColor(white: 0.95, alpha: 1.0).cgColor)
                    context.cgContext.fill(rowRect)
                }
                
                servis.aracPlaka.draw(at: CGPoint(x: leftMargin + 5, y: yPosition), withAttributes: rowAttributes)
                
                let firmaKisaltilmis = String(servis.servisFirmaAdi.prefix(15))
                firmaKisaltilmis.draw(at: CGPoint(x: leftMargin + 80, y: yPosition), withAttributes: rowAttributes)
                
                servis.durum.displayTitle.draw(at: CGPoint(x: leftMargin + 200, y: yPosition), withAttributes: rowAttributes)
                
                dateFormatter.string(from: servis.gonderilmeTarihi).draw(at: CGPoint(x: leftMargin + 280, y: yPosition), withAttributes: rowAttributes)
                
                String(servis.servisNedenleri.map(\.displayTitle).joined(separator: ", ").prefix(42)).draw(at: CGPoint(x: leftMargin + 370, y: yPosition), withAttributes: rowAttributes)
                
                yPosition += 22
            }
            
            // Footer
            yPosition = pageSize.height - 30
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.gray
            ]
            "\(UserDefaults.standard.selectedCountry.name)".draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: footerAttributes)
        }
        
        let fileName = "servis_raporu_\(Date().timeIntervalSince1970).pdf"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: path)
            shareFile(at: path, viewController: viewController)
        } catch {
            print("PDF oluşturma hatası: \(error)")
        }
    }
    
    private func shareFile(at url: URL, viewController: UIViewController?) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        let presenter = viewController ?? Self.bestPresenterViewController()

        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = presenter?.view
            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        presenter?.present(activityVC, animated: true)
    }

    /// Resolves the frontmost VC so share sheets work from nested SwiftUI flows (e.g. Reports full-screen cover).
    private static func topMostViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topMostViewController(from: presented)
        }
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController {
            return topMostViewController(from: visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topMostViewController(from: selected)
        }
        return root
    }

    static func bestPresenterViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let windowScene = scene else { return nil }
        let root = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windowScene.windows.first?.rootViewController
        guard let root else { return nil }
        return topMostViewController(from: root)
    }
}
