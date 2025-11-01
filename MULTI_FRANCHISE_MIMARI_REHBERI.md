# 🏢 Multi-Franchise (Çoklu Şube) Mimari Rehberi

**Amaç:** 50 franchise'ın her birinin kendi verilerini, kendi kullanıcılarını görmesi, tek bir uygulamadan yönetilebilmesi

---

## 📊 MİMARİ SEÇENEKLERİ

### **SEÇENEK 1: Her Franchise için Ayrı Firebase Projesi** 🔴

#### Nasıl Çalışır:
```
- Franchise 1 → Firebase Projesi: "greenmotion-franchise-001"
- Franchise 2 → Firebase Projesi: "greenmotion-franchise-002"
- ...
- Franchise 50 → Firebase Projesi: "greenmotion-franchise-050"
```

#### Artıları:
- ✅ **Tam İzolasyon:** Veriler tamamen ayrı
- ✅ **Güvenlik:** Bir franchise diğerinin verilerine hiç erişemez
- ✅ **Bağımsızlık:** Bir franchise'ın problemi diğerlerini etkilemez
- ✅ **Ölçekleme:** Her franchise kendi limitlerini kullanır
- ✅ **Yedekleme:** Franchise bazlı yedekleme kolay

#### Eksileri:
- ❌ **Maliyet:** Her proje için ayrı billing
- ❌ **Yönetim:** 50 ayrı Firebase projesi yönetmek zor
- ❌ **App Store:** Her franchise için ayrı app yapman gerekir
- ❌ **Kod:** Dinamik Firebase config yapman gerekir
- ❌ **Güncelleme:** Her franchise için ayrı config güncelleme

#### Uygulama:
```swift
// Her franchise için farklı GoogleService-Info.plist
// App açılışında franchise seçimi yapılır
// Seçilen franchise'a göre Firebase initialize edilir
```

---

### **SEÇENEK 2: Tek Firebase Projesi + Franchise ID ile Partition** ✅ **ÖNERİLEN**

#### Nasıl Çalışır:
```
Firebase Projesi: "greenmotion-main"
├── franchises/
│   ├── franchise_001/
│   │   ├── name: "Zurich Airport"
│   │   ├── location: "Zurich, Switzerland"
│   │   └── config: {...}
│   ├── franchise_002/
│   │   └── ...
│
├── users/
│   ├── user123/
│   │   ├── franchiseId: "franchise_001"  ← FRANCHISE BAĞLANTISI
│   │   └── ...
│
├── araclar/  (TÜM FRANCHISELAR)
│   ├── arac_abc/
│   │   ├── franchiseId: "franchise_001"  ← FRANCHISE BAĞLANTISI
│   │   └── ...
│
├── hasarKayitlari/  (TÜM FRANCHISELAR)
│   └── hasar_xyz/
│       ├── franchiseId: "franchise_001"
│       └── ...
```

#### Artıları:
- ✅ **Tek App:** Tek uygulama, tüm franchise'lar için
- ✅ **Tek Firebase Projesi:** Tek billing, kolay yönetim
- ✅ **Güvenlik:** Firestore Rules ile franchise bazlı izolasyon
- ✅ **Merkezi Yönetim:** Tüm franchise'ları görebilirsin (super admin)
- ✅ **Kolay Migrasyon:** Mevcut verileri franchiseId ekleyerek migrate edebilirsin
- ✅ **Maliyet:** Daha ekonomik

#### Eksileri:
- ⚠️ **Firestore Rules:** Karmaşık security rules yazman gerekir
- ⚠️ **Query Performance:** Index'ler franchiseId içermeli
- ⚠️ **Yedekleme:** Franchise bazlı yedekleme için query yapman gerekir

#### Veri Yapısı:
```javascript
// Her document'a franchiseId eklenir
{
  "araclar": {
    "arac_123": {
      "id": "arac_123",
      "franchiseId": "franchise_001",  // ← YENİ ALAN
      "plaka": "ZH123456",
      "marka": "BMW",
      ...
    }
  },
  
  "users": {
    "user_456": {
      "uid": "user_456",
      "franchiseId": "franchise_001",  // ← YENİ ALAN
      "email": "john@greenmotion.ch",
      ...
    }
  }
}
```

