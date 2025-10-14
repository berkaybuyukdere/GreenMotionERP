import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Bildirim izni verildi")
            } else if let error = error {
                print("Bildirim izni hatası: \(error.localizedDescription)")
            }
        }
    }
    
    func sendNotification(baslik: String, mesaj: String) {
        let content = UNMutableNotificationContent()
        content.title = baslik
        content.body = mesaj
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Bildirim gönderme hatası: \(error.localizedDescription)")
            }
        }
    }
    
    // Özel bildirim fonksiyonları
    func aracEklendi(plaka: String) {
        sendNotification(baslik: "Araç Eklendi", mesaj: "\(plaka) plakalı araç sisteme eklendi")
    }
    
    func aracSilindi(plaka: String) {
        sendNotification(baslik: "Araç Silindi", mesaj: "\(plaka) plakalı araç sistemden silindi")
    }
    
    func aracGuncellendi(plaka: String) {
        sendNotification(baslik: "Araç Güncellendi", mesaj: "\(plaka) plakalı araç bilgileri güncellendi")
    }
    
    func hasarEklendi(plaka: String, hasarTuru: String) {
        sendNotification(baslik: "Hasar Kaydı Eklendi", mesaj: "\(plaka) - \(hasarTuru) hasar kaydı eklendi")
    }
    
    func servisEklendi(plaka: String, servisFirma: String) {
        sendNotification(baslik: "Servise Gönderildi", mesaj: "\(plaka) plakalı araç \(servisFirma) servisine gönderildi")
    }
    
    func servisTamamlandi(plaka: String) {
        sendNotification(baslik: "Servis Tamamlandı", mesaj: "\(plaka) plakalı aracın servisi tamamlandı")
    }
    
    func qrKoduTarandi(plaka: String) {
        sendNotification(baslik: "QR Kod Tarandı", mesaj: "\(plaka) plakalı araç QR kodu tarandı")
    }
    
    func plakaTarandi(plaka: String) {
        sendNotification(baslik: "Plaka Tarandı", mesaj: "\(plaka) plakalı araç tarandı")
    }
}
