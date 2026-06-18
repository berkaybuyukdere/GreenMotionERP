# Multi-Franchise & Roller — Master Plan (iOS + Web)

**Versiyon:** 1.1 (review düzeltmeleri)  
**Tarih:** 2026-05-28  
**Amaç:** Firebase Rules’ı bozmadan, tüm platformlarda (iOS + Web ERP) rollerin ve franchise sınırlarının **aynı anlama** gelmesini sağlamak; multi-franchise mimarisini tek referans altında toplamak.

**İlgili dokümanlar (mevcut):**
- `docs/FRANCHISE_DATA_GOVERNANCE.md` — veri yolları, deploy sırası
- `docs/PR_CHECKLIST_FRANCHISE.md` — PR kontrol listesi
- `firestore.rules` — **kaynak gerçeği (güvenlik)**
- `storage.rules` — Storage (şu an Firestore kadar sıkı değil)
- `AracHasarKayit/Utilities/OptimizationFeatureFlags.swift` — `FranchiseCapabilityMatrix` (ürün özellikleri)
- `AracHasarKayit/Firebase/AuthenticationManager.swift` — roller + `UserProfile` yetki yardımcıları
- Web kaynak (ayrı repo): `GreenMotionWebApp/green-motion-web/src/utilities/roleScope.js`, `firebaseHelpers.js`

---

## 1. Temel ilkeler (bozulmaması gerekenler)

| # | İlke | Açıklama |
|---|------|----------|
| P1 | **Rules önce** | Yeni özellik veya rol: önce `firestore.rules` / Functions, sonra istemci. İstemci gizleme ≠ güvenlik. |
| P2 | **Tek franchise oturumu** | Operasyonel okuma/yazma `franchises/{FRANCHISE_ID}/…` altında; oturum franchise’ı `FirebaseService.currentFranchiseId` (iOS) ve web session franchise ile aynı olmalı. |
| P3 | **Globaladmin ≠ Superadmin** | **Cross-franchise bypass** yalnızca `globaladmin` veya `roleScope.level == global`. `superadmin` yükseltilmiş ama **franchise kapsamlı** (legacy read + admin koleksiyonları). |
| P4 | **Ürün ≠ Yetki** | Ülke/franchise özellikleri (`FranchiseCapabilityMatrix`) ile RBAC (`UserProfile` / rules) ayrı katman; karıştırılmaz. |
| P5 | **Parite iOS ↔ Web** | `roleScope`, `GLOBAL_COLLECTIONS`, scoped path, `resolvedFranchiseIdForDataAccess` / `resolveRoleScope` aynı PR veya eşzamanlı kardeş PR ile güncellenir. |
| P6 | **Kök koleksiyon dondurma** | Legacy kök (`/araclar`, `/exitIslemleri`, …) yazma kapalı; yeni veri scoped path’e. |
| P7 | **Deploy sırası** | Migration → uygulama kodu → `firestore.rules` → `storage.rules` → Functions (bkz. `docs/FIREBASE_RULES_DEPLOY_SEQUENCE.md`). |

---

## 2. Platform katmanları (mimari)

```mermaid
flowchart TB
    subgraph clients [İstemciler]
        iOS[iOS SwiftUI]
        Web[Web ERP React - green-motion-web]
        Public[public/*.html müşteri formları]
    end

    subgraph session [Oturum çözümlemesi]
        Auth[users/{uid} profil]
        Scope[roleScope + franchiseMemberships]
        Resolve[resolvedFranchiseId / currentFranchiseId]
    end

    subgraph product [Ürün kapıları - istemci]
        Matrix[FranchiseCapabilityMatrix]
        Tabs[MainTabRouter]
        ProfileHelpers[UserProfile can*]
    end

    subgraph security [Güvenlik - sunucu]
        FS[firestore.rules]
        ST[storage.rules]
        CF[Cloud Functions]
    end

    iOS --> Resolve
    Web --> Resolve
    Resolve --> Auth
    Resolve --> Scope
    iOS --> Matrix
    Web --> Matrix
    iOS --> ProfileHelpers
    Web --> ProfileHelpers
    iOS --> FS
    Web --> FS
    iOS --> ST
    CF --> FS
    Public --> FS
```

**Veri yolu standardı:**

