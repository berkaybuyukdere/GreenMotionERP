---
name: Uygulama Analizi ve Yeni Özellik Önerileri
overview: Arac Hasar Kayit (Green Motion) uygulamasının mevcut yapısı analiz edildi; teknoloji, yenilik, çeşitlilik ve süreç iyileştirmeleri için başlık başlık öneriler derlendi.
todos: []
isProject: false
---

# Arac Hasar Kayit - Uygulama Analizi ve Yeni Özellik Önerileri

## Mevcut Uygulama Özeti

Uygulama: Araç hasar takibi, filo yönetimi, ofis operasyonları, shuttle, iade/çıkış işlemleri, servis kayıtları ve raporlama içeren SwiftUI + Firebase tabanlı bir iOS uygulaması.

**Mevcut teknoloji:** SwiftUI, Firebase (Auth, Firestore, Storage, Cloud Functions), Vision (plaka OCR), Charts, FCM push, multi-tenant demo ortamı.

**Mevcut özellikler:** Dashboard, Araç listesi, QR/Plaka tarayıcı, Analytics sekmesi, Raporlar (hasar, check-out, iade, ofis operasyonları, shuttle, servis, tatil, asistan), Admin paneli, görsel önbellekleme, offline mod, pagination, cascade delete, audit trail, arama/filtre, toplu işlemler, PDF üretimi, Lottie/Toast/Tutorial.

---

## 1. Teknoloji ve Yenilik Özellikleri

### 1.1 Yapay Zeka / Makine Öğrenimi

- **Hasar fotoğrafı analizi (Core ML / Vision):** Hasar şiddeti tahmini (hafif/orta/ağır) veya hasar tipi sınıflandırması (çizik, çökme, cam) ile otomatik etiket önerisi.
- **Hasar maliyet tahmini:** Fotoğraf + araç kategorisi ile tahmini onarım maliyeti (ML modeli veya kural tabanlı).
- **Plaka tanıma iyileştirmesi:** Mevcut [PlakaScannerView](AracHasarKayit/Views/PlakaScannerView.swift) Vision kullanıyor; özel plaka formatları (İsviçre vb.) için model fine-tuning veya daha iyi post-processing.
- **Sesli not (Speech-to-Text):** Hasar eklerken sesli açıklama kaydı; AVFoundation + Speech framework veya harici API.

### 1.2 Apple Ekosistemi Entegrasyonları

- **Widget (WidgetKit):** Ana ekranda “Bugünkü hasar sayısı”, “Aktif servis sayısı” veya “Shuttle müşteri sayısı” widget’ları.
- **Siri Shortcuts / App Intents:** “Bugünkü hasar raporunu aç”, “Araç X’i göster” gibi sesli/manuel kısayollar.
- **Apple Watch uygulaması:** Shuttle için müşteri sayısı girişi veya basit dashboard (okuma).
- **App Clip:** Sadece plaka tarama + araç detay görüntüleme; müşteri deneyimi için hafif giriş noktası.

### 1.3 Gelişmiş Kamera ve Görüntü

- **AR ile hasar konumu:** ARKit ile aracın üzerinde hasar bölgesini işaretleme (opsiyonel).
- **Belge tarama (VNDocumentCameraViewController):** Ruhsat/sözleşme tarama ve Firestore’a PDF kaydetme (mevcut PDF/upload altyapısı ile).
- **Fotoğraf kalite kontrolü:** Çekim sonrası bulanıklık/parlaklık kontrolü; yeniden çekim önerisi.

### 1.4 Offline ve Senkronizasyon

- **Arka planda senkronizasyon:** [BackgroundSyncManager](AracHasarKayit/Utilities/BackgroundSyncManager.swift) ile BGAppRefreshTask; offline’da yapılan değişikliklerin periyodik sync’i.
- **Çakışma çözümü:** Aynı dokümana offline + online değişiklik gelirse “son yazan kazanır” veya kullanıcıya seçim ekranı.
- **Offline kuyruk göstergesi:** Bekleyen yazma sayısı ve “Sync tamamlandı” bildirimi.