---

### **SEÇENEK 3: Collection Prefix ile Partition** 🟡

#### Nasıl Çalışır:
```
araclar_franchise_001/
araclar_franchise_002/
users_franchise_001/
users_franchise_002/
```

#### Artıları:
- ✅ **Tam İzolasyon:** Collection seviyesinde ayrım
- ✅ **Basit Rules:** Her collection için ayrı rule yazabilirsin

#### Eksileri:
- ❌ **Dinamik Query:** Collection ismini dinamik oluşturman gerekir
- ❌ **Kod Karmaşıklığı:** Her query'de franchise ID eklemek
- ❌ **Ölçeklenebilirlik:** 50 franchise = 50x collection sayısı

---

### **SEÇENEK 4: Subcollections ile Partition** 🟢

#### Nasıl Çalışır:
```
franchises/
  └── franchise_001/
      ├── araclar/
      │   └── arac_123/
      ├── users/
      │   └── user_456/
      ├── hasarKayitlari/
      └── ...
```

#### Artıları:
- ✅ **Organize:** Mantıklı yapı
- ✅ **İzolasyon:** Franchise bazlı tam ayrım
- ✅ **Rules:** Basit security rules

#### Eksileri:
- ❌ **Query Limit:** Firestore subcollection query limitleri
- ❌ **Cross-Collection:** Franchise'lar arası query zor
- ❌ **Migrasyon:** Mevcut verileri tamamen yeniden yapılandır

---

## 🎯 ÖNERİLEN ÇÖZÜM: SEÇENEK 2 (Tek Proje + Franchise ID)

### Neden Bu Seçenek?

1. **Mevcut Koda Minimal Değişiklik**
2. **Tek App Store Uygulaması**
3. **Kolay Migrasyon**
4. **Merkezi Yönetim İmkanı**
5. **Ölçeklenebilir**

---

## 🛠️ UYGULAMA ADIMLARI

### **ADIM 1: Franchise Model Oluştur**

```swift
// Models/Franchise.swift
import Foundation

struct Franchise: Identifiable, Codable {
    var id: String  // franchise_001, franchise_002, etc.
    var name: String
    var location: String
    var address: String?
    var phone: String?
    var email: String?
    var createdAt: Date
    var isActive: Bool
    var config: FranchiseConfig?
    
    struct FranchiseConfig: Codable {
        var allowedFeatures: [String]
        var maxVehicles: Int?
        var customSettings: [String: Any]?
    }
}
```

---

### **ADIM 2: UserProfile'a Franchise ID Ekle**

```swift
// Firebase/AuthenticationManager.swift
struct UserProfile: Codable {
    var uid: String
    var email: String
    var firstName: String
    var lastName: String
    var createdAt: Date
    var franchiseId: String?  // ← YENİ ALAN
    var role: UserRole  // ← YENİ ALAN (Admin, Agent, Driver, vb.)
    
    enum UserRole: String, Codable {
        case admin = "Admin"
        case frontOfficeAgent = "Front Office Agent"
        case driver = "Driver"
        case fleetAgent = "Fleet Agent"
        case superAdmin = "Super Admin"  // Tüm franchise'ları görebilir
    }
}
```

---

### **ADIM 3: Arac Model'ine Franchise ID Ekle**

```swift
// Models/Arac.swift
struct Arac: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var franchiseId: String  // ← YENİ ALAN (ZORUNLU)
    var plaka: String
    var marka: String
    var model: String
    var kategori: String
    var vignetteVar: Bool
    var kayitTarihi: Date
    var hasarKayitlari: [HasarKaydi]
    var qrCode: String
    var spareKeyCount: Int
    var headDocumentURL: String?
    
    // ... mevcut kod ...
}
```

---

### **ADIM 4: Franchise Manager Oluştur**

