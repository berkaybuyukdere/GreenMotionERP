# Firestore franchise envanter şablonu (manuel / script çıktısı ile doldurun)

> **Otomatik doldurma:** `node scripts/firestore_readonly_inventory.mjs` çıktısını `docs/live-inventory-*.md` olarak üretir (git’e genelde eklenmez).

## A1 — Kök vs scoped (özet)

| Koleksiyon | Kök (root) adet | franchises/CH/... (veya diğer ID) | Yorum (canlı veri hangi yol?) |
|------------|-----------------|-----------------------------------|-------------------------------|
| araclar | | | |
| activities | | | |
| iadeIslemleri | | | |
| exitIslemleri | | | |
| office_operations | | | |
| … | | | |

## A2 — Storage (manuel)

| Alan | Kök path | Scoped path | Not |
|------|----------|-------------|-----|
| return_pdfs | return_pdfs/ | franchises/CH/return_pdfs/ | iOS/web çoklu aday dener |

## A3 — Auth vs Firestore users

- Firebase Console → Authentication: kullanıcı sayısı: ______
- Firestore `users` kök koleksiyon sayısı: ______ (script veya Console)
- Not: ______

## A4 — Yedek (export)

- Tarih: ______
- GCS yolu: `gs://...`
- Onaylayan: ______
