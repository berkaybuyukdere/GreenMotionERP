# Franchise + Firebase — güvenli yönetişim özeti

Bu dosya **canlı veriyi değiştirmez**; ekip için tek referans noktasıdır.

## Veri yolları (kaynak gerçeği)

| Katman | Operasyonel veri | Global / paylaşılan |
|--------|------------------|---------------------|
| **iOS** `FirebaseService` | `franchises/{FRANCHISE_ID}/{collection}` (scoped reads/writes açık) | `isGlobalCollection` içindekiler → kök |
| **Web** `firebaseHelpers.js` | Aynı: prod kullanıcı → `franchises/{FRANCHISE_ID}/{collection}` | `GLOBAL_COLLECTIONS` → kök (iOS ile hizalı) |

Global set (iki tarafta senkron tutulmalı): `users`, `franchises`, `smtpConfigurations`, `notifications`, `outgoingEmails`, `plateFormats`, `protocolTemplates`, `accidentCodes`, `fcmTokens`, `adminTests`, `adminTestLogs`.

## Yapılmaması gerekenler (yüksek risk)

- Kök ↔ scoped arasında otomatik toplu migrate (yedek + doğrulama olmadan).
- `users` veya `returnFormData` yolunu koordinesiz değiştirmek.
- `dualWrite`’ı migration bitmeden açmak/karıştırmak.

## Elle yapılacak işler (Faz 0 — öneri)

1. **Otomatik envanter (önerilen):** `node scripts/firestore_readonly_inventory.mjs` — ayrıntı [scripts/README_FIRESTORE_INVENTORY.md](../scripts/README_FIRESTORE_INVENTORY.md). `gcloud auth login` gerekir. Elle tablo için şablon: [FIRESTORE_FRANCHISE_ENVANTER_SABLON.md](FIRESTORE_FRANCHISE_ENVANTER_SABLON.md).
2. Firestore Console ile spot kontrol (isteğe bağlı).
3. Tam yedek export: [FIRESTORE_EXPORT_HOWTO.md](FIRESTORE_EXPORT_HOWTO.md) — bucket onayı ile; kapılı script: `scripts/firestore_export_backup.mjs`.
4. Storage `return_pdfs` envanteri (salt okunur): `node scripts/storage_return_pdfs_readonly_inventory.mjs` — [scripts/README_FIRESTORE_INVENTORY.md](../scripts/README_FIRESTORE_INVENTORY.md).
5. Faz C/D yedek + isteğe bağlı `userPresence` silme: [README_FAZ_CD_BACKUP_AND_CLEANUP.md](README_FAZ_CD_BACKUP_AND_CLEANUP.md) — **export önce**, silme için export URI kanıtı zorunlu.

## PR ve deploy

- [PR_CHECKLIST_FRANCHISE.md](PR_CHECKLIST_FRANCHISE.md)
- [DEPLOY_REGRESSION_CHECKLIST.md](DEPLOY_REGRESSION_CHECKLIST.md)

## Repo temizliği (güvenli)

- **Web:** Eski giriş noktaları `GreenMotionWebApp/green-motion-web/src/_deprecated/` altında; `index.js` yalnızca `App.js` kullanır.
- **iOS:** Presence özelliği kaldırıldı; kullanılmayan presence string’leri lokalizasyondan silindi.
- **Firestore `userPresence` (üretim):** 2026-03-30 öncesi/sonrası tam export + CH scoped doküman silimi yapıldı; güncel yedek yolları [README_FAZ_CD_BACKUP_AND_CLEANUP.md](README_FAZ_CD_BACKUP_AND_CLEANUP.md) günlüğünde.

## Deploy sırası

Kurallar ve Functions değişikliklerinde mevcut proje dokümantasyonuna (`DEPLOYMENT_SUCCESS.md` vb.) uy.
