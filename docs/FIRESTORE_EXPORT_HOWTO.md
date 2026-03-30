# Firestore tam yedek export (A4 — manuel onay)

**Bu komut ücret ve GCS bucket gerektirir.** Repo otomatik çalıştırmaz.

## Önkoşullar

- Hedef bucket: Proje içinde ör. `gs://greenmotionapp-33413-backups-eu/...` veya `gs://greenmotionapp-33413-backups/...` (`gcloud storage buckets list --project=greenmotionapp-33413`). Eski dokümandaki `greenmotion-backups` adı bu projede yoksa kullanılamaz.
- Hedef path örneği: `gs://YOUR_BUCKET/firestore-exports/...`
- Hesabınızda `storage.objects.create` ve Firestore export izinleri

## Örnek (doğrudan gcloud)

```bash
gcloud config set project greenmotionapp-33413

gcloud firestore export gs://YOUR_BUCKET/firestore-backups/$(date +%Y%m%d-%H%M) \
  --database='(default)'
```

## Onay kapılı wrapper (önerilen)

Aynı işi, zorunlu bayraklar olmadan çalıştırmaz:

```bash
node scripts/firestore_export_backup.mjs \
  --destination=gs://YOUR_BUCKET/firestore-backups/YYYYMMDD-HHMM \
  --acknowledge-cost \
  --confirm=I_HAVE_AUTHORIZATION
```

Tam akış: [README_FAZ_CD_BACKUP_AND_CLEANUP.md](README_FAZ_CD_BACKUP_AND_CLEANUP.md).

## Sonrası

- Export tamamlanınca Console veya `gcloud firestore operations list` ile durumu kontrol edin.
- Silme veya migrate kararı **yalnız** export ve iş onayından sonra (bakınız [FRANCHISE_DATA_GOVERNANCE.md](FRANCHISE_DATA_GOVERNANCE.md)).