| Veri türü | Path |
|-----------|------|
| Franchise operasyonel | `franchises/{FRANCHISE_ID}/{collection}/{docId}` |
| Global / paylaşılan | Kök: `users`, `franchises`, `smtpConfigurations`, `outgoingEmails`, `plateFormats`, … (bkz. governance doc) |

---

## 3. Rol sözlüğü (canonical)

Firestore `users.role` ve iOS `UserRole` ile hizalı:

| Rol | Kapsam (varsayılan) | Firestore franchise bypass | Tipik UI (iOS) |
|-----|---------------------|----------------------------|----------------|
| `globaladmin` | Tüm franchise’lar | Evet (`isGlobalAdminRole`) | Ülke/franchise seçici, tüm veri |
| `superadmin` | Platform; dokümanda franchiseId | **Hayır** (scoped) | Admin panel, elevated read |
| `admin` | Tek franchise (franchise admin) | Hayır | CH Panel, kategori yönetimi, duyuru |
| `manager` | Tek franchise | Hayır | Operasyon, duyuru yayınlama, ekip saatleri |
| `staff` | Tek franchise | Hayır | Günlük operasyon |
| `shuttle` | CH shuttle | Hayır | Shuttle girişleri (staff benzeri) |
| `viewer` | Tek franchise | Hayır* | *Rules’da staff ile aynı yazma — düzeltilmeli |
| `garage` | CH servis portalı | Kısıtlı (`garageServiceJobs`) | Garage portal sekmesi |

\* **Bilinen borç:** `viewer` için rules “full franchise write” yorumu; ürün niyeti read-only ise rules + UI güncellenmeli.

### 3.1 `roleScope` (birincil kapsam modeli)

`users.roleScope` (ve legacy: `scopeLevel`, `franchiseMemberships`, `defaultFranchiseId`, `countryCode`, `franchiseId`):

| `roleScope.level` | Anlam | Login |
|-------------------|-------|-------|
| `global` | Tüm ülkeler/franchise’lar | Ülke + franchise picker (`globaladmin` veya `roleScope.level == global` — `isGlobalAdminRole()`) |
| `country` | Bir ülkedeki tüm şubeler | Şube listesi / `country_all` |
| `franchise` | Explicit liste veya tek `franchiseId` | Tek veya seçili şube |

**iOS çözümleme:** `UserProfile.resolvedFranchiseIdForDataAccess()` → `AracViewModel.syncFranchiseContext()` → `FirebaseService.setFranchiseContext(franchiseId:)`.

**Web çözümleme:** `roleScope.js#resolveRoleScope` + session franchise (dokümantasyon; kaynak bu repoda değil).

### 3.2 Platform operatör matrisi (superadmin vs globaladmin)

| Yetki | `globaladmin` | `superadmin` | Franchise `admin` |
|-------|---------------|--------------|-------------------|
| Cross-franchise Firestore okuma/yazma (scoped `franchises/{id}/…`) | Evet (`isGlobalAdminRole`) | Hayır (`userMatchesFranchiseId` / `hasScopedFranchiseAccess`) | Hayır |
| Legacy kök koleksiyon read (`/araclar`, …) | Evet (`isElevatedAdmin`) | Evet (`isElevatedAdmin`) | Hayır |
| `users` koleksiyonu **doğrudan** read/list/write | Evet (`isGlobalAdminOnly`) | Hayır | Hayır |
| Franchise kullanıcı yönetimi | Evet (Functions + globaladmin) | Hayır* (Functions: trial/assign/create vb.; **Firestore `users` list/read değil**) | Hayır (Functions; doğrudan `users` write yok) |
| Franchise admin panel (CH) — iOS `canAccessFranchiseAdminPanel` | Evet | Evet | Evet |
| iOS Admin Panel `users` dizini (`isElevatedAdmin` UI) | Evet | UI açık, **Firestore list/read yalnızca globaladmin** | Kapalı |
| `smtpConfigurations` Firestore write | Evet (`isElevatedAdmin`) | Evet | Evet (franchise `admin`/`manager`, `canAccessFranchise`) |
| iOS Settings SMTP formu | — | **Yok** (bölüm kaldırıldı; SMTP Firestore + gönderim akışı) | **Yok** |

\* `superadmin` için kullanıcı işlemleri yalnızca izin verilen Cloud Functions üzerinden; `users` koleksiyonuna globaladmin gibi doğrudan erişim yok.

