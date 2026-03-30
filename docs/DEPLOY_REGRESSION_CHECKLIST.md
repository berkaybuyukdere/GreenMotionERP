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

## Araçlar

- [ ] `firebase firestore:indexes` — yeni sorgu için eksik index uyarısı yok mu (ilk hatada Console’dan index oluştur)
- [ ] İsteğe bağlı staging: `npm run deploy:preview` (web) veya TestFlight
