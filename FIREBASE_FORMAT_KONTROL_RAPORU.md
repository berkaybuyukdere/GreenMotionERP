# 🔍 Firebase Veri Format Kontrol Raporu

**Tarih:** $(date)
**Kontrol Edilen:** Tüm Firebase koleksiyonları ve veri formatları

---

## ⚠️ KRİTİK BULGULAR

### 1. 🔴 SERVİS KOLEKSİYONU İSMİ TUTARSIZLIĞI

**Problem:** Servis kayıtları iki farklı koleksiyon ismi kullanıyor!

**Durum:**
- ✅ `FirebaseService.swift` → `"servisler"` kullanıyor (satır 75, 96, 105)
- ✅ `CascadeDeleteManager.swift` → `"servisKayitlari"` kullanıyor (satır 39, 140, 212, 366)
- ✅ `FIREBASE_DATA_STRUCTURE.md` → `"servisKayitlari"` dokümante edilmiş
- ✅ `firestore.rules` → Her iki koleksiyon için de rule var (satır 94 ve 104)

**Etki:**
- 🔴 Bazı kullanıcılar `servisler` koleksiyonundaki verileri görüyor
- 🔴 Bazı kullanıcılar `servisKayitlari` koleksiyonundaki verileri görüyor  
- 🔴 Veriler iki ayrı yerde kaydediliyor olabilir
- 🔴 Silme işlemleri yanlış koleksiyondan silme yapıyor olabilir

**Çözüm Önerisi:**
1. Tek bir koleksiyon ismi belirle: `servisKayitlari` (dokümantasyona uygun)
2. `FirebaseService.swift`'deki tüm `"servisler"` referanslarını `"servisKayitlari"` olarak değiştir
3. Firebase'deki `servisler` koleksiyonundaki verileri `servisKayitlari`'na taşı
4. Eski `servisler` koleksiyonunu sil

**Etkilenen Dosyalar:**
- `AracHasarKayit/Firebase/FirebaseService.swift` (satır 75, 96, 105)

---

### 2. 🟡 OFFICE OPERATIONS KOLEKSİYON İSMİ DOKÜMANTASYON UYUMSUZLUĞU

**Problem:** Dokümantasyonda koleksiyon ismi yanlış yazılmış

**Durum:**
- ✅ Kod: `"office_operations"` (snake_case) - TUTARLI kullanılıyor
- ❌ Dokümantasyon (`FIREBASE_DATA_STRUCTURE.md` satır 199): `"officeOperations"` (camelCase) yazıyor
- ✅ `firestore.rules`: `"office_operations"` doğru

**Etki:**
- 🟡 Dokümantasyon hatası - kodda sorun yok
- 🟡 Yeni geliştiriciler için kafa karıştırıcı

**Çözüm Önerisi:**
1. `FIREBASE_DATA_STRUCTURE.md` dosyasında `"officeOperations"` → `"office_operations"` olarak düzelt

---

### 3. 🟡 OFFICEOPERATION ENCODİNG TUTARSIZLIĞI

**Problem:** OfficeOperation diğer modellerden farklı şekilde encode ediliyor

**Durum:**
- ❌ `OfficeOperation`: Manuel `JSONEncoder` + `JSONSerialization` kullanıyor (`FirebaseService.swift` satır 360-361)
- ✅ Diğer modeller (`Arac`, `HasarKaydi`, `Activity`, vb.): `setData(from:)` kullanıyor

**Etki:**
- 🟡 Date ve enum encoding'i tutarsız olabilir
- 🟡 Timestamp dönüşümleri farklı çalışabilir

**Kod İncelenmesi:**
```swift
// FirebaseService.swift - satır 358-367
func saveOfficeOperation(_ operation: OfficeOperation, completion: @escaping (Error?) -> Void) {
    do {
        let data = try JSONEncoder().encode(operation)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        db.collection("office_operations").document(operation.id.uuidString).setData(dict) { error in
            completion(error)
        }
    } catch {
        completion(error)
    }
}
```

**Diğer modeller:**
```swift
// FirebaseService.swift - satır 48
try db.collection("araclar").document(arac.id.uuidString).setData(from: arac) { error in
    completion(error)
}
```

**Çözüm Önerisi:**
1. `OfficeOperation` için de `setData(from:)` kullan
2. Veya custom encoder ekle Date ve enum handling için

---

### 4. 🟢 PROTOCOL MODELİ DATE FORMATI (Beklenen davranış)

**Durum:**
- ✅ `Protocol` modeli tarihleri `String` olarak tutuyor (ISO8601 formatında)
- ✅ Diğer modeller `Date`/`Timestamp` kullanıyor

**Etki:**
- 🟢 Bu muhtemelen kasıtlı - Protocol verileri external sistemden geliyor olabilir
- 🟢 Kod tutarlı çalışıyor gibi görünüyor

**Not:** Bu bir sorun değil, ancak farklılık kayıt altında.