**Ülke kapısı (login):** `bypassesCountryGate` / `isCrossFranchisePlatformOperator` yalnızca `globaladmin` veya `roleScope.level == global` için geçerlidir. **`superadmin` tek başına ülke kapısını bypass etmez** (oturum `users.franchiseId` / `roleScope` ile sınırlı kalır).

---

## 4. `UserProfile` — tek RBAC yüzeyi (iOS; web’e mirror)

**Tanımlı:** `AuthenticationManager.swift` — yeni kontroller buraya eklenir, view’larda dağınık `role == .manager || …` kullanılmaz.

| Property | Roller | Kullanım |
|----------|--------|----------|
| `isElevatedAdmin` | superadmin, globaladmin | SMTP, elevated health |
| `canAccessFranchiseAdminPanel` | + admin | CH Panel, Jarvis, shuttle modülü kapısı |
| `canPublishAnnouncements` | manager+ | Duyuru CRUD |
| `canManageVehicleCategories` | manager+ | Kategori / toplu silme |
| `isCrossFranchisePlatformOperator` | globaladmin, roleScope.global | Login ülke kapısı bypass |
| `isGaragePortalUser` | garage + CH | Garage portal |

**Eklenecek (önerilen konsolidasyon):**

```swift
// Örnek — tekrarlayan 6+ view kontrolünü birleştirmek için
var canAccessOfficeFinancialHubs: Bool {
    role == .manager || role == .admin || role == .superadmin || role == .globaladmin
}
```

**Kaldırılacak / düzeltilecek:**
- `FirebaseService.currentHasCrossFranchiseAccess` — set ediliyor, **hiç okunmuyor**; ya kaldır ya da yalnızca `isCrossFranchisePlatformOperator` ile sorgu bypass’ına bağla (dikkatli; rules ile uyum şart).

---

## 5. Ülke / franchise ürün matrisi (`FranchiseCapabilityMatrix`)

**Kaynak:** `OptimizationFeatureFlags.swift` — **session franchise** (`FirebaseService.currentFranchiseId`), profil `countryCode` tek başına TR özelliklerini açmaz.

| Özellik | TR | CH | DE | Rules hizası |
|---------|----|----|-----|--------------|
| Operations hub | ✓ | — | — | TR scoped |
| Parked checkouts UI | ✓ | ✓ | ✓ | — |
| Office operations (fuel/POS) | ✓ | ✓ | ✓ | TR+CH+DE |
| Office returns | ✓ | ✓ | — | TR+CH (DE rules’ta yok) |
| Police / traffic contracts | — | ✓ | — | CH |
| Checkout/return customer email (iOS UI) | ✓ | — | ✓ | Functions: checkout allow-list TR+DE; return queue’da aynı gate **yok** (bkz. not) |
| Serial photo capture | ✓ | — | — | TR |
| CH Admin panel tab | — | ✓* | — | *+ `canAccessFranchiseAdminPanel` |
| File library / announcements UI | — | ✓ | — | CH franchise |
| Shuttle module | — | ✓* | — | *admin panel erişimi |
| Swiss-style PDF | — | ✓ | ✓ | — |
| Garage portal | — | ✓** | — | **garage role |

**Not (Functions):** `checkoutEmailAllowedFranchise` yalnızca **checkout** kuyruğunda uygulanır; **return** kuyruğu için aynı franchise gate şu an yok — iOS matrisi TR+DE gösterse bile sunucu paritesi ayrı PR ile hizalanmalı.

**Web paritesi:** Aynı tablo `roleScope.js` yanında bir `franchiseCapabilities.js` (veya mevcut web eşdeğeri) ile paylaşılmalı; hard-coded `CH`/`TR` view içi kontroller taranmalı.

---

## 6. Firebase Rules — koruma rehberi

### 6.1 Firestore (sıkı — referans)

**Dosya:** `firestore.rules`

| Helper grubu | Amaç |
|--------------|------|
| `isGlobalAdminRole`, `userMatchesFranchiseId`, `hasScopedFranchiseAccess` | Franchise izolasyonu |
| `hasFranchiseRead/Write/DeleteAccess` | Doküman `franchiseId` alanı |
| `scopedRestrictedOfficeCollection` | Ülkeye göre office koleksiyonları |
| `userRoleIsGarage`, `garageServiceJobs` | Garage portal |
| `isAnnouncementPublisher` | Duyuru |
| `isGlobalAdminOnly` | `users` privileged writes |