---

## 2. Kullanıcı Deneyimi ve Arayüz

### 2.1 Erişilebilirlik ve Çoklu Dil

- **VoiceOver / Dynamic Type:** Kritik ekranlarda etiket ve sıra kontrolü; [AccessibilityHelpers](AracHasarKayit/Utilities/AccessibilityHelpers.swift) ile tutarlı kullanım.
- **Tam lokalizasyon:** [LocalizationManager](AracHasarKayit/Utilities/LocalizationManager.swift) hazır; TR/DE/FR/EN string’lerin tamamının `.localized` ile doldurulması.
- **RTL desteği:** Arapça vb. için layout desteği (ileri seviye).

### 2.2 Onboarding ve Eğitim

- **Kişiselleştirilmiş onboarding:** Rol (admin/sürücü/ofis) seçimine göre farklı tanıtım akışı.
- **Kontekst bilgisi (tooltip):** Raporlar ve dashboard kartlarında “Bu ne?” açıklamaları.
- **Video kısa rehberler:** Kritik akışlar için gömülü veya link ile video.

### 2.3 Görsel ve Etkileşim

- **Skeleton loading:** Liste ve detay ekranlarında [SkeletonView](AracHasarKayit/Utilities/SkeletonView.swift) kullanımının yaygınlaştırılması.
- **Pull-to-refresh tutarlılığı:** Tüm liste ekranlarında aynı davranış.
- **Haptic tutarlılığı:** Başarı/hata/uyarı için [HapticManager] kullanımının tüm aksiyonlarda standart hale getirilmesi.

---

## 3. Raporlama ve İş Zekası

### 3.1 Yeni Raporlar ve Metrikler

- **Aylık/haftalık özet e-postası:** Cloud Functions ile zamanlanmış (cron) rapor; e-posta veya PDF ekı.
- **Hasar çözüm süresi:** “Ortalama hasar kapanış süresi (gün)” metrikleri; [AnalyticsDashboardView](AracHasarKayit/Views/AnalyticsDashboardView.swift) ve ViewModel’e ek alan.
- **Kategori bazlı hasar dağılımı:** Hangi araç kategorisinde daha çok hasar var; mevcut Charts ile grafik.
- **Shuttle sürücü performansı:** Sürücü başına günlük/haftalık müşteri sayısı ve karşılaştırma.

### 3.2 Dışa Aktarma ve Entegrasyon

- **Excel/CSV export:** Araç listesi, hasar listesi, shuttle özeti için [BulkOperationsManager](AracHasarKayit/Utilities/BulkOperationsManager.swift) veya ayrı export modülü.
- **PDF birleştirme:** Birden fazla hasar raporunu tek PDF’de toplama.
- **Takvim entegrasyonu:** Servis tarihleri veya shuttle günleri için Calendar export (EventKit).

---

## 4. Süreç İyileştirmeleri

### 4.1 Veri ve İş Kuralları

- **Zorunlu alan ve validasyon:** Hasar/araç eklerken [DataValidation](AracHasarKayit/Utilities/DataValidation.swift) ile sunucu tarafı kuralları Firestore Rules’da da yansıtmak; eksik alanlarda yazmayı reddetmek.
- **Duplicate plaka uyarısı:** Aynı plaka ile yeni araç eklenirken uyarı ve “mevcut araça git” seçeneği.
- **Tarih mantığı:** Hasar “teslim tarihi”nin “hasar tarihi”nden önce olamayacağı kontrolü (client + opsiyonel Rules).

### 4.2 Güvenlik ve Erişim

- **Rol tabanlı erişim (RBAC):** [UserProfile](AracHasarKayit/Firebase/AuthenticationManager.swift) veya Firestore’da `role` (admin, manager, driver, viewer); kurallarda `get(/databases/.../users/$(request.auth.uid)).data.role` ile okuma/yazma/silme kısıtı.
- **Kritik işlem onayı:** Toplu silme veya tüm veriyi dışa aktarma için ek şifre/onay adımı.
- **Oturum süresi ve çıkış:** Uzun süre hareketsizlikte uyarı veya otomatik çıkış (opsiyonel).

