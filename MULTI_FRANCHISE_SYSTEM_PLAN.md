# Multi-Franchise System Architecture
## AracHasarKayit - Çoklu Franchise Desteği

---

## 1. Desteklenen Ülkeler (Avrupa)

### Tam Liste

| Kod | Ülke | Plaka Formatı | Örnek |
|-----|------|---------------|-------|
| CH | Switzerland | 1-2 harf + 1-6 rakam | ZH 123456 |
| DE | Germany | 1-3 harf + 1-2 harf + 1-4 rakam | B AB 1234 |
| TR | Turkey | 2 rakam + 1-3 harf + 2-4 rakam | 34 ABC 1234 |
| AT | Austria | 1-2 harf + rakam + harf | W 12345 A |
| FR | France | 2 harf + 3 rakam + 2 harf | AB 123 CD |
| IT | Italy | 2 harf + 3 rakam + 2 harf | AB 123 CD |
| ES | Spain | 4 rakam + 3 harf | 1234 ABC |
| NL | Netherlands | 2 karakter grupları | AB 12 CD |
| BE | Belgium | 1 rakam + 3 harf + 3 rakam | 1 ABC 234 |
| PL | Poland | 2-3 harf + 4-5 rakam/harf | WA 12345 |
| PT | Portugal | 2 harf + 2 rakam + 2 harf | AB 12 CD |
| CZ | Czech Republic | 1-2 harf + 1 rakam + 4 karakter | 1A2 3456 |
| HU | Hungary | 3 harf + 3 rakam | ABC 123 |
| RO | Romania | 1-2 harf + 2-3 rakam + 3 harf | B 123 ABC |
| GR | Greece | 3 harf + 4 rakam | ABC 1234 |
| SE | Sweden | 3 harf + 3 rakam | ABC 123 |
| DK | Denmark | 2 harf + 5 rakam | AB 12345 |
| FI | Finland | 3 harf + 3 rakam | ABC 123 |
| NO | Norway | 2 harf + 5 rakam | AB 12345 |
| IE | Ireland | 3 bölüm | 12 D 1234 |
| UK | United Kingdom | 2 harf + 2 rakam + 3 harf | AB 12 CDE |
| HR | Croatia | 2 harf + 3-4 rakam + 2 harf | ZG 1234 AB |
| SK | Slovakia | 2 harf + 3 rakam + 2 harf | BA 123 AB |
| SI | Slovenia | 2 harf + rakam + harf | LJ 123 AB |
| BG | Bulgaria | 1-2 harf + 4 rakam + 2 harf | A 1234 BC |
| LU | Luxembourg | 2 harf + 4 rakam | AB 1234 |

---

## 2. Login Ekranı

### UI Tasarımı

