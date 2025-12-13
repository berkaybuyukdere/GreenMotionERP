# 🔄 Firestore Backup Kurulum Rehberi

**Problem:** Firestore'da otomatik backup görünmüyor (Realtime Database'de var)

**Çözüm:** Firestore için backup ayarlama yöntemleri

---

## 📋 DURUM ANALİZİ

✅ **Realtime Database:** Otomatik backup mevcut
⚠️ **Firestore:** Backup manuel olarak kurulması gerekiyor

**Neden?** Firestore daha yeni bir sistem ve backup özellikleri farklı şekilde çalışıyor.

---

## 🎯 FIRESTORE BACKUP YÖNTEMLERİ

### **Yöntem 1: Cloud Console'dan Manuel Export** ⭐ (Hızlı, Kolay)

#### Adım 1: Google Cloud Console'a Git
1. https://console.cloud.google.com adresine git
2. Projenizi seçin: `greenmotionapp-33413`
3. Sol menüden **Firestore** → **Export/Import** seçin

#### Adım 2: Export İşlemi
```
1. "Export" butonuna tıkla
2. Collection ID'lerini seç:
   - araclars
   - servisler
   - iadeIslemleri
   - officeOperations
   - protocols
   - activities
   - servisFirmalari
   - users
   - userPresence
   - shuttleEntries
   - shuttleSessions

3. Cloud Storage bucket seç (yoksa oluştur):
   - gs://greenmotion-backups/firestore-exports/

4. "Export" butonuna tıkla
5. İşlem 5-30 dakika sürebilir
```

#### Adım 3: Export Dosyalarını İndir
```
1. Cloud Storage bucket'a git
2. Export dosyalarını görüntüle
3. İstenirse indir veya arşivle
```

**Avantajları:**
- ✅ Çok kolay
- ✅ Hemen yapılabilir
- ✅ GUI üzerinden

**Dezavantajları:**
- ⚠️ Manuel (otomatik değil)
- ⚠️ Her seferinde tekrar yapman gerekir

---

### **Yöntem 2: Scheduled Cloud Function (Önerilen)** ⭐⭐⭐⭐⭐

Otomatik günlük/haftalık backup için Cloud Function kullan.

#### Adım 1: Cloud Function Oluştur

**Dosya:** `functions/index.js` (mevcut dosyaya ekle)

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { PubSub } = require('@google-cloud/pubsub');

// Firestore backup function
exports.scheduledFirestoreBackup = functions.pubsub
  .schedule('every 24 hours') // Her gün saat 02:00'de (varsayılan)
  .timeZone('Europe/Zurich') // İsviçre saati
  .onRun(async (context) => {
    const projectId = process.env.GCLOUD_PROJECT;
    const bucketName = 'greenmotion-backups';
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    
    const bucket = admin.storage().bucket(bucketName);
    
    // Export path
    const exportPath = `firestore-backups/${timestamp}`;
    
    try {
      console.log(`🔄 Starting Firestore backup to ${exportPath}`);
      
      // Firestore export using Admin SDK
      // Note: This requires Firestore Export API to be enabled
      const firestore = admin.firestore();
      
      // Get all collections
      const collections = [
        'araclar',
        'servisler',
        'iadeIslemleri',
        'officeOperations',
        'protocols',
        'activities',
        'servisFirmalari',
        'users',
        'userPresence',
        'shuttleEntries',
        'shuttleSessions'
      ];
      
      // Export each collection
      for (const collectionId of collections) {
        const querySnapshot = await firestore.collection(collectionId).get();
        const docs = querySnapshot.docs.map(doc => ({
          id: doc.id,
          data: doc.data()
        }));
        
        // Save to Cloud Storage as JSON
        const file = bucket.file(`${exportPath}/${collectionId}.json`);
        await file.save(JSON.stringify(docs, null, 2), {
          metadata: {
            contentType: 'application/json',
            metadata: {
              collection: collectionId,
              timestamp: new Date().toISOString()
            }
          }
        });
        
        console.log(`✅ Exported ${collectionId}: ${docs.length} documents`);
      }
      
      // Create manifest file
      const manifest = {
        timestamp: new Date().toISOString(),
        projectId: projectId,
        collections: collections,
        version: '1.0'
      };
      
      const manifestFile = bucket.file(`${exportPath}/manifest.json`);
      await manifestFile.save(JSON.stringify(manifest, null, 2), {
        metadata: {
          contentType: 'application/json'
        }
      });
      
      console.log(`✅ Backup completed: ${exportPath}`);
      
      // Delete old backups (keep last 30 days)
      await deleteOldBackups(bucket, 30);
      
      return null;
    } catch (error) {
      console.error(`❌ Backup failed: ${error.message}`);
      throw error;
    }
  });

