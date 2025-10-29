# 📦 Data Backup Options for AracHasarKayit

**Comprehensive Guide to Database Backup Solutions**

---

## 🎯 Backup İhtiyacı

Mevcut sisteminiz **Firebase Firestore** kullanıyor. Backup stratejileri:

1. **Otomatik Yedekleme** - Firebase'in kendi backup'ları
2. **Manuel Export** - JSON/CSV export
3. **Cloud Storage Backup** - Google Cloud Storage
4. **Hybrid Solutions** - Birden fazla yerde yedek

---

## 🗄️ DATABASE BACKUP SEÇENEKLERİ

### 1. **Firebase Firestore Native Backup** ⭐⭐⭐⭐⭐
**En Kolay ve En Güvenilir**

#### Özellikleri:
- ✅ Otomatik günlük backup
- ✅ 7-30 gün retention (ayarlanabilir)
- ✅ Point-in-time recovery
- ✅ Kolay restore işlemi
- ✅ Firebase Console'dan yönetim

#### Nasıl Kurulur:
```bash
# Firebase CLI ile
firebase firestore:backups:schedule DAILY \
  --collection-group=all \
  --retention-period=7d \
  --location=us-central1
```

#### Avantajları:
- ✅ Ücretsiz (Firebase planınızda dahil)
- ✅ Sıfır konfigürasyon
- ✅ Otomatik çalışır
- ✅ Güvenli ve güvenilir

#### Dezavantajları:
- ⚠️ Sadece Firestore koleksiyonları (Storage ayrı)
- ⚠️ Firebase ekosistemine bağımlı

#### Fiyatlandırma:
- **Spark Plan:** Backup yok
- **Blaze Plan:** Backup dahil

---

### 2. **Google Cloud Storage (GCS) Export** ⭐⭐⭐⭐
**Firestore Data + Firebase Storage**

#### Özellikleri:
- ✅ Firestore JSON export
- ✅ Firebase Storage dosyaları
- ✅ Scheduled exports (günlük/haftalık)
- ✅ Custom retention policies
- ✅ Bulunduğu yerde encryption

#### Nasıl Kurulur:
```swift
// Cloud Function ile otomatik export
import { functions } from 'firebase-functions';
import { Storage } from '@google-cloud/storage';

exports.scheduledExport = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const projectId = 'your-project-id';
    const bucketName = 'your-backup-bucket';
    
    // Firestore export
    await admin.firestore().exportDocuments({
      projectId,
      bucket: `gs://${bucketName}/firestore-backup-${Date.now()}`,
    });
    
    // Storage backup
    // Firebase Storage dosyalarını GCS'e kopyala
  });
```

#### Avantajları:
- ✅ Hem Firestore hem Storage backup
- ✅ Unlimited storage (ücret ödersiniz)
- ✅ Archive storage class (ucuz)
- ✅ Lifecycle management (otomatik silme)
- ✅ Versioning desteği

#### Dezavantajları:
- ⚠️ Cloud Function gerekir
- ⚠️ Storage maliyeti var

#### Fiyatlandırma:
- **Storage:** $0.020/GB/ay (Standard)
- **Archive:** $0.004/GB/ay (uzun vadeli)
- **Operations:** $0.05/10,000 operations

---

### 3. **MongoDB Atlas** ⭐⭐⭐
**Hybrid Database Backup**

#### Özellikleri:
- ✅ Cloud-hosted MongoDB
- ✅ Otomatik backup (daily snapshots)
- ✅ Point-in-time recovery
- ✅ Cross-region replication
- ✅ 7-35 gün retention

#### Nasıl Entegre Edilir:
```swift
// Firestore'dan MongoDB'ye sync
import MongoSwift

func syncToMongoDB() {
    let client = try MongoClient("mongodb+srv://...")
    let db = client.db("vehicle_backup")
    
    // Firestore data'yı MongoDB'ye kopyala
    FirebaseService.shared.loadAraclar { araclar, error in
        let collection = db.collection("vehicles")
        try? collection.insertMany(araclar.map { $0.toBSON() })
    }
}
```

#### Avantajları:
- ✅ Firebase'den bağımsız backup
- ✅ Kolay query (MongoDB query language)
- ✅ Atlas ücretsiz tier (512MB)
- ✅ Otomatik backup

#### Dezavantajları:
- ⚠️ Sync mekanizması gerekir
- ⚠️ Firestore structure mapping gerekir

#### Fiyatlandırma:
- **Free Tier:** 512MB storage
- **M0 (Shared):** $0/mo (512MB, sınırlı backup)
- **M10+:** $57+/mo (otomatik backup dahil)

---

### 4. **PostgreSQL (Supabase/Railway/Render)** ⭐⭐⭐⭐
**Open Source Alternative**

#### Özellikleri:
- ✅ PostgreSQL database
- ✅ JSONB desteği (Firestore benzeri)
- ✅ Otomatik backup
- ✅ Point-in-time recovery
- ✅ Replication

#### Seçenekler:

**A. Supabase**
- Free tier: 500MB
- Automatic daily backups (7 days)
- Easy Firebase migration

**B. Railway**
- Pay-as-you-go
- Automatic backups
- $5/mo başlangıç

**C. Render**
- Free tier: 90MB
- Automatic daily backups
- Upgrade gerekir

#### Nasıl Kurulur:
```swift
// Firestore → PostgreSQL sync
import PostgreSQL