### 6.1.1 `isAdmin()` (Firestore) ≠ `canAccessFranchiseAdminPanel` (iOS)

| | Firestore `isAdmin()` | iOS `UserProfile.canAccessFranchiseAdminPanel` |
|--|----------------------|-----------------------------------------------|
| Tanım | `users.role == 'admin'` | `superadmin` \| `globaladmin` \| `admin` |
| Örnek | `franchises/{id}` doc write: `isAdmin() \|\| isSuperAdminOnly()` | CH Panel, Jarvis, shuttle modülü kapısı |

`manager` / `staff` / `shuttle` / `viewer` / `garage` için `isAdmin()` **false**dır.

**Değişiklik yaparken:**
1. Yeni koleksiyon → scoped path mi, global mi karar ver.
2. `match /franchises/{franchiseId}/…` içine ekle; `hasScopedFranchiseAccess(franchiseId)` kullan.
3. Ülkeye özel ürün → `isTurkeyFranchiseId` / `officeOperationsAllowedFranchise` ile hizala.
4. `superadmin`’e global bypass **ekleme** (bilinçli mimari ayrım).

### 6.2 Storage (gevşek — bilinen risk)

**Dosya:** `storage.rules`

- `franchises/{franchiseId}/**` → şu an **tüm authenticated** kullanıcılar read/write.
- `inOwnFranchise()` tanımlı ama **kullanılmıyor**.
- PDF upload güvenliği kısmen `uploadOperationPdfForEmail` (`callerCanWriteFranchiseStorage`) ile.

**Hedef faz (rules bozmadan kademeli):**
1. Yeni path’lerde `inOwnFranchise(franchiseId)` veya token/custom claim.
2. Legacy kök path’lerde write deny (mevcut).
3. iOS/web aynı path convention: `franchises/{id}/checkout_pdfs|return_pdfs|…`

### 6.3 Cloud Functions

**Dosya:** `functions/index.js`

| İş | Rol / erişim kontrolü |
|----|------------------------|
| `uploadOperationPdfForEmail` | `globaladmin` **veya** `users.franchiseId` / `roleScope.franchiseIds` eşleşmesi (`callerCanWriteFranchiseStorage`) — `superadmin` cross-franchise değil |
| Checkout customer email (queued) | Franchise allow-list: **TR + DE** (`checkoutEmailAllowedFranchise`); rol kontrolü yok |
| Return customer email (queued) | **Franchise allow-list yok** (yalnızca checkout’ta gate); iOS UI TR+DE (`returnCustomerEmailEnabledForSession`) |
| `assignUserRoles`, trial callables | `superadmin` only |
| `adminDeleteUserCompletely` | `superadmin` veya `globaladmin` |
| Migration / parity (seçili) | `superadmin` **veya** `globaladmin` |

Yeni callable: `callerCanAccessFranchise(franchiseId)` helper’ını rules mantığıyla paylaş (tek JS modül).

---

## 7. iOS uygulama düzeni (standartlar)

### 7.1 Oturum senkronu

```
Login → UserProfile yüklendi
  → resolvedFranchiseIdForDataAccess()
  → AracViewModel.syncFranchiseContext()
  → FirebaseService.setFranchiseContext(
       franchiseId:,
       hasCrossFranchiseAccess: profile.isCrossFranchisePlatformOperator
     )
  → Listener’lar scoped path’e bağlanır
```

**Yapılmayacaklar:**
- `currentFranchiseId == ""` iken gerçek veri yazımı (`LiveActivityTracker` benzeri crash’ler).
- DE oturumunda CH-only listener ( `officeOperationsProductEnabledForSession` ile gate).

### 7.2 UI kapıları (sıra)

1. `FranchiseCapabilityMatrix.*ForSession(serviceFranchiseId:userProfile:)` — ülke ürünü
2. `userProfile?.can*` — rol
3. Asla yalnızca `countryCode == "TR"` (profil ülkesi session franchise’ı yansıtmaz)

### 7.3 Navigasyon

`MainTabRouter.current(...)` — tek tab indeks kaynağı; `ContentView` dışında hard-coded tab numarası kullanma.

### 7.4 Dağınık kontroller (temizlik listesi)

Şu an **6+ dosyada** tekrarlanan:

`role == .manager || role == .admin || role == .superadmin || role == .globaladmin`

**Hedef:** `UserProfile.canAccessOfficeFinancialHubs` (veya benzeri tek property).