```swift
// Utilities/FranchiseManager.swift
import Foundation
import FirebaseFirestore
import FirebaseAuth

class FranchiseManager: ObservableObject {
    static let shared = FranchiseManager()
    
    @Published var currentFranchise: Franchise?
    @Published var availableFranchises: [Franchise] = []
    
    private let db = Firestore.firestore()
    
    // Mevcut kullanıcının franchise'ını yükle
    func loadUserFranchise(completion: @escaping (Franchise?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }
        
        // Kullanıcının franchise ID'sini al
        db.collection("users").document(user.uid).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let franchiseId = data["franchiseId"] as? String else {
                completion(nil)
                return
            }
            
            // Franchise bilgilerini yükle
            self.loadFranchise(id: franchiseId, completion: completion)
        }
    }
    
    // Franchise bilgilerini yükle
    func loadFranchise(id: String, completion: @escaping (Franchise?) -> Void) {
        db.collection("franchises").document(id).getDocument { snapshot, error in
            guard let snapshot = snapshot,
                  let franchise = try? snapshot.data(as: Franchise.self) else {
                completion(nil)
                return
            }
            
            DispatchQueue.main.async {
                self.currentFranchise = franchise
                completion(franchise)
            }
        }
    }
    
    // Super admin için tüm franchise'ları yükle
    func loadAllFranchises(completion: @escaping ([Franchise]) -> Void) {
        db.collection("franchises")
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let franchises = documents.compactMap { try? $0.data(as: Franchise.self) }
                DispatchQueue.main.async {
                    self.availableFranchises = franchises
                    completion(franchises)
                }
            }
    }
}
```

---

### **ADIM 5: FirebaseService'i Güncelle**

```swift
// Firebase/FirebaseService.swift

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private var currentFranchiseId: String? {
        return FranchiseManager.shared.currentFranchise?.id
    }
    
    // Araç yükleme - SADECE mevcut franchise'ın araçlarını getir
    func loadAraclar(completion: @escaping ([Arac]?, Error?) -> Void) {
        guard let franchiseId = currentFranchiseId else {
            completion(nil, NSError(domain: "FranchiseError", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "Franchise ID bulunamadı"]))
            return
        }
        
        db.collection("araclar")
            .whereField("franchiseId", isEqualTo: franchiseId)  // ← FRANCHISE FİLTRESİ
            .getDocuments { querySnapshot, error in
                // ... mevcut kod ...
            }
    }
    
    // Araç kaydetme - Franchise ID otomatik ekle
    func saveArac(_ arac: Arac, completion: @escaping (Error?) -> Void) {
        guard var updatedArac = arac as? Arac else {
            // Eğer franchiseId yoksa, mevcut franchise ID'sini ekle
            var newArac = arac
            if newArac.franchiseId.isEmpty,
               let franchiseId = currentFranchiseId {
                newArac.franchiseId = franchiseId
            }
            
            do {
                try db.collection("araclar")
                    .document(newArac.id.uuidString)
                    .setData(from: newArac) { error in
                        completion(error)
                    }
            } catch {
                completion(error)
            }
            return
        }
        
        // Franchise ID yoksa ekle
        if updatedArac.franchiseId.isEmpty,
           let franchiseId = currentFranchiseId {
            updatedArac.franchiseId = franchiseId
        }
        
        do {
            try db.collection("araclar")
                .document(updatedArac.id.uuidString)
                .setData(from: updatedArac) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }
    
    // Tüm servisler için aynı mantık...
}
```

---

### **ADIM 6: Firestore Rules Güncelle**

