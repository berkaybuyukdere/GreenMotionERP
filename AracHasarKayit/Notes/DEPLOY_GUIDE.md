# 🚀 Firebase Hosting Deploy Kılavuzu

## 📋 Ön Gereksinimler

✅ Node.js yüklü olmalı
✅ Firebase projesi oluşturulmuş olmalı
✅ React uygulaması hazır olmalı

## 🔧 Adım 1: Firebase CLI Kurulumu

```bash
# Firebase CLI'ı global olarak yükle
npm install -g firebase-tools

# Kurulumu kontrol et
firebase --version
```

## 🔑 Adım 2: Firebase'e Giriş Yap

```bash
# Firebase hesabına giriş yap
firebase login

# Başarılı olursa "Success! Logged in as [your-email]" göreceksiniz
```

## 📦 Adım 3: React Projesini Hazırla

```bash
# Proje dizinine git
cd ~/green-motion-web

# Eğer henüz paketleri yüklemediyseniz:
npm install

# Production build al
npm run build

# Build klasörü oluşacak (bu Firebase'e deploy edilecek)
```

## 🎯 Adım 4: Firebase Projesini Başlat

```bash
# Proje dizininde Firebase'i başlat
firebase init

# Açılan menüde:
# 1. Space ile "Hosting" seçeneğini seç (ok işareti görünecek)
# 2. Enter'a bas

# "Use an existing project" seç
# 3. Projenizi seçin: greenmotionapp-33413

# Sorular:
# ? What do you want to use as your public directory? 
#   Cevap: build

# ? Configure as a single-page app (rewrite all urls to /index.html)?
#   Cevap: Yes (y)

# ? Set up automatic builds and deploys with GitHub?
#   Cevap: No (n)

# ? File build/index.html already exists. Overwrite?
#   Cevap: No (n)
```

## 🚀 Adım 5: Deploy Et!

```bash
# Firebase'e deploy et
firebase deploy

# Veya sadece hosting'i deploy et:
firebase deploy --only hosting

# Deploy başarılı olursa şuna benzer bir çıktı göreceksiniz:
# ✔  Deploy complete!
# 
# Project Console: https://console.firebase.google.com/project/greenmotionapp-33413/overview
# Hosting URL: https://greenmotionapp-33413.web.app
```

## 🎊 TAMAMLANDI!

Uygulamanız şu adreste yayında:
- **Live URL**: https://greenmotionapp-33413.web.app
- **Alt Domain**: https://greenmotionapp-33413.firebaseapp.com

---

## 📝 Otomatik Deploy Scriptleri

Daha kolay deploy için `package.json`'a ekleyin:

```json
{
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "deploy": "npm run build && firebase deploy",
    "deploy:hosting": "npm run build && firebase deploy --only hosting"
  }
}
```

Artık tek komutla deploy edebilirsiniz:
```bash
npm run deploy
```

---

## 🔄 Güncelleme Yapmak İçin

Her güncelleme sonrası:

```bash
# 1. Değişiklikleri yap (kod düzenle)

# 2. Build al
npm run build

# 3. Deploy et
firebase deploy

# VEYA tek komutla:
npm run deploy
```

---

## 🌐 Custom Domain Eklemek

Firebase Console'dan:

1. **Firebase Console** → **Hosting** → **Add custom domain**
2. Domain adınızı girin (örn: greenmotion.ch)
3. DNS kayıtlarını ekleyin
4. SSL otomatik sağlanır ✅

---

## 🛠️ Faydalı Komutlar

```bash
# Hosting bilgilerini görüntüle
firebase hosting:channel:list

# Yerel test et (Firebase emulator)
firebase emulators:start

# Deploy geçmişini görüntüle
firebase hosting:releases:list

# Belirli bir versiyonu geri al
firebase hosting:clone SOURCE_SITE:SOURCE_CHANNEL DESTINATION_SITE:DESTINATION_CHANNEL

# Önizleme kanalı oluştur (staging için)
firebase hosting:channel:deploy preview

# Deploy'u geri al (son versiyona dön)
firebase hosting:rollback
```

---

## 📊 Firebase.json Yapılandırması

Eğer manuel oluşturmak isterseniz `firebase.json`:

```json
{
  "hosting": {
    "public": "build",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=31536000"
          }
        ]
      },
      {
        "source": "**/*.@(js|css)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=31536000"
          }
        ]
      }
    ]
  }
}
```

---

## 🔐 Güvenlik Kuralları

`firestore.rules` (Firestore için):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Kullanıcılar sadece kendi verilerine erişebilir
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Giriş yapmış kullanıcılar tüm verileri okuyabilir/yazabilir
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

`storage.rules` (Storage için):

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.resource.size < 10 * 1024 * 1024; // Max 10MB
    }
  }
}
```

Deploy et:
```bash
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
```

---

## 🐛 Sorun Giderme

### Problem: "Firebase command not found"
```bash
npm install -g firebase-tools
```

### Problem: "Permission denied"
```bash
sudo npm install -g firebase-tools
```

### Problem: Build hatası
```bash
# Node modules'ları temizle ve yeniden yükle
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Problem: Deploy hatası
```bash
# Firebase logout/login yap
firebase logout
firebase login

# Projeyi yeniden seç
firebase use greenmotionapp-33413

# Deploy et
firebase deploy
```

---

## 📱 Preview Link (Test İçin)

Canlıya almadan önce test etmek için:

```bash
# Preview kanalı oluştur
firebase hosting:channel:deploy staging

# Output:
# ✔  Channel URL (staging): https://greenmotionapp-33413--staging-xxxxx.web.app
```

Test ettikten sonra canlıya al:
```bash
firebase deploy
```

---

## 🎯 Tam Deploy Sırası

```bash
# 1. Projeye git
cd ~/green-motion-web

# 2. Güncellemeleri çek (varsa)
git pull

# 3. Paketleri güncelle
npm install

# 4. Build al
npm run build

# 5. Test et (opsiyonel)
firebase emulators:start

# 6. Deploy et
firebase deploy

# 7. Test et
# Tarayıcıda: https://greenmotionapp-33413.web.app
```

---

## 🎉 Deploy Başarılı!

Uygulamanız artık canlıda:
- **URL**: https://greenmotionapp-33413.web.app
- **Console**: https://console.firebase.google.com/project/greenmotionapp-33413

**Paylaşın, kullanın, keyfini çıkarın! 🚀**

---

## 📈 Monitoring & Analytics

Firebase Console'dan:
- **Performance Monitoring** → Sayfa yükleme süreleri
- **Analytics** → Kullanıcı davranışları
- **Crashlytics** → Hata raporları (web için Firebase App Distribution)

---

## 💡 İpuçları

1. **Her deploy öncesi test edin** → `npm start` ile local test
2. **Build dosyasını git'e eklemeyin** → `.gitignore`'a `build/` ekli olsun
3. **Environment variables kullanın** → `.env` dosyası oluşturun
4. **CI/CD kurun** → GitHub Actions ile otomatik deploy
5. **Custom domain ekleyin** → Profesyonel görünüm

---

## 🔗 Faydalı Linkler

- Firebase Console: https://console.firebase.google.com
- Firebase Docs: https://firebase.google.com/docs/hosting
- React Docs: https://react.dev
- Tailwind CSS: https://tailwindcss.com

---

**Hazırlayan**: Claude Sonnet 4.5 🤖
**Proje**: Green Motion AG - Zurich 🇨🇭
**Tarih**: 2025 ✨