```
┌─────────────────────────────────────┐
│                                     │
│         [App Logo]                  │
│                                     │
│   Select Country                    │
│   ┌─────────────────────────────┐   │
│   │  🇨🇭 Switzerland           ▼│   │
│   └─────────────────────────────┘   │
│                                     │
│   ┌─────────────────────────────┐   │
│   │  Email                      │   │
│   └─────────────────────────────┘   │
│                                     │
│   ┌─────────────────────────────┐   │
│   │  Password                   │   │
│   └─────────────────────────────┘   │
│                                     │
│   ┌─────────────────────────────┐   │
│   │         LOGIN               │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

### Country Picker (Demo etiketi YOK)

```
┌─────────────────────────────────────┐
│  🇦🇹 Austria                        │
│  🇧🇪 Belgium                        │
│  🇧🇬 Bulgaria                       │
│  🇭🇷 Croatia                        │
│  🇨🇿 Czech Republic                 │
│  🇩🇰 Denmark                        │
│  🇫🇮 Finland                        │
│  🇫🇷 France                         │
│  🇩🇪 Germany                        │
│  🇬🇷 Greece                         │
│  🇭🇺 Hungary                        │
│  🇮🇪 Ireland                        │
│  🇮🇹 Italy                          │
│  🇱🇺 Luxembourg                     │
│  🇳🇱 Netherlands                    │
│  🇳🇴 Norway                         │
│  🇵🇱 Poland                         │
│  🇵🇹 Portugal                       │
│  🇷🇴 Romania                        │
│  🇸🇰 Slovakia                       │
│  🇸🇮 Slovenia                       │
│  🇪🇸 Spain                          │
│  🇸🇪 Sweden                         │
│  🇨🇭 Switzerland                    │
│  🇹🇷 Turkey                         │
│  🇬🇧 United Kingdom                 │
└─────────────────────────────────────┘
```

### Login Flow

```
1. Kullanıcı ülke seçer (normal liste, demo etiketi yok)
2. Email ve password girer
3. Firebase Auth login
4. UserProfile yüklenir (franchiseId, isDemo, demoExpiresAt)
5. Seçilen ülke ile userProfile.franchiseId eşleşir mi kontrol
6. Eğer demo hesabıysa → "30 gün kaldı" bildirimi göster
7. Dashboard'a yönlendir
```

---

## 3. Demo Bildirim Sistemi

### Login Sonrası Otomatik Bildirim

```swift
// AppDelegate veya ContentView.onAppear
func checkDemoStatus() {
    guard let profile = authManager.userProfile else { return }
    
    if profile.isDemo, let expiresAt = profile.demoExpiresAt {
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
        
        if daysRemaining > 0 {
            // Banner göster: "Demo hesabınızın süresi 30 gün sonra dolacak"
            showDemoBanner(daysRemaining: daysRemaining)
        } else {
            // Demo süresi dolmuş - logout yap
            authManager.signOut()
            showExpiredAlert()
        }
    }
}
```

### Demo Banner UI

```
┌─────────────────────────────────────────────────────┐
│ ⚠️ Demo Account - 30 days remaining          [×]   │
└─────────────────────────────────────────────────────┘
```

### Son 7 Gün Uyarısı

```
┌─────────────────────────────────────────────────────┐
│ ⚠️ Demo Account - Only 5 days remaining!     [×]   │
│    Contact sales to upgrade to production.          │
└─────────────────────────────────────────────────────┘
```

---

## 4. Firestore Yapısı

### Franchise Subcollection

```
franchises/
├── ch/                          (Switzerland)
│   ├── info: { ... }
│   ├── araclar/
│   ├── iadeIslemleri/
│   ├── exitIslemleri/
│   └── ...
│
├── de/                          (Germany)
│   └── ...
│
├── tr/                          (Turkey)
│   └── ...
│
└── {countryCode}/               (Diğer ülkeler)
    └── ...