// Helper function to delete old backups
async function deleteOldBackups(bucket, daysToKeep) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);
  
  const [files] = await bucket.getFiles({
    prefix: 'firestore-backups/'
  });
  
  for (const file of files) {
    const [metadata] = await file.getMetadata();
    const created = new Date(metadata.timeCreated);
    
    if (created < cutoffDate) {
      await file.delete();
      console.log(`🗑️ Deleted old backup: ${file.name}`);
    }
  }
}
```

#### Adım 2: Gerekli Paketleri Yükle

```bash
cd functions
npm install @google-cloud/pubsub --save
```

#### Adım 3: Cloud Storage Bucket Oluştur

```bash
# Firebase CLI ile
gsutil mb -p greenmotionapp-33413 -l europe-west1 gs://greenmotion-backups/

# Veya Cloud Console'dan:
# Storage → Create Bucket → "greenmotion-backups"
```

#### Adım 4: IAM Permissions Ayarla

Cloud Function'ın Firestore ve Storage'a erişebilmesi için:

1. Cloud Console → IAM & Admin → Service Accounts
2. `your-project@appspot.gserviceaccount.com` bul
3. Şu rolleri ekle:
   - **Cloud Datastore User**
   - **Storage Admin**

#### Adım 5: Deploy Et

```bash
cd functions
firebase deploy --only functions:scheduledFirestoreBackup
```

#### Adım 6: İlk Backup'i Test Et

```bash
# Manuel olarak tetikle
firebase functions:shell
> scheduledFirestoreBackup()
```

**Avantajları:**
- ✅ Tam otomatik
- ✅ Günlük backup
- ✅ Eski backup'ları otomatik siler
- ✅ Email bildirimi eklenebilir

---

### **Yöntem 3: gcloud CLI ile Export** ⭐⭐⭐⭐

Terminal/komut satırı üzerinden backup.

#### Adım 1: gcloud CLI Kurulumu

```bash
# macOS
brew install google-cloud-sdk

# veya manuel indir:
# https://cloud.google.com/sdk/docs/install
```

#### Adım 2: Authentication

```bash
gcloud auth login
gcloud config set project greenmotionapp-33413
```

#### Adım 3: Export Script

**Dosya oluştur:** `backup-firestore.sh`

```bash
#!/bin/bash

# Firestore Backup Script
PROJECT_ID="greenmotionapp-33413"
BUCKET_NAME="greenmotion-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_PATH="gs://${BUCKET_NAME}/firestore-exports/${TIMESTAMP}"

echo "🔄 Starting Firestore backup..."

# Export all collections
gcloud firestore export ${EXPORT_PATH} \
  --project=${PROJECT_ID} \
  --collection-ids=araclar,servisler,iadeIslemleri,officeOperations,protocols,activities,servisFirmalari,users,userPresence,shuttleEntries,shuttleSessions

if [ $? -eq 0 ]; then
  echo "✅ Backup completed: ${EXPORT_PATH}"
  
  # Optional: Delete backups older than 30 days
  gsutil -m rm -r gs://${BUCKET_NAME}/firestore-exports/$(date -v-30d +%Y%m%d)* 2>/dev/null
  
  echo "✅ Old backups cleaned"
else
  echo "❌ Backup failed"
  exit 1
fi
```

#### Adım 4: Script'i Çalıştırılabilir Yap

```bash
chmod +x backup-firestore.sh
```

#### Adım 5: Cron Job Oluştur (Otomatik)

```bash
# macOS/Linux
crontab -e

# Her gün saat 02:00'de çalıştır
0 2 * * * /path/to/backup-firestore.sh >> /path/to/backup.log 2>&1
```

**Avantajları:**
- ✅ Tam kontrol
- ✅ Komut satırı üzerinden
- ✅ Otomatik hale getirilebilir

---

### **Yöntem 4: Firestore Native Scheduled Backups** ⭐⭐⭐ (CLI ile)

Firestore'un kendi scheduled backup özelliği (CLI ile).

#### Adım 1: Export API'yi Aktif Et

```bash
gcloud services enable firestore.googleapis.com
gcloud services enable firestoreexport.googleapis.com
```

#### Adım 2: Scheduled Backup Oluştur

```bash
# Günlük backup
gcloud firestore backups schedules create DAILY \
  --collection-ids=araclar,servisler,iadeIslemleri,officeOperations,protocols,activities,servisFirmalari,users \
  --retention-period=7d \
  --location=us-central1 \
  --project=greenmotionapp-33413

# Veya haftalık
gcloud firestore backups schedules create WEEKLY \
  --collection-ids=araclar,servisler,iadeIslemleri,officeOperations \
  --retention-period=30d \
  --location=us-central1
```

#### Adım 3: Backup'ları Listele

```bash
gcloud firestore backups list
```

#### Adım 4: Restore İşlemi

```bash
# Backup ID'yi al
BACKUP_ID="your-backup-id"

# Restore et
gcloud firestore databases restore \
  --backup=${BACKUP_ID} \
  --location=us-central1