```javascript
// firestore.rules

rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper: Kullanıcının franchise ID'sini al
    function getUserFranchiseId() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.franchiseId;
    }
    
    // Helper: Super admin mi kontrol et
    function isSuperAdmin() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Super Admin';
    }
    
    // Helper: Document franchise'ı kullanıcının franchise'ı ile eşleşiyor mu?
    function isSameFranchise(franchiseId) {
      return getUserFranchiseId() == franchiseId || isSuperAdmin();
    }
    
    // === FRANCHISES COLLECTION ===
    match /franchises/{franchiseId} {
      // Herkes kendi franchise'ını görebilir, super admin hepsini görebilir
      allow read: if isAuthenticated() && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
      
      // Sadece super admin franchise oluşturabilir/güncelleyebilir
      allow write: if isAuthenticated() && isSuperAdmin();
    }
    
    // === USERS COLLECTION ===
    match /users/{userId} {
      // Kullanıcılar kendi profillerini görebilir
      allow read: if isAuthenticated() && request.auth.uid == userId;
      
      // Aynı franchise'daki kullanıcıları görebilir (super admin hepsini)
      allow read: if isAuthenticated() && 
                     isSameFranchise(get(/databases/$(database)/documents/users/$(userId)).data.franchiseId);
      
      // Kullanıcı kendi profilini güncelleyebilir
      allow update: if isAuthenticated() && request.auth.uid == userId &&
                       request.resource.data.franchiseId == resource.data.franchiseId;  // Franchise ID değiştirilemez
      
      // Super admin kullanıcı oluşturabilir
      allow create: if isAuthenticated() && isSuperAdmin();
    }
    
    // === ARACLAR (VEHICLES) ===
    match /araclar/{aracId} {
      // Sadece aynı franchise'daki araçları görebilir (super admin hepsini)
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      // Aynı franchise'a araç ekleyebilir/güncelleyebilir (super admin hepsini)
      allow write: if isAuthenticated() && 
                     (getUserFranchiseId() == request.resource.data.franchiseId || isSuperAdmin());
      
      // Silme: Sadece aynı franchise'dan
      allow delete: if isAuthenticated() && 
                      isSameFranchise(resource.data.franchiseId);
    }
    
    // === HASAR KAYITLARI ===
    // Araç içinde nested olduğu için aracın franchise kontrolü yeterli
    
    // === SERVIS KAYITLARI ===
    match /servisKayitlari/{servisId} {
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      allow write: if isAuthenticated() && 
                     (getUserFranchiseId() == request.resource.data.franchiseId || isSuperAdmin());
    }
    
    // === ACTIVITIES ===
    match /activities/{activityId} {
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      allow create: if isAuthenticated() && 
                      getUserFranchiseId() == request.resource.data.franchiseId;
    }
    
    // === IADE ISLEMLERI ===
    match /iadeIslemleri/{iadeId} {
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      allow write: if isAuthenticated() && 
                     (getUserFranchiseId() == request.resource.data.franchiseId || isSuperAdmin());
    }
    
    // === OFFICE OPERATIONS ===
    match /office_operations/{operationId} {
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      allow write: if isAuthenticated() && 
                     (getUserFranchiseId() == request.resource.data.franchiseId || isSuperAdmin());
    }
    
    // === PROTOCOLS ===
    match /protocols/{protocolId} {
      allow read: if isAuthenticated() && 
                     isSameFranchise(resource.data.franchiseId);
      
      allow write: if isAuthenticated() && 
                     (getUserFranchiseId() == request.resource.data.franchiseId || isSuperAdmin());
    }
  }
}
```

---

### **ADIM 7: Storage Rules Güncelle**

```javascript
// storage.rules

rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    
    // Helper: Kullanıcının franchise ID'sini al
    function getUserFranchiseId() {
      return firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.franchiseId;
    }
    
    // Helper: Super admin mi?
    function isSuperAdmin() {
      return firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == 'Super Admin';
    }
    
    // Hasar fotoğrafları - franchise bazlı
    match /hasar_fotograflari/{franchiseId}/{allPaths=**} {
      allow read: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
      allow write: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
    }
    
    // Kafa kağıtları - franchise bazlı
    match /kafa_kagitlari/{franchiseId}/{allPaths=**} {
      allow read: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
      allow write: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
    }
    
    // Office operations - franchise bazlı
    match /office_operations/{franchiseId}/{allPaths=**} {
      allow read: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
      allow write: if request.auth != null && 
                     (getUserFranchiseId() == franchiseId || isSuperAdmin());
    }
  }
}
```

---

### **ADIM 8: Migration Script (Mevcut Verileri Güncelle)**

