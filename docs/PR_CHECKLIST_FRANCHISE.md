# PR checklist — Firebase franchise güvenliği

Yeni PR’da aşağıdakilerden etkilenen değişiklikler varsa işaretleyin.

## Global Firestore koleksiyonu ekledim / kaldırdım / yeniden adlandırdım

- [ ] [FirebaseService.swift](../AracHasarKayit/Firebase/FirebaseService.swift) içindeki `isGlobalCollection` güncellendi
- [ ] Web: [GreenMotionWebApp/green-motion-web/src/utilities/firebaseHelpers.js](../../GreenMotionWebApp/green-motion-web/src/utilities/firebaseHelpers.js) içindeki `GLOBAL_COLLECTIONS` aynı PR veya eşzamanlı kardeş PR ile güncellendi
- [ ] [firestore.rules](../firestore.rules) gerekiyorsa gözden geçirildi (staging önerilir)

## Yeni domain koleksiyonu (franchise altı)

- [ ] Yazılan dokümanda `franchiseId` alanı, Firestore path ile uyumlu (`franchises/{id}/...` → `franchiseId == id`)
- [ ] iOS `getCollectionReference` / `getFilteredQuery` kullanımı veya bilinçli istisna dokümante

## Web (Green Motion Web)

- [ ] `src/index.js` yalnızca `App.js` import ediyor; `_deprecated/` altı üretimde import edilmiyor (`npm run check:deprecated-imports`)

## Deploy

- [ ] Firestore rules / Functions deploy sırası mevcut proje dokümantasyonuna uygun
- [ ] İsteğe bağlı: `node scripts/firestore_readonly_inventory.mjs` ile envanter notu (büyük şema değişikliklerinde)
