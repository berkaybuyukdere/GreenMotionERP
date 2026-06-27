import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    // Hafif feedback - UI interactions
    func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // Orta feedback - Buton tıklamaları
    func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // Güçlü feedback - Önemli işlemler
    func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    // Başarı feedback - Kaydetme, güncelleme
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    // Hata feedback
    func error() {
        let impact = UIImpactFeedbackGenerator(style: .rigid)
        let notification = UINotificationFeedbackGenerator()
        impact.impactOccurred(intensity: 0.95)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            impact.impactOccurred(intensity: 0.65)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            notification.notificationOccurred(.error)
        }
    }
    
    // Uyarı feedback
    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    // Selection feedback - Liste kaydırma, seçim
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    // Scan başarılı - Özel combo
    func scanSuccess() {
        light()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.success()
        }
    }
    
    // PDF oluşturma başarılı - Özel combo
    func pdfGenerated() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.success()
        }
    }
}