---

## ✅ DOĞRU ÇALIŞAN FORMATLAR

### 1. **Araçlar (araclar)**
- ✅ Koleksiyon ismi: `"araclar"` - TUTARLI
- ✅ Document ID: UUID string
- ✅ Date encoding: Firebase Timestamp → Swift Date (otomatik)
- ✅ Nested `hasarKayitlari` array yapısı doğru

### 2. **Hasar Kayıtları (nested in aracilar)**
- ✅ Date encoding: Firebase Timestamp → Swift Date
- ✅ Enum encoding: String rawValue
- ✅ Photo URL array: String array - TUTARLI

### 3. **Activities**
- ✅ Koleksiyon ismi: `"activities"` - TUTARLI
- ✅ Date encoding: Firebase Timestamp
- ✅ Enum encoding: ActivityType rawValue

### 4. **İade İşlemleri (iadeIslemleri)**
- ✅ Koleksiyon ismi: `"iadeIslemleri"` - TUTARLI
- ✅ Date encoding: Firebase Timestamp
- ✅ Enum encoding: IadeStatus rawValue

### 5. **Servis Firmaları (servisFirmalari)**
- ✅ Koleksiyon ismi: `"servisFirmalari"` - TUTARLI
- ✅ UUID encoding: String format

### 6. **Protocols**
- ✅ Koleksiyon ismi: `"protocols"` - TUTARLI
- ✅ Document ID: String (Firebase document ID)
- ✅ Tüm alanlar String (external sistem uyumluluğu için)

### 7. **Shuttle Sistem**
- ✅ `shuttleSessions` - TUTARLI
- ✅ `shuttleEntries` - TUTARLI

---

## 📊 ÖZET TABLO

| Koleksiyon | Kullanılan İsim | Dokümantasyon | Durum |
|------------|----------------|---------------|-------|
| `araclar` | ✅ `araclar` | ✅ `araclar` | ✅ TUTARLI |
| `servisler` | ⚠️ **TUTARSIZ** | ❌ `servisKayitlari` | 🔴 **SORUN** |
| `servisKayitlari` | ⚠️ **TUTARSIZ** | ✅ `servisKayitlari` | 🔴 **SORUN** |
| `iadeIslemleri` | ✅ `iadeIslemleri` | ✅ `iadeIslemleri` | ✅ TUTARLI |
| `activities` | ✅ `activities` | ✅ `activities` | ✅ TUTARLI |
| `office_operations` | ✅ `office_operations` | ❌ `officeOperations` | 🟡 Dokümantasyon hatası |
| `protocols` | ✅ `protocols` | ✅ `protocols` | ✅ TUTARLI |
| `servisFirmalari` | ✅ `servisFirmalari` | ✅ `servisFirmalari` | ✅ TUTARLI |

---

## 🎯 ÖNCELİKLİ AKSİYONLAR

### 🔴 YÜKSEK ÖNCELİK (Hemen Yapılmalı)

1. **Servis Koleksiyonu Tutarlılığı**
   - [ ] `FirebaseService.swift`'de `"servisler"` → `"servisKayitlari"` değiştir
   - [ ] Firebase'de veri migrasyonu yap (servisler → servisKayitlari)
   - [ ] Test et - tüm kullanıcılar aynı verileri görmeli

### 🟡 ORTA ÖNCELİK (Bu Hafta)

2. **OfficeOperation Encoding Tutarlılığı**
   - [ ] `FirebaseService.swift`'de OfficeOperation için `setData(from:)` kullan
   - [ ] Veya custom encoder ekle Date handling için

3. **Dokümantasyon Düzeltmeleri**
   - [ ] `FIREBASE_DATA_STRUCTURE.md`'de `officeOperations` → `office_operations` düzelt

---

## 🔍 KONTROL EDİLEN ALANLAR

✅ UUID encoding/decoding
✅ Date/Timestamp conversion
✅ Enum encoding (rawValue)
✅ Collection name consistency
✅ Field name consistency (camelCase)
✅ Nested array structures
✅ Optional field handling
✅ Firebase Storage URL formats

---

## 📝 NOTLAR

1. **Firestore Rules:** Her iki servis koleksiyonu için de rule var - bu iyi ama tutarsızlık yaratıyor
2. **Backward Compatibility:** Eski veriler için migration script gerekebilir
3. **Testing:** Değişikliklerden sonra mutlaka test edilmeli:
   - Yeni servis ekleme
   - Servis silme
   - Servis güncelleme
   - Farklı kullanıcılardan görüntüleme

---

## 🚨 KRİTİK UYARI

**Servis koleksiyonu tutarsızlığı nedeniyle:**
- Bazı kullanıcılar servis verilerini görmüyor olabilir
- Veriler iki farklı koleksiyonda kaydediliyor olabilir
- Silme işlemleri yanlış koleksiyondan silme yapıyor olabilir

**Hemen düzeltilmeli!**