```

### Franchise Info Document

```json
{
  "franchiseId": "de",
  "name": "Green Motion Germany",
  "country": "Germany",
  "countryCode": "DE",
  "plateFormat": "german",
  "currency": "EUR",
  "timezone": "Europe/Berlin",
  "language": "de",
  "isActive": true,
  "createdAt": "Timestamp"
}
```

### User Profile (Güncellenmiş)

```json
{
  "uid": "String",
  "email": "String",
  "firstName": "String",
  "lastName": "String",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp",
  "franchiseId": "String - ch | de | tr | ...",
  "role": "String - admin | manager | staff",
  "isDemo": "Boolean",
  "demoExpiresAt": "Timestamp? (sadece demo için)",
  "createdBy": "String? (admin email)",
  "isActive": "Boolean"
}
```

---

## 5. Plaka Formatları

### PlateFormats Collection

```
Collection: plateFormats
Document ID: countryCode
```

```json
// Document: ch
{
  "countryCode": "CH",
  "name": "Switzerland",
  "flag": "🇨🇭",
  "pattern": "^[A-Z]{1,2}[0-9]{1,6}$",
  "validPrefixes": ["ZH", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR", "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG", "TI", "VD", "VS", "NE", "GE", "JU"],
  "example": "ZH 123456",
  "minLength": 3,
  "maxLength": 8
}

// Document: de
{
  "countryCode": "DE",
  "name": "Germany",
  "flag": "🇩🇪",
  "pattern": "^[A-ZÄÖÜ]{1,3}[A-Z]{0,2}[0-9]{1,4}[EH]?$",
  "validPrefixes": ["B", "M", "K", "F", "HH", "S", "D", "N", "L", "DD", "DU", "E", "..."],
  "example": "B AB 1234",
  "minLength": 4,
  "maxLength": 10
}

// Document: tr
{
  "countryCode": "TR",
  "name": "Turkey",
  "flag": "🇹🇷",
  "pattern": "^[0-9]{2}[A-Z]{1,3}[0-9]{2,4}$",
  "validPrefixes": ["01", "02", "03", "...", "81"],
  "example": "34 ABC 1234",
  "minLength": 7,
  "maxLength": 9
}

// ... diğer ülkeler
```

---

## 6. Web App - Admin User Management

### Konum

```
Web App: /Users/berkaybuyukdere/Desktop/GreenMotionWebApp
Sadece admin@gmail.com erişebilir
Yeni Admin View: AdminUserManagementView
```

### Admin Panel Menüsüne Ekleme

```javascript
// App.js - Admin Section içine ekle
<NavButtonGrid 
    icon={<Users size={18} />} 
    label="User Management" 
    active={currentView === 'adminUserManagement'} 
    onClick={() => setCurrentView('adminUserManagement')} 
/>
```

### AdminUserManagementView Özellikleri

```
┌─────────────────────────────────────────────────────────────────┐
│  User Management                              [+ New User]      │
├─────────────────────────────────────────────────────────────────┤
│  Filter: [All ▼] [All Countries ▼] [Active ▼]    🔍 Search     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Email              │ Name       │ Country │ Demo │ Status │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ user1@company.de   │ Hans M.    │ 🇩🇪 DE   │ Yes  │ Active │  │
│  │ Created: 01.02.2024 │ Updated: 05.02.2024  │ [Edit][Delete]│  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ user2@company.tr   │ Ahmet K.   │ 🇹🇷 TR   │ Yes  │ Active │  │
│  │ Created: 01.02.2024 │ Expires: 01.03.2024  │ [Edit][Delete]│  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ staff@greenmotion.ch│ Peter S.  │ 🇨🇭 CH   │ No   │ Active │  │
│  │ Created: 15.01.2024 │ Updated: 20.01.2024  │ [Edit][Delete]│  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### New User Modal

```
┌─────────────────────────────────────────────────────┐
│  Create New User                              [×]   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Email *                                            │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Password *                                         │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  First Name *                                       │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Last Name *                                        │
│  ┌───────────────────────────────────────────────┐  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Country *                                          │
│  ┌───────────────────────────────────────────────┐  │
│  │  🇩🇪 Germany                               ▼  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Role *                                             │
│  ┌───────────────────────────────────────────────┐  │
│  │  Staff                                    ▼   │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ☑ Demo Account (30 günlük deneme)                 │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐                  │
│  │   Cancel    │  │   Create    │                  │
│  └─────────────┘  └─────────────┘                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Edit User Modal

```
┌─────────────────────────────────────────────────────┐
│  Edit User                                    [×]   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Email (readonly)                                   │
│  ┌───────────────────────────────────────────────┐  │
│  │  user@company.de                              │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  First Name *            Last Name *                │
│  ┌─────────────────┐     ┌─────────────────┐       │
│  │ Hans            │     │ Müller          │       │
│  └─────────────────┘     └─────────────────┘       │
│                                                     │
│  Country *               Role *                     │
│  ┌─────────────────┐     ┌─────────────────┐       │
│  │ 🇩🇪 Germany   ▼ │     │ Staff       ▼   │       │
│  └─────────────────┘     └─────────────────┘       │
│                                                     │
│  Status                                             │
│  ◉ Active   ○ Inactive                             │
│                                                     │
│  Demo Settings                                      │
│  ☑ Demo Account                                    │
│  Expires: [2024-03-01] (editable for demo)         │
│                                                     │
│  ─────────────────────────────────────────────────  │
│  Created: 01.02.2024 10:30 by admin@gmail.com      │
│  Updated: 05.02.2024 14:15 by admin@gmail.com      │
│  ─────────────────────────────────────────────────  │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐                  │
│  │   Cancel    │  │    Save     │                  │
│  └─────────────┘  └─────────────┘                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Firestore - Users Collection

```json
// Collection: users
// Document ID: Firebase Auth UID
{
  "uid": "abc123...",
  "email": "user@company.de",
  "firstName": "Hans",
  "lastName": "Müller",
  "franchiseId": "de",
  "role": "staff",
  "isDemo": true,
  "demoExpiresAt": "Timestamp (30 gün sonra)",
  "convertedFromDemo": false,
  "convertedAt": null,
  "isActive": true,
  "createdAt": "Timestamp",
  "createdBy": "admin@gmail.com",
  "updatedAt": "Timestamp",
  "updatedBy": "admin@gmail.com"
}
```

### Firestore - Franchises Collection (Lisans Yönetimi)

```json
// Collection: franchises
// Document ID: countryCode (ch, de, tr, ...)
{
  "franchiseId": "de",
  "name": "Green Motion Germany",
  "country": "Germany",
  "countryCode": "DE",
  "flag": "🇩🇪",
  
  // License Info
  "maxUsers": 10,
  "currentUserCount": 3,
  "subscriptionType": "standard",
  "subscriptionStartDate": "Timestamp",
  "subscriptionEndDate": "Timestamp",
  
  // Status
  "isDemo": false,
  "isActive": true,
  
  // Tracking
  "createdAt": "Timestamp",
  "createdBy": "admin@gmail.com",
  "updatedAt": "Timestamp",
  "updatedBy": "admin@gmail.com",
  
  // Config
  "plateFormat": "german",
  "currency": "EUR",
  "timezone": "Europe/Berlin",
  "language": "de"
}
```

**Subscription Types:**
| Tip | Kullanıcı Limiti | Açıklama |
|-----|------------------|----------|
| demo | 5 | 30 günlük deneme |
| basic | 5 | Küçük franchise |
| standard | 15 | Orta franchise |
| premium | 50 | Büyük franchise |
| enterprise | Sınırsız | Kurumsal |

### Web App Functions

```javascript
// AdminUserManagementView.js

// Tüm kullanıcıları yükle
const loadUsers = async () => {
    const snapshot = await getDocs(collection(db, 'users'));
    const users = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    setUsers(users);
};

// Yeni kullanıcı oluştur
const createUser = async (userData) => {
    // 1. Firebase Auth'da kullanıcı oluştur
    const userCredential = await createUserWithEmailAndPassword(
        auth, 
        userData.email, 
        userData.password
    );
    
    // 2. Firestore'da profil oluştur
    const profile = {
        uid: userCredential.user.uid,
        email: userData.email,
        firstName: userData.firstName,
        lastName: userData.lastName,
        franchiseId: userData.countryCode.toLowerCase(),
        role: userData.role,
        isDemo: userData.isDemo,
        demoExpiresAt: userData.isDemo 
            ? Timestamp.fromDate(addDays(new Date(), 30)) 
            : null,
        isActive: true,
        createdAt: Timestamp.now(),
        createdBy: 'admin@gmail.com',
        updatedAt: Timestamp.now(),
        updatedBy: 'admin@gmail.com'
    };
    
    await setDoc(doc(db, 'users', userCredential.user.uid), profile);
};

// Kullanıcı güncelle
const updateUser = async (userId, updates) => {
    await updateDoc(doc(db, 'users', userId), {
        ...updates,
        updatedAt: Timestamp.now(),
        updatedBy: 'admin@gmail.com'
    });
};

// Kullanıcı sil (soft delete - isActive = false)
const deleteUser = async (userId) => {
    await updateDoc(doc(db, 'users', userId), {
        isActive: false,
        updatedAt: Timestamp.now(),
        updatedBy: 'admin@gmail.com'
    });
    
    // Opsiyonel: Firebase Auth'dan da sil
    // Bu admin SDK gerektirir - Cloud Function ile yapılabilir
};

// Real-time listener
useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'users'), (snapshot) => {
        const users = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        setUsers(users);
    });
    return () => unsubscribe();
}, []);
```

---

## 7. Firestore Security Rules

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    
    function isAdmin() {
      return request.auth != null && request.auth.token.email == 'admin@gmail.com';
    }
    
    function getUserFranchise() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.franchiseId;
    }
    
    function belongsToFranchise(franchiseId) {
      return request.auth != null && getUserFranchise() == franchiseId;
    }
    
    function isActiveUser() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isActive == true;
    }
    
    function isDemoNotExpired() {
      let userData = get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
      return !userData.isDemo || userData.demoExpiresAt > request.time;
    }
    
    // Users collection - admin full access, users read own
    match /users/{userId} {
      allow read: if request.auth != null && (request.auth.uid == userId || isAdmin());
      allow write: if isAdmin();
    }
    
    // Franchises info - readable by all authenticated
    match /franchises/{franchiseId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
    
    // Franchise data - only for users of that franchise
    match /franchises/{franchiseId}/{collection}/{document=**} {
      allow read, write: if belongsToFranchise(franchiseId) 
                         && isActiveUser() 
                         && isDemoNotExpired();
    }
    
    // Plate formats - readable by all
    match /plateFormats/{countryCode} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
  }
}
```

---

## 8. Cloud Function - Demo Cleanup

```javascript
// functions/index.js