**Dosyalar:** `OfficeOperationsMainView`, `OfficeOperationsMenuView`, `WorkTimeTrackingHub`, `TrafficAccidentContractsView`, `InkassoHubListView`, `PaymentsHubListView`.

---

## 8. Web ERP düzeni

### 8.1 Repo gerçekliği

| Bileşen | Konum |
|---------|--------|
| Production build (hosting) | `public/` (minified React) |
| Kaynak kod | **Dış repo:** `GreenMotionWebApp/green-motion-web/` |
| Müşteri self-fill | `public/return.html`, `checkout.html`, `condition-signature.html` |

Bu master plan **her iki repoya** uygulanır; PR checklist zaten kardeş PR istiyor.

### 8.2 Web standartları (green-motion-web)

| Konu | Dosya / davranış |
|------|------------------|
| Scoped queries | `firebaseHelpers.js` → `franchises/{sessionFranchiseId}/` |
| Global koleksiyonlar | `GLOBAL_COLLECTIONS` = iOS `isGlobalCollection` ile senkron |
| Rol çözümleme | `roleScope.js` ↔ `AuthenticationManager.resolvedScope` |
| Ürün kapıları | `FranchiseCapabilityMatrix` ile aynı tablo (paylaşılan JSON veya generated constants önerilir) |
| Admin kullanıcı CRUD | Cloud Functions (`adminDeleteUserCompletely`, `assignUserRoles`, …); doğrudan `users` write yok. Web’deki create/update callable adları deploy ile doğrulanmalı |

### 8.3 `public/` build

- Hosting artifact; rol mantığı **kaynak repoda** değişir, sonra `npm run build` → `public/` deploy.
- Müşteri HTML formları: `publicCustomerSelfFill*` rules ile hizalı payload; franchise path scoped.

---

## 9. Uygulama fazları (rules kırmadan)

### Faz 0 — Envanter (1 hafta, salt okunur)

- [ ] `node scripts/firestore_readonly_inventory.mjs`
- [ ] `FIRESTORE_FRANCHISE_ENVANTER_SABLON.md` doldur
- [ ] `FIREBASE_DATA_SCHEMA.md` güncelle: `globaladmin`, `garage`, `roleScope`, superadmin scoped notu
- [ ] Web + iOS `GLOBAL_COLLECTIONS` diff

### Faz 1 — Tek sözlük (2–3 hafta, düşük risk)

- [ ] `docs/ROLE_CAPABILITY_MATRIX.md` (bu dokümandan türetilmiş kısa tablo) veya bu dosyanın §3–§5’i canonical ilan
- [ ] iOS: `UserProfile`’a eksik `can*` property’ler; view refactor
- [ ] Web: `roleScope.js` + capability helper parite testi
- [ ] `currentHasCrossFranchiseAccess` kaldır veya wire et

### Faz 2 — Storage sıkılaştırma (ayrı deploy, yüksek dikkat)

- [ ] `storage.rules`: `franchises/{franchiseId}` için `userMatchesFranchiseId` eşdeğeri (Storage’da Firestore read maliyeti — claim alternatifi değerlendir)
- [ ] Regression: PDF upload, foto sync, web ERP medya

### Faz 3 — `viewer` ve garage netleştirme

- [ ] Rules: `viewer` read-only write deny
- [ ] iOS/Web UI: viewer için buton gizleme
- [ ] Garage: sadece `garageServiceJobs` path’leri

### Faz 4 — Generated parity (uzun vade)

- [ ] `scripts/generate_capability_matrix.swift` → JSON → web import
- [ ] CI: rules helper isimleri ↔ client capability isimleri drift testi

---

## 10. Test matrisi (her PR)

### Oturum / franchise

| Senaryo | Beklenen |
|---------|----------|
| DE_DUSSELDORF manager login | Scoped DE verisi; CH listener yok |
| TR şube staff | Operations açık; CH panel kapalı |
| globaladmin TR→DE switch | `currentFranchiseId` değişir; veri DE scoped |
| superadmin DE franchiseId | DE scoped yazma; CH verisi **permission denied** |

### Rol

| Senaryo | Beklenen |
|---------|----------|
| Franchise admin CH panel | Panel açık; `users` list **kapalı** (elevated only) |
| Manager duyuru CH | Yayınlayabilir (rules + UI) |
| Manager CH admin shuttle kapısı | iOS: kapalı (`canAccessFranchiseAdminPanel` false) — bilinçli UX mi rules mu — karar kaydı |
| garage CH | Sadece atanmış servis işleri |
| viewer (hedef) | Read-only |