```swift
// Utilities/MigrationManager.swift
import Foundation
import FirebaseFirestore

class MigrationManager {
    static let shared = MigrationManager()
    private let db = Firestore.firestore()
    
    // Mevcut tüm verilere franchise ID ekle
    func migrateToMultiFranchise(defaultFranchiseId: String, completion: @escaping (Bool, String) -> Void) {
        var totalUpdated = 0
        var errors: [String] = []
        let group = DispatchGroup()
        
        // 1. Araçları migrate et
        group.enter()
        migrateAraclar(defaultFranchiseId: defaultFranchiseId) { count, error in
            totalUpdated += count
            if let error = error {
                errors.append("Araçlar: \(error)")
            }
            group.leave()
        }
        
        // 2. Kullanıcıları migrate et
        group.enter()
        migrateUsers(defaultFranchiseId: defaultFranchiseId) { count, error in
            totalUpdated += count
            if let error = error {
                errors.append("Kullanıcılar: \(error)")
            }
            group.leave()
        }
        
        // 3. Servis kayıtlarını migrate et
        group.enter()
        migrateServisKayitlari(defaultFranchiseId: defaultFranchiseId) { count, error in
            totalUpdated += count
            if let error = error {
                errors.append("Servisler: \(error)")
            }
            group.leave()
        }
        
        // 4. İade işlemlerini migrate et
        group.enter()
        migrateIadeIslemleri(defaultFranchiseId: defaultFranchiseId) { count, error in
            totalUpdated += count
            if let error = error {
                errors.append("İadeler: \(error)")
            }
            group.leave()
        }
        
        // 5. Activities migrate et
        group.enter()
        migrateActivities(defaultFranchiseId: defaultFranchiseId) { count, error in
            totalUpdated += count
            if let error = error {
                errors.append("Activities: \(error)")
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            let errorMessage = errors.isEmpty ? "" : errors.joined(separator: "\n")
            completion(errors.isEmpty, "\(totalUpdated) kayıt güncellendi.\n\(errorMessage)")
        }
    }
    
    private func migrateAraclar(defaultFranchiseId: String, completion: @escaping (Int, String?) -> Void) {
        db.collection("araclar").getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else {
                completion(0, error?.localizedDescription)
                return
            }
            
            let batch = self.db.batch()
            var updateCount = 0
            
            for document in documents {
                let data = document.data()
                
                // Eğer franchiseId yoksa ekle
                if data["franchiseId"] == nil {
                    batch.updateData(["franchiseId": defaultFranchiseId], 
                                    forDocument: document.reference)
                    updateCount += 1
                }
            }
            
            if updateCount > 0 {
                batch.commit { error in
                    completion(updateCount, error?.localizedDescription)
                }
            } else {
                completion(0, nil)
            }
        }
    }
    
    // Diğer migrate fonksiyonları benzer şekilde...
    private func migrateUsers(defaultFranchiseId: String, completion: @escaping (Int, String?) -> Void) {
        // Similar implementation...
    }
    
    private func migrateServisKayitlari(defaultFranchiseId: String, completion: @escaping (Int, String?) -> Void) {
        // Similar implementation...
    }
    
    private func migrateIadeIslemleri(defaultFranchiseId: String, completion: @escaping (Int, String?) -> Void) {
        // Similar implementation...
    }
    
    private func migrateActivities(defaultFranchiseId: String, completion: @escaping (Int, String?) -> Void) {
        // Similar implementation...
    }
}
```

---

### **ADIM 9: UI'da Franchise Seçimi (Super Admin için)**

```swift
// Views/FranchiseSelectionView.swift
import SwiftUI

struct FranchiseSelectionView: View {
    @ObservedObject var franchiseManager = FranchiseManager.shared
    @ObservedObject var authManager = AuthenticationManager.shared
    @State private var selectedFranchise: Franchise?
    
    var body: some View {
        NavigationView {
            VStack {
                if authManager.userProfile?.role == .superAdmin {
                    // Super admin tüm franchise'ları görebilir
                    List(franchiseManager.availableFranchises) { franchise in
                        Button(action: {
                            selectedFranchise = franchise
                            franchiseManager.currentFranchise = franchise
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(franchise.name)
                                        .font(.headline)
                                    Text(franchise.location)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if franchiseManager.currentFranchise?.id == franchise.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                } else {
                    // Normal kullanıcı sadece kendi franchise'ını görür
                    if let franchise = franchiseManager.currentFranchise {
                        Text(franchise.name)
                            .font(.largeTitle)
                    }
                }
            }
            .navigationTitle("Franchise")
            .onAppear {
                franchiseManager.loadUserFranchise { _ in }
                if authManager.userProfile?.role == .superAdmin {
                    franchiseManager.loadAllFranchises { _ in }
                }
            }
        }
    }
}
```