```

**Avantajları:**
- ✅ Firestore native özelliği
- ✅ Point-in-time recovery
- ✅ Otomatik retention

**Dezavantajları:**
- ⚠️ CLI üzerinden kurulum gerekir
- ⚠️ Console'da görünmez (CLI'da listelenir)

---

## 🎯 ÖNERİLEN YAKLAŞIM

### **Başlangıç için:**
1. ✅ **Yöntem 1** (Manuel Export) - Hemen bir backup al
2. ✅ **Yöntem 2** (Cloud Function) - Otomatik backup kur

### **Production için:**
1. ✅ **Yöntem 2** (Cloud Function) - Günlük otomatik backup
2. ✅ **Yöntem 4** (Native Scheduled) - Ekstra güvenlik için

---

## 📝 ADIM ADIM KURULUM (Önerilen)

### **1. Cloud Storage Bucket Oluştur**

**Terminal:**
```bash
gsutil mb -p greenmotionapp-33413 -l europe-west1 gs://greenmotion-backups/
```

**Veya Cloud Console:**
1. Cloud Console → Storage → Create Bucket
2. Name: `greenmotion-backups`
3. Location: `europe-west1` (veya en yakın bölge)
4. Create

### **2. Cloud Function Oluştur**

`functions/index.js` dosyasına ekle (yukarıdaki kodu)

### **3. Deploy**

```bash
cd functions
npm install
firebase deploy --only functions:scheduledFirestoreBackup
```

### **4. İlk Backup'i Test Et**

Cloud Console → Functions → `scheduledFirestoreBackup` → Test

### **5. Backup'ları Kontrol Et**

Cloud Console → Storage → `greenmotion-backups` → `firestore-backups/`

---

## 🔍 BACKUP'LARI GÖRME VE YÖNETME

### **Cloud Console Üzerinden:**

1. **Storage Bucket:**
   ```
   Console → Storage → greenmotion-backups → firestore-backups/
   ```
   Burada tarihli klasörler göreceksin.

2. **Export History:**
   ```
   Console → Firestore → Backups
   ```
   (Eğer native scheduled backup kullanıyorsan)

### **CLI Üzerinden:**

```bash
# Cloud Function logları
firebase functions:log --only scheduledFirestoreBackup

# Storage'daki dosyaları listele
gsutil ls -r gs://greenmotion-backups/firestore-backups/

# Backup boyutunu kontrol et
gsutil du -sh gs://greenmotion-backups/firestore-backups/
```

---

## 💰 MALİYET HESABI

| Item | Storage | Operations | Monthly Cost |
|------|---------|------------|--------------|
| **Backup Storage** | 10GB | - | ~$0.26 |
| **Export Operations** | - | 12 collections/day | ~$0 |
| **Function Invocations** | - | 30/day | ~$0 |
| **Total** | | | **~$0.30/ay** |

Çok düşük maliyet! ✅

---

## 🔄 RESTORE İŞLEMİ

### **Cloud Console'dan:**
1. Storage → Backup dosyasını seç
2. İndir veya direkt Firestore'a import et

### **CLI'dan:**
```bash
# Export dosyasını indir
gsutil cp -r gs://greenmotion-backups/firestore-backups/20241029_020000 ./

# Firestore'a import et (gerekirse)
# Not: Firestore import direkt yok, manuel restore gerekir
```

---

## ✅ KONTROL LİSTESİ

- [ ] Cloud Storage bucket oluşturuldu
- [ ] Cloud Function yazıldı ve deploy edildi
- [ ] İlk test backup başarılı
- [ ] Scheduled backup çalışıyor (24 saat sonra kontrol et)
- [ ] Backup dosyaları Storage'da görünüyor
- [ ] Eski backup'lar otomatik siliniyor
- [ ] Email bildirimi (opsiyonel) eklendi

---

## 🚨 SORUN GİDERME

### **Problem: Backup çalışmıyor**

**Çözüm:**
```bash
# Function loglarına bak
firebase functions:log

# Permissions kontrol et
gcloud projects get-iam-policy greenmotionapp-33413
```

### **Problem: Storage'a yazamıyor**

**Çözüm:**
1. Cloud Console → IAM → Service Account
2. `appspot.gserviceaccount.com` → Edit
3. "Storage Admin" rolünü ekle

### **Problem: Function deploy olmuyor**

**Çözüm:**
```bash
# Functions çalışıyor mu kontrol et
firebase functions:list

# Billing aktif mi kontrol et
gcloud billing accounts list
```

---

## 📞 DESTEK

Sorun yaşarsan:
1. Function loglarına bak: `firebase functions:log`
2. Cloud Console → Logs Explorer
3. Error mesajlarını kontrol et

---

## 🎉 SONUÇ

Firestore için backup kurulumu tamamlandı! 

**Önerilen:**
1. ✅ Cloud Function ile otomatik günlük backup
2. ✅ Cloud Storage'da arşivle
3. ✅ Ayda bir manuel test et

**Maliyet:** Çok düşük (~$0.30/ay)

**Zaman:** 30 dakika kurulum, sonra otomatik çalışır! 🚀