const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');

// Her gün 00:00'da çalışır
exports.cleanupExpiredDemos = functions.scheduler.onSchedule('0 0 * * *', async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    
    // Süresi dolmuş demo kullanıcıları bul
    const expiredUsers = await db.collection('users')
        .where('isDemo', '==', true)
        .where('demoExpiresAt', '<', now)
        .where('isActive', '==', true)
        .get();
    
    for (const userDoc of expiredUsers.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        const franchiseId = userData.franchiseId;
        
        console.log(`Deactivating expired demo user: ${userData.email}`);
        
        // Kullanıcıyı deaktif et
        await userDoc.ref.update({
            isActive: false,
            updatedAt: admin.firestore.Timestamp.now(),
            updatedBy: 'system-cleanup'
        });
        
        // Opsiyonel: Franchise verilerini temizle
        // await deleteCollection(`franchises/${franchiseId}/araclar`);
        // ...
    }
    
    console.log(`Cleaned up ${expiredUsers.size} expired demo users`);
});

// Demo süresi dolmak üzere olan kullanıcılara email gönder
exports.sendDemoExpirationWarning = functions.scheduler.onSchedule('0 9 * * *', async () => {
    const db = admin.firestore();
    const now = new Date();
    const sevenDaysLater = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    
    const expiringUsers = await db.collection('users')
        .where('isDemo', '==', true)
        .where('demoExpiresAt', '<=', admin.firestore.Timestamp.fromDate(sevenDaysLater))
        .where('demoExpiresAt', '>', admin.firestore.Timestamp.now())
        .where('isActive', '==', true)
        .get();
    
    for (const userDoc of expiringUsers.docs) {
        const userData = userDoc.data();
        // Email gönder (SendGrid, Mailgun, vs.)
        console.log(`Warning email to: ${userData.email}`);
    }
});
```

---

## 9. Franchise Dashboard (Admin Panel)

### Ana Dashboard UI

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Franchise Management                               [+ New Franchise]   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Overview: 5 Active Franchises | 23 Total Users | 3 Demo Accounts      │
│                                                                         │
│  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐ │
│  │ 🇨🇭 Switzerland     │  │ 🇩🇪 Germany         │  │ 🇹🇷 Turkey          │ │
│  │                    │  │                    │  │                    │ │
│  │ Users: 12/50       │  │ Users: 3/10        │  │ Users: 2/5         │ │
│  │ ████████░░░░ 24%   │  │ ███░░░░░░░░ 30%    │  │ ████░░░░░░ 40%     │ │
│  │                    │  │                    │  │                    │ │
│  │ [Production]       │  │ [Demo] 25 days     │  │ [Demo] 18 days     │ │
│  │ Premium            │  │ Standard           │  │ Basic              │ │
│  │                    │  │                    │  │                    │ │
│  │ [View] [Edit]      │  │ [View] [Edit]      │  │ [View] [Edit]      │ │
│  └────────────────────┘  └────────────────────┘  └────────────────────┘ │
│                                                                         │
│  ┌────────────────────┐  ┌────────────────────┐                        │
│  │ 🇫🇷 France          │  │ 🇮🇹 Italy           │                        │
│  │                    │  │                    │                        │
│  │ Users: 0/10        │  │ Users: 6/15        │                        │
│  │ ░░░░░░░░░░░░ 0%    │  │ █████░░░░░░ 40%    │                        │
│  │                    │  │                    │                        │
│  │ [Inactive]         │  │ [Production]       │                        │
│  │ Standard           │  │ Standard           │                        │
│  │                    │  │                    │                        │
│  │ [Activate]         │  │ [View] [Edit]      │                        │
│  └────────────────────┘  └────────────────────┘                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Franchise Detail View

```
┌─────────────────────────────────────────────────────────────────────────┐
│  ← Back to Dashboard    🇩🇪 Germany                   [Edit Franchise]  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  LICENSE INFORMATION                                            │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │  Plan: Standard          │  Status: Demo                       │   │
│  │  Max Users: 10           │  Current Users: 3                   │   │
│  │  Available Slots: 7      │  Demo Expires: 01.03.2024 (25 days) │   │
│  │                          │                                     │   │
│  │  [Upgrade Plan]  [Convert to Production]  [Extend Demo]        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  Users (3/10)                                           [+ Add User]   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Email              │ Name      │ Role  │ Type   │ Actions       │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │ hans@company.de    │ Hans M.   │ Admin │ Demo   │[Convert][Edit]│   │
│  │ Created: 01.02.24  │           │       │ 25d    │               │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │ anna@company.de    │ Anna K.   │ Staff │ Demo   │[Convert][Edit]│   │
│  │ Created: 03.02.24  │           │       │ 25d    │               │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │ max@company.de     │ Max S.    │ Staff │ Regular│ [Edit][Delete]│   │
│  │ Created: 05.02.24  │ Converted │       │        │               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Demo to Regular Conversion