---

### **ADIM 10: AppDelegate'te Franchise Initialization**

```swift
// AppDelegate.swift veya AracHasarKayitApp.swift

import SwiftUI
import FirebaseCore

@main
struct AracHasarKayitApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var franchiseManager = FranchiseManager.shared
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                // Kullanıcı giriş yaptıysa franchise yükle
                MainView()
                    .onAppear {
                        franchiseManager.loadUserFranchise { franchise in
                            if franchise == nil {
                                // Franchise bulunamadı - hata göster
                                print("⚠️ Kullanıcının franchise'ı bulunamadı!")
                            }
                        }
                    }
            } else {
                LoginView()
            }
        }
    }
}
```

---

## 📋 UYGULAMA SIRASI

### **Faz 1: Veri Modeli Güncellemeleri (1-2 Gün)**
1. ✅ `Franchise` modeli oluştur
2. ✅ `UserProfile`'a `franchiseId` ve `role` ekle
3. ✅ `Arac` modeline `franchiseId` ekle
4. ✅ Diğer modellere `franchiseId` ekle (Servis, İade, Activity, vb.)

### **Faz 2: Backend Güncellemeleri (2-3 Gün)**
5. ✅ `FranchiseManager` oluştur
6. ✅ `FirebaseService`'i franchise-aware yap
7. ✅ Firestore Rules güncelle
8. ✅ Storage Rules güncelle

### **Faz 3: Migration (1 Gün)**
9. ✅ Migration script yaz
10. ✅ Mevcut verileri migrate et (test ortamında önce!)
11. ✅ İlk franchise'ı oluştur (`franchise_001`)

### **Faz 4: UI Güncellemeleri (1-2 Gün)**
12. ✅ Franchise seçim ekranı (super admin için)
13. ✅ Tüm query'lerde franchise filtresi
14. ✅ Yeni kayıtlarda otomatik franchise ID ekleme

### **Faz 5: Test (2-3 Gün)**
15. ✅ Her franchise'ın sadece kendi verilerini görmesi
16. ✅ Super admin'in tüm verileri görmesi
17. ✅ Security rules testleri
18. ✅ Performance testleri

---

## 🔒 GÜVENLİK KONTROL LİSTESİ

- [ ] Firestore Rules: Franchise izolasyonu
- [ ] Storage Rules: Franchise bazlı erişim
- [ ] Client-side validation: Franchise ID değiştirilemez
- [ ] Super Admin: Tüm franchise'lara erişim
- [ ] Audit Log: Her işlemde franchise ID kaydı

---

## 📊 PERFORMANS İYİLEŞTİRMELERİ

### **Firestore Index'leri:**

```
Collection: araclar
Index:
- franchiseId (Ascending)
- kayitTarihi (Descending)

Collection: users
Index:
- franchiseId (Ascending)
- role (Ascending)

Collection: activities
Index:
- franchiseId (Ascending)
- tarih (Descending)
```

---

## 🎯 SONUÇ

**Önerilen Mimari:** **SEÇENEK 2 - Tek Firebase Projesi + Franchise ID**

**Neden:**
- ✅ Mevcut koda minimal değişiklik
- ✅ Tek app, tüm franchise'lar
- ✅ Kolay migrasyon
- ✅ Merkezi yönetim
- ✅ Güvenli (Rules ile)
- ✅ Ölçeklenebilir

**Tahmini Süre:** 7-10 gün (1 developer)

**Risk Seviyesi:** Düşük-Orta (Migration dikkatli yapılmalı)