### Email / PDF (DE)

| Senaryo | Beklenen |
|---------|----------|
| Checkout email DE | UI + Functions + Storage path `franchises/DE_*/checkout_pdfs` |
| Arka planda send (iOS) | Coordinator verilen **scoped** `outgoingEmails` doc path’ini dinler; franchise değişince path yeniden bağlanmalı |

### Web

| Senaryo | Beklenen |
|---------|----------|
| Scoped write yeni kayıt | `franchises/{id}/…` |
| Legacy kök write | Denied |
| Build deploy | `public/` güncel bundle |

---

## 11. Anti-pattern listesi (yapma)

1. View içinde `hasPrefix("TR")` — `FranchiseCapabilityMatrix` kullan.
2. `superadmin`’e cross-franchise UI verip rules’ta bypass beklemek.
3. `users` dokümanını istemciden `role` / `franchiseId` güncellemek.
4. Storage path’e başka franchise id ile yazmak (“zaten auth var”).
5. `FIREBASE_DATA_SCHEMA.md`’yi rules’tan eski bırakıp ekibe referans vermek.
6. iOS’ta feature flag açıp web/rules kapalı bırakmak.
7. `dualWrite` migration bitmeden production’da.

---

## 12. Bilinen açıklar (özet)

| # | Konu | Öncelik | Önerilen sahip |
|---|------|---------|----------------|
| G1 | Storage franchise izolasyonu yok | P0 güvenlik | Backend + rules PR |
| G2 | `FIREBASE_DATA_SCHEMA.md` stale | P1 dokümantasyon | Tek PR schema sync |
| G3 | Dağınık manager-tier UI checks | P2 iOS refactor | iOS |
| G4 | `viewer` = staff in rules | P2 rules+UI | Rules önce |
| G5 | Web kaynak bu repoda yok | P1 process | Kardeş PR zorunluluğu |
| G6 | CH manager vs admin panel kapısı | P3 product | PM kararı + tek satır doc |
| G7 | `currentHasCrossFranchiseAccess` dead code; property yorumu hâlâ “superadmin or globaladmin” | P3 iOS cleanup | iOS |
| G8 | iOS `isElevatedAdmin` user directory UI vs rules `isGlobalAdminOnly` | P1 | Rules veya UI hizası |
| G9 | Return email: iOS TR+DE, Functions checkout-only allow-list | P2 | Functions |
| G10 | `isAdmin()` vs `canAccessFranchiseAdminPanel` (§6.1.1) | P2 | Dokümantasyon + eğitim |
| G11 | `UserRole.globaladmin` Swift yorumu “superadmin ile aynı bypass” — rules ile çelişiyor | P3 | iOS yorum düzeltmesi |

---

## 13. Karar kaydı şablonu (yeni rol/özellik için)

Her yeni yetki için doldurulur:

```markdown
### [Özellik adı]
- **Franchise:** TR | CH | DE | all
- **Roller:** manager, admin, …
- **Firestore path:** franchises/{id}/collection
- **Rules helper:** hasScopedFranchiseAccess + …
- **Storage path:** …
- **Function:** callable adı / trigger
- **iOS:** UserProfile.canX + FranchiseCapabilityMatrix
- **Web:** roleScope.js + firebaseHelpers
- **Test:** [oturum] + [rol] + permission denied beklenen
```

---

## 14. Özet

Multi-franchise sisteminde **güvenlik kaynağı Firestore rules + Functions**’dır; iOS ve Web yalnızca aynı `roleScope` ve `FranchiseCapabilityMatrix` ile **tutarlı UX** sunar. `globaladmin` cross-franchise, `superadmin` elevated-scoped, franchise `admin`/`manager`/`staff` operasyonel katmandır. Storage ve `viewer` rolü en büyük teknik borçlardır. Bu plan, mevcut rules’ı bozmadan faz faz hizalamayı tanımlar; her değişiklik `docs/PR_CHECKLIST_FRANCHISE.md` ve deploy sırasına uyar.

**Sonraki adım:** Faz 0 envanter + `FIREBASE_DATA_SCHEMA.md` güncellemesi; ardından Faz 1 iOS `UserProfile` konsolidasyonu ve web `roleScope` parity PR’ı.