### Conversion Modal

```
┌─────────────────────────────────────────────────────────────────┐
│  Convert Demo User to Regular                             [×]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ⚠️ This action will:                                          │
│                                                                 │
│  • Remove demo expiration date                                  │
│  • Convert user to regular subscription                         │
│  • User data will be permanently retained                       │
│                                                                 │
│  User: hans@company.de                                          │
│  Franchise: 🇩🇪 Germany                                         │
│  Current Demo Expires: 01.03.2024 (25 days remaining)          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │    Cancel    │  │   Convert    │                            │
│  └──────────────┘  └──────────────┘                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Conversion Function

```javascript
// Demo kullanıcıyı normal kullanıcıya dönüştür
const convertDemoToRegular = async (userId) => {
    const userRef = doc(db, 'users', userId);
    
    await updateDoc(userRef, {
        isDemo: false,
        demoExpiresAt: null,
        convertedFromDemo: true,
        convertedAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
        updatedBy: 'admin@gmail.com'
    });
    
    // Franchise demo kontrolü de güncellenebilir
    // Eğer tüm kullanıcılar regular ise, franchise de production olabilir
};
```

---

## 11. License Enforcement

### Kullanıcı Ekleme Kontrolü

```javascript
const addUserToFranchise = async (franchiseId, userData) => {
    // 1. Franchise bilgilerini al
    const franchiseDoc = await getDoc(doc(db, 'franchises', franchiseId));
    const franchise = franchiseDoc.data();
    
    // 2. Kota kontrolü
    if (franchise.currentUserCount >= franchise.maxUsers) {
        throw new Error(`User limit reached for ${franchise.name}. 
            Current: ${franchise.currentUserCount}/${franchise.maxUsers}. 
            Please upgrade the subscription.`);
    }
    
    // 3. Kullanıcı oluştur
    const userCredential = await createUserWithEmailAndPassword(
        auth, userData.email, userData.password
    );
    
    // 4. Firestore profil
    await setDoc(doc(db, 'users', userCredential.user.uid), {
        ...userData,
        franchiseId: franchiseId,
        createdAt: Timestamp.now(),
        createdBy: 'admin@gmail.com'
    });
    
    // 5. Franchise user count güncelle
    await updateDoc(doc(db, 'franchises', franchiseId), {
        currentUserCount: increment(1),
        updatedAt: Timestamp.now()
    });
};
```

### Cloud Function - User Count Sync

```javascript
// Kullanıcı oluşturulduğunda
exports.onUserCreated = functions.firestore
    .document('users/{userId}')
    .onCreate(async (snap, context) => {
        const userData = snap.data();
        const franchiseId = userData.franchiseId;
        
        await admin.firestore()
            .collection('franchises')
            .doc(franchiseId)
            .update({
                currentUserCount: admin.firestore.FieldValue.increment(1)
            });
    });

