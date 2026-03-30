# Faz C / D — yedek, onay, isteğe bağlı temizlik

Bu akış **üretim** verisine dokunur (export → GCS yazar; isteğe bağlı adımda `userPresence` siler). Otomatik cron veya sessiz script yok; her adımda açık onay ve doğru bucket gerekir.

## 1) Salt okunur envanter (önce)

```bash
node scripts/firestore_readonly_inventory.mjs
node scripts/storage_return_pdfs_readonly_inventory.mjs
```

## 2) Firestore tam yedek (export)

1. Güvenli bir GCS bucket ve klasör seçin (`gs://.../firestore-backups/UNIQUE_NAME`). Bu projede tipik: `greenmotionapp-33413-backups-eu` veya `greenmotionapp-33413-backups` (`gcloud storage buckets list`).
2. `gcloud firestore operations list` ile önceki export bitmiş mi kontrol edin.
3. Kapısı olan wrapper:

```bash
node scripts/firestore_export_backup.mjs \
  --destination=gs://YOUR_BUCKET/firestore-backups/YYYYMMDD-HHMM \
  --acknowledge-cost \
  --confirm=I_HAVE_AUTHORIZATION
```

Export çıktısındaki **tam** `gs://…` önekini not edin (silme adımında kullanılır).

## 3) `userPresence` temizliği (isteğe bağlı — D)

Uygulama artık yazmıyorsa ve yedek alındıysa:

**Önce dry-run (tek franchise):**

```bash
node scripts/firestore_cleanup_user_presence.mjs --franchise=CH
```

**Tüm franchise dokümanları + kök `userPresence` (legacy) dry-run:**

```bash
node scripts/firestore_cleanup_user_presence.mjs --all-franchises --include-root-legacy
```

**Silme (geri dönüş yok — export URI zorunlu):**

```bash
node scripts/firestore_cleanup_user_presence.mjs \
  --franchise=CH \
  --export-uri=gs://YOUR_BUCKET/firestore-backups/YYYYMMDD-HHMM \
  --execute \
  --confirm=PRESENCE_DELETE_AFTER_BACKUP
```

Hepsi için aynı güvenlik bayraklarıyla:

```bash
node scripts/firestore_cleanup_user_presence.mjs \
  --all-franchises --include-root-legacy \
  --export-uri=gs://YOUR_BUCKET/firestore-backups/YYYYMMDD-HHMM \
  --execute \
  --confirm=PRESENCE_DELETE_AFTER_BACKUP
```

`--export-uri`, tamamlanmış export ile **aynı** GCS yoluna işaret etmelidir (kanıt olarak).

## 4) Faz C (kök legacy koleksiyonlar)

Toplu “her kök dokümanı sil” yoktur. **CH `franchiseId` ile işaretli kök yetimleri** (scoped’ta aynı doc id yok; iOS scoped-only) için kapılı script:

```bash
node scripts/firestore_legacy_root_cleanup.mjs
# sonra: --execute --confirm=LEGACY_ROOT_CLEANUP_CH --export-uri=gs://...
```

Diğer franchise’lar, belirsiz `franchiseId` veya scoped’ta karşılığı belirsiz kayıtlar **silinmez** (raporlanır). Bakınız [FRANCHISE_DATA_GOVERNANCE.md](FRANCHISE_DATA_GOVERNANCE.md).

---

## Çalışma günlüğü (iç referans — `greenmotionapp-33413`)

| Tarih (UTC) | Olay |
|---------------|------|
| 2026-03-30 | Tam export (presence temizliği öncesi): `gs://greenmotionapp-33413-backups-eu/firestore-backups/20260330T213955Z-full` |
| 2026-03-30 | `franchises/CH/userPresence` 16 doküman silindi (export URI ile onaylı script). |
| 2026-03-30 | Sonraki sweep (`--all-franchises --include-root-legacy`): 0 kalan `userPresence` dokümanı. |
| 2026-03-30 | Tam export (güncel durum): `gs://greenmotionapp-33413-backups-eu/firestore-backups/20260330T214202Z-post-presence-cleanup` |
| 2026-03-30 | Kök legacy CH yetimi: `araclar`×1 + `activities`×2 silindi (`scripts/firestore_legacy_root_cleanup.mjs`, aynı export URI onayı). Uygulama scoped-only; scoped’ta aynı doc id yoktu, `franchiseId=CH` idi. |