### 4.3 Performans ve Stabilite

- **Firestore sorgu indeksleri:** Karmaşık sorgular için `firestore.indexes.json` ve dokümantasyon; derleme hatası yerine “index gerekli” hatalarını azaltmak.
- **Listener birleştirme:** Aynı collection’a birden fazla listener varsa tek listener + paylaşılan state (ör. [OptimizedRealtimeManager](AracHasarKayit/Utilities/OptimizedRealtimeManager.swift) ile tutarlı kullanım).
- **Büyük listelerde virtualizasyon:** 1000+ araçta LazyVStack/LazyHStack ve sayfalı yükleme; gereksiz view oluşturmayı azaltmak.

### 4.4 Bakım ve Operasyon

- **Merkezi hata raporlama:** Firebase Crashlytics + özel log; kritik ekranlarda “Hata oluştu” durumunda otomatik rapor ve kullanıcıya kısa mesaj.
- **Feature flag:** Firebase Remote Config ile yeni özellikleri belirli kullanıcı gruplarına açma/kapama.
- **Audit log sorgulama:** [AuditTrailManager](AracHasarKayit/Utilities/AuditTrailManager.swift) verileri için Admin panelinde “Son değişiklikler” filtresi ve export.

### 4.5 Geliştirme Süreci

- **Unit test:** ViewModel ve validation/business logic için testler; özellikle AracViewModel, DataValidation, plaka/email validasyonu.
- **UI test:** Kritik akışlar (giriş, araç ekleme, hasar ekleme, rapor açma) için XCUITest.
- **CI/CD:** GitHub Actions veya Xcode Cloud ile test + TestFlight build; Firebase kurallarının test ortamında doğrulanması.

---

## 5. Entegrasyonlar

### 5.1 Harici Servisler

- **İsviçre araç kayıt API’si (varsa):** Plaka ile araç bilgisi doğrulama veya otomatik doldurma.
- **Sigorta/onarım firması API’si:** Hasar bildirimi veya durum sorgulama (iş gereksinimine göre).
- **Harita:** Araç teslim/tesellüm noktaları veya shuttle rotası için MapKit/Google Maps entegrasyonu.

### 5.2 Firebase Genişletmeleri

- **Firestore genişleme:** Yeni collection’lar için [firestore.rules](AracHasarKayit/Notes/firestore.rules) ve [FirebaseService](AracHasarKayit/Firebase/FirebaseService.swift) dokümantasyonu; demo ortamı kurallarının production ile aynı yapıda tutulması.
- **Ek Cloud Functions:** Zamanlanmış raporlar, toplu bildirimler, veri arşivleme (eski aktiviteleri soğuk depolama).

---

## Önceliklendirme Özeti

| Kategori | Örnek öğe | Öncelik (öneri) |
|----------|------------|------------------|
| Teknoloji / AI | Hasar foto analizi, Widget, Siri Shortcuts | Yüksek (fark yaratır) |
| UX | Skeleton, tam lokalizasyon, tooltip | Orta |
| Raporlama | Zamanlanmış e-posta, Excel export, çözüm süresi | Orta–Yüksek |
| Süreç | RBAC, duplicate plaka, validasyon kuralları | Yüksek (güvenlik/veri kalitesi) |
| Geliştirme | Unit/UI test, CI/CD, Crashlytics | Orta (uzun vadede hız kazandırır) |

Bu plan, uygulamanın mevcut yapısına ve [Notes](AracHasarKayit/Notes/) içindeki analiz dokümanlarına dayanmaktadır. Belirli bir başlığı (ör. sadece “Teknoloji” veya “Süreç”) uygulama adımına çevirmek isterseniz, o bölüm için ayrıntılı uygulama planı çıkarılabilir.