func syncToPostgres() {
    let connection = try PostgresConnection(...)
    
    // Firestore data'yı PostgreSQL'e map et
    // JSONB kullanarak flexible schema
}
```

#### Avantajları:
- ✅ Firebase alternatifi
- ✅ SQL query capabilities
- ✅ Relational data yapısı
- ✅ Açık kaynak

#### Dezavantajları:
- ⚠️ Migration çalışması gerekir
- ⚠️ Schema mapping gerekir

---

### 5. **AWS Solutions** ⭐⭐⭐⭐⭐
**Enterprise-Grade Backup**

#### 5A. **AWS DynamoDB**
- ✅ NoSQL (Firestore benzeri)
- ✅ Automatic backups (Point-in-time recovery)
- ✅ Cross-region replication
- ✅ On-demand backup
- **Fiyat:** $0.00065/GB/ay (backup storage)

#### 5B. **AWS S3 + Glacier**
- ✅ Firestore export + Storage dosyaları
- ✅ Lifecycle policies (S3 → Glacier)
- ✅ Versioning
- ✅ Encryption
- **Fiyat:** 
  - S3: $0.023/GB/ay
  - Glacier: $0.0036/GB/ay

#### 5C. **AWS RDS (PostgreSQL/MySQL)**
- ✅ Managed database
- ✅ Automated backups (35 days)
- ✅ Multi-AZ replication
- **Fiyat:** $15+/mo

---

### 6. **Azure Cosmos DB** ⭐⭐⭐⭐
**Microsoft Cloud Alternative**

#### Özellikleri:
- ✅ Multi-model database
- ✅ Automatic backups (7-30 days)
- ✅ Global distribution
- ✅ API compatible with MongoDB/PostgreSQL

#### Fiyatlandırma:
- **Free Tier:** 25GB storage
- **Standard:** $0.0006/GB/ay

---

### 7. **Self-Hosted Solutions** ⭐⭐
**Kendi Sunucunuz**

#### 7A. **Self-Hosted PostgreSQL**
- Docker container
- pg_dump ile backup
- Cron job ile scheduled backup
- **Maliyet:** Sadece sunucu maliyeti ($5-20/mo)

#### 7B. **Self-Hosted MongoDB**
- MongoDB Community Edition
- mongodump ile backup
- **Maliyet:** Sadece sunucu maliyeti

#### 7C. **Backup Server (Nextcloud/ownCloud)**
- File-based backup
- JSON exports
- **Maliyet:** Sunucu maliyeti

---

## 🎯 ÖNERİLEN BACKUP STRATEJİSİ

### **Seviye 1: Hızlı ve Ücretsiz (Başlangıç)**
```
Firebase Firestore Native Backup + GCS Export
✅ Otomatik
✅ Ücretsiz (Blaze plan)
✅ Kolay restore
```

### **Seviye 2: Orta Seviye (Güvenlik)**
```
Firebase Backup + MongoDB Atlas (Free Tier)
✅ İki farklı yerde yedek
✅ Firestore + MongoDB
✅ Ücretsiz başlangıç
```

### **Seviye 3: Enterprise (Production)**
```
Firebase Backup + GCS Archive + AWS S3/Glacier
✅ 3 farklı yerde yedek
✅ Long-term archive (Glacier)
✅ Disaster recovery
```

---

## 💻 IMPLEMENTATION GUIDE

### **Option 1: Firebase Native Backup (En Kolay)**

#### Step 1: Firebase Console
```
Firebase Console → Firestore → Backups → Schedule Backup
- Frequency: Daily
- Retention: 7-30 days
- Location: us-central1
```

#### Step 2: Cloud Function ile Export
```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

exports.scheduledFirestoreBackup = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const projectId = 'greenmotionapp-33413';
    const bucketName = 'gs://greenmotion-backups';
    
    // Export Firestore
    await admin.firestore().exportDocuments({
      projectId,
      bucket: bucketName,
      collectionIds: ['araclar', 'servisler', 'iadeIslemleri', 'officeOperations']
    });
    
    console.log('✅ Backup completed');
  });
```

#### Step 3: Deploy
```bash
firebase deploy --only functions:scheduledFirestoreBackup
```

---

### **Option 2: GCS Export + Storage Backup**

#### Complete Backup Script:
```swift
// AracHasarKayit/Utilities/BackupManager.swift
import Foundation
import FirebaseFirestore
import FirebaseStorage
import GoogleCloudStorage

class BackupManager {
    static let shared = BackupManager()
    
