# Firestore salt okunur envanter

## Gereksinimler

- `gcloud` kurulu ve `gcloud auth login` ile oturum açık
- `gcloud config set project greenmotionapp-33413` (veya hedef proje)
- Node.js 18+ (`fetch` yerleşik)

## Komut

```bash
cd /path/to/AracHasarKayitv10_BEST
node scripts/firestore_readonly_inventory.mjs
```

Çıktı: `docs/live-inventory-<timestamp>.md` (`.gitignore` ile hariç tutulur; üretim metrikleri repoya girmesin diye). Rapor; ana tablo dışındaki franchise alt koleksiyonları (ör. `hasarKayitlari`, `userPresence`) ve kök `users` belge sayısını da içerir.

İsteğe bağlı:

```bash
node scripts/firestore_readonly_inventory.mjs --project=greenmotionapp-33413 --out=docs/my-inventory.md
```

## Firebase CLI ile ilişki

- `firebase login` proje listesi ve deploy için yeterlidir.
- Bu script **yalnızca** `gcloud auth print-access-token` kullanır (Firestore REST okuma).
- İndeks envanteri (ayrı komut): `firebase firestore:indexes` — çıktıyı isteğe bağlı `docs/` altına yönlendirebilirsiniz.

## Admin SDK / ADC (alternatif)

CI veya uzun süreli token istemeyen ortamlar için:

```bash
gcloud auth application-default login
cd functions && node scripts/firestore_readonly_inventory_admin.cjs
```

Bu ikinci script, Application Default Credentials ile `firebase-admin` kullanır (salt okunur).

## Storage — `return_pdfs` (salt okunur)

Varsayılan bucket: `greenmotionapp-33413.firebasestorage.app` ( `--bucket=` ile değişir).

```bash
node scripts/storage_return_pdfs_readonly_inventory.mjs
```

Çıktı: `docs/live-storage-inventory-<timestamp>.md` (`.gitignore`’da).