// Kullanıcı silindiğinde/deaktif edildiğinde
exports.onUserDeleted = functions.firestore
    .document('users/{userId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();
        
        // Aktif → İnaktif geçiş kontrolü
        if (before.isActive === true && after.isActive === false) {
            await admin.firestore()
                .collection('franchises')
                .doc(after.franchiseId)
                .update({
                    currentUserCount: admin.firestore.FieldValue.increment(-1)
                });
        }
    });
```

---

## 12. Özet

```
✅ 26 Avrupa ülkesi destekleniyor
✅ Login'de sadece ülke seçimi (demo etiketi yok)
✅ Demo hesaplarda otomatik "X gün kaldı" bildirimi
✅ Her franchise kendi verilerini görür
✅ Plaka formatları ülkeye göre değişir
✅ Admin Panel - Franchise Dashboard
   - Tüm franchise'ları görüntüleme
   - Kullanıcı sayısı / maksimum kota görüntüleme
   - Subscription plan yönetimi
✅ Franchise içinde direkt kullanıcı oluşturma
✅ Demo kullanıcıyı normal kullanıcıya dönüştürme
✅ Kullanıcı kota kontrolü (maxUsers limiti)
✅ Kayıt ve güncelleme tarihleri görüntülenebilir
✅ Tüm değişiklikler Firebase'de otomatik güncellenir
✅ Demo süresi dolunca otomatik deaktivasyon
✅ Cloud Functions ile user count senkronizasyonu
```

---

## 13. Implementation Sırası

### Phase 1: Database Setup
1. `franchises` collection oluştur (lisans bilgileri dahil)
2. `plateFormats` collection oluştur (26 Avrupa ülkesi)
3. `users` collection şemasını güncelle (convertedFromDemo, etc.)
4. CH franchise'ı production olarak ekle
5. Mevcut verileri `franchises/ch/` altına taşı

### Phase 2: Web App - Franchise Dashboard
1. `AdminFranchiseDashboard.js` component oluştur
   - Franchise grid görünümü
   - User count / max users progress bar
   - Demo / Production badge
2. `AdminFranchiseDetailView.js` component oluştur
   - Franchise detay bilgileri
   - O franchise'a ait kullanıcı listesi
   - Add user (franchise bağlamında)
   - Demo to Regular conversion butonu
3. `AdminUserManagementView.js` component oluştur
   - Tüm kullanıcılar listesi (franchise filtresi)
   - CRUD operasyonları
   - Kayıt/güncelleme tarihleri
4. App.js'e admin menü + routes ekle
5. License enforcement (kota kontrolü)
6. Real-time listeners

### Phase 3: iOS App Updates
1. `Country.swift` model (26 Avrupa ülkesi)
2. `FranchiseManager.swift` ekle
3. Login ekranına ülke seçici ekle
4. Demo banner sistemi ekle (kalan gün gösterimi)
5. `FirebaseService.getCollectionReference` güncelle
6. `Validators.swift` multi-country plate validation

### Phase 4: Cloud Functions
1. `cleanupExpiredDemos` - Günlük scheduled cleanup
2. `onUserCreated` - Franchise user count artır
3. `onUserDeleted` - Franchise user count azalt
4. `sendDemoExpirationWarning` - Email uyarısı

### Phase 5: Security Rules
1. Firestore rules güncelle (franchise isolation)
2. Storage rules güncelle
3. License limit enforcement

### Phase 6: Testing & Deploy
1. Web App test (franchise dashboard, user management)
2. iOS App test (login flow, demo banner)
3. Web App deploy
4. iOS App Store update
5. Demo franchise'ları oluştur (DE, TR)
6. Demo kullanıcıları oluştur