    func performFullBackup(completion: @escaping (Result<String, Error>) -> Void) {
        // 1. Export Firestore to JSON
        exportFirestore { result in
            switch result {
            case .success(let firestoreURL):
                // 2. Backup Firebase Storage
                self.backupStorageFiles { result2 in
                    switch result2 {
                    case .success(let storageURL):
                        // 3. Create manifest
                        self.createManifest(firestore: firestoreURL, storage: storageURL) { result3 in
                            completion(result3)
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func exportFirestore(completion: @escaping (Result<String, Error>) -> Void) {
        // Cloud Function çağrısı veya manual export
        // Firestore collection'ları JSON'a export et
    }
    
    private func backupStorageFiles(completion: @escaping (Result<String, Error>) -> Void) {
        // Firebase Storage'daki tüm dosyaları GCS'e kopyala
    }
    
    private func createManifest(firestore: String, storage: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Backup manifest dosyası oluştur
        let manifest = BackupManifest(
            timestamp: Date(),
            firestoreBackupURL: firestore,
            storageBackupURL: storage,
            version: Bundle.main.appVersion
        )
        // GCS'e yükle
    }
}
```

---

### **Option 3: MongoDB Atlas Sync**

```swift
// AracHasarKayit/Utilities/MongoBackupManager.swift
import Foundation
import MongoSwift

class MongoBackupManager {
    private let mongoClient: MongoClient
    private let db: MongoDatabase
    
    init(connectionString: String) {
        mongoClient = try! MongoClient(connectionString)
        db = mongoClient.db("vehicle_backup")
    }
    
    func syncFromFirestore(completion: @escaping (Result<Int, Error>) -> Void) {
        FirebaseService.shared.loadAraclar { araclar, error in
            guard let araclar = araclar else {
                completion(.failure(error ?? NSError()))
                return
            }
            
            let collection = self.db.collection("vehicles")
            
            // Delete old data
            try? collection.deleteMany([:])
            
            // Insert new data
            let documents = araclar.map { $0.toBSON() }
            try? collection.insertMany(documents)
            
            completion(.success(araclar.count))
        }
    }
}

extension Arac {
    func toBSON() -> BSONDocument {
        var doc = BSONDocument()
        doc["id"] = .string(self.id.uuidString)
        doc["plaka"] = .string(self.plaka)
        doc["marka"] = .string(self.marka)
        // ... diğer fieldlar
        return doc
    }
}
```

---

## 📊 KARŞILAŞTIRMA TABLOSU

| Solution | Ease | Cost | Reliability | Features | Recommendation |
|----------|------|------|-------------|----------|----------------|
| **Firebase Native** | ⭐⭐⭐⭐⭐ | Free/Paid | ⭐⭐⭐⭐⭐ | Basic | ✅ **En kolay** |
| **GCS Export** | ⭐⭐⭐⭐ | Low | ⭐⭐⭐⭐⭐ | Advanced | ✅ **Production için** |
| **MongoDB Atlas** | ⭐⭐⭐ | Free/Low | ⭐⭐⭐⭐ | Good | ✅ **Alternatif backup** |
| **PostgreSQL (Supabase)** | ⭐⭐⭐ | Free/Low | ⭐⭐⭐⭐ | Great | ⚠️ Migration gerekir |
| **AWS S3/Glacier** | ⭐⭐⭐ | Low/Medium | ⭐⭐⭐⭐⭐ | Enterprise | ✅ **Long-term archive** |
| **Self-Hosted** | ⭐⭐ | Low | ⭐⭐⭐ | Manual | ⚠️ Bakım gerekir |

---

## 🎯 TAVSİYE: HİBRİT YAKLAŞIM

### **Startup için en iyi strateji:**

```swift
// 1. Firebase Native Backup (Primary)
- Otomatik günlük backup
- 7-30 gün retention

// 2. GCS Export (Secondary)
- Haftalık full export
- Archive storage class
- Long-term retention (1+ year)

// 3. MongoDB Atlas (Disaster Recovery)
- Aylık sync
- Cross-region backup
- Ücretsiz tier yeterli
```

**Toplam Maliyet:** ~$10-20/ay (starter için)

---

## 🚀 HIZLI BAŞLANGIÇ

### **1 Saatlik Kurulum:**

```bash
# 1. Firebase Backup'ı aktif et
firebase firestore:backups:schedule DAILY \
  --collection-group=all \
  --retention-period=7d

# 2. Cloud Function deploy et (GCS export için)
firebase deploy --only functions:backupFunction

# 3. İlk backup'i manuel çalıştır
firebase firestore:export gs://your-bucket/backup-$(date +%Y%m%d)
```

---

## ✅ SONUÇ

**En iyi seçenek startup için:**

1. **Firebase Native Backup** - Otomatik, kolay, güvenilir
2. **GCS Export (Haftalık)** - Long-term archive
3. **MongoDB Atlas (Opsiyonel)** - Disaster recovery

**Toplam maliyet:** Minimal (Firebase plan dahil)
**Kurulum süresi:** 1-2 saat
**Bakım:** Minimal (otomatik)

