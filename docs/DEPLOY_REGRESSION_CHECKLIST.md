# Deploy öncesi kısa regresyon (Faz E)

Önemli Firebase / client sürümü değişikliklerinde, prod’a çıkmadan önce:

## Franchise kullanıcısı (ör. CH)

- [ ] Giriş başarılı
- [ ] Araç listesi yükleniyor
- [ ] En az bir okuma yoğun ekran (iade veya çıkış listesi) açılıyor
- [ ] İsteğe bağlı: güvenli bir alanda tek küçük yazma (taslak / not)

## Web (aynı Firebase projesi)

- [ ] Giriş ve ana dashboard
- [ ] Operasyonel bir liste sayfası (araç / iade vb.)

## Superadmin

- [ ] Kök `users` / `franchises` yönetim ekranları açılıyor

## PDF / Storage

- [ ] Örnek iade PDF indirme veya dosya URL’si (scoped + legacy path denemeleri mevcut kodda var)
- [ ] Scoped Storage path doğrulaması: farklı franchise kullanıcısı ile birbirinin `franchises/{id}/...` dosyasına erişim denemesi reddediliyor
- [ ] Global admin ile aynı dosya erişimi doğrulaması başarılı

## Return Form Rules

- [ ] Aktif akış: `franchises/{franchiseId}/returnFormData/{token}` üzerinden form create/read çalışıyor
- [ ] Legacy top-level `returnFormData/{token}` istemci create engelleniyor

## Test Altyapısı (ViewInspector / SnapshotTesting)

- [ ] `AracHasarKayitTests/EmptyStateViewInspectorTests` geçiyor
- [ ] Snapshot testi default koşuda `skip` (beklenen)
- [ ] Snapshot baseline almak için `ENABLE_SNAPSHOT_TESTS=1` ile test koşulup snapshot çıktısı doğrulanıyor

## Araçlar

- [ ] `firebase firestore:indexes` — yeni sorgu için eksik index uyarısı yok mu (ilk hatada Console’dan index oluştur)
- [ ] İsteğe bağlı staging: `npm run deploy:preview` (web) veya TestFlight

## Deploy Smoke (Tenant Isolation + Test Bootstrap)

- [ ] Lokal statik smoke kontrolünü çalıştır: `bash scripts/deploy_smoke_tenant_isolation.sh`
- [ ] Script sonucu `FAIL: 0` olmalı; `WARN` varsa deploy notlarına ekleyip takip aç
- [ ] Post-deploy canlı doğrulama:
  - Non-admin kullanıcı: farklı franchise Firestore verisine erişim reddediliyor
  - Non-admin kullanıcı: `franchises/{otherId}/...` Storage erişimi reddediliyor
  - Aynı franchise: Firestore/Storage scoped path erişimi başarılı
  - `globaladmin`: beklenen cross-franchise erişimler başarılı
- [ ] Test bootstrap smoke:
  - `xcodebuild test -scheme AracHasarKayit -destination 'platform=iOS Simulator,name=iPhone 16'`
  - Snapshot baseline gerekiyorsa: `ENABLE_SNAPSHOT_TESTS=1 xcodebuild test -scheme AracHasarKayit -destination 'platform=iOS Simulator,name=iPhone 16'`
