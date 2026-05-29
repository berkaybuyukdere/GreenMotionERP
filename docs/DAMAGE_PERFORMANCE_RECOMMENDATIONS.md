# Damage Module — Performance Recommendations

**Scope:** iOS app (`AracHasarKayit`) — hasar (damage) capture, list, reports, PDF, Fleet Inspection damage tab.  
**Date:** May 2026  
**Goal:** Faster perceived UX and lower Firestore/network cost without breaking franchise isolation.

---

## Executive summary

The damage path is correct functionally but pays cost in three places: **(1)** global top-level `hasarKayitlari` listener merged into every vehicle, **(2)** **photo upload** on the critical path when saving, and **(3)** **report/PDF screens** that flatten all vehicles’ damages in memory. Below are prioritized fixes.

| Priority | Item | Impact | Effort |
|----------|------|--------|--------|
| P0 | Parallel photo uploads (bounded concurrency) | High on save | Medium |
| P0 | Keep `detailMemoV2` + derived caches on vehicle detail | High on navigation | Done (flag on) |
| P1 | Paginate / window top-level hasar listener (e.g. last 90 days) | High on fleet load | Medium |
| P1 | Damage list on vehicle: subcollection listener per open vehicle | Medium | Medium |
| P2 | Report grid: use `allHasarKayitlariForReporting` only when Reports opens | Medium | Low |
| P2 | Thumbnail pipeline: downscale before upload (max edge 1920) | Medium on upload | Low |
| P3 | Firestore composite index per franchise + `createdAt` | Query stability | Low |
| P3 | Prefetch damage photos only when opening HasarDetay | Low–medium | Low |

---

## 1. Data loading architecture

### Current behavior
- `AracViewModel` attaches `observeHasarKayitlariTopLevel` and merges damages into each `Arac` by `aracId`.
- Opening **Reports** or **CH Panel** touches `allHasarKayitlariForReporting` / `flatMap { hasarKayitlari }` — O(vehicles × damages).

### Recommendations
1. **Time-windowed listener** for top-level damages: `whereField("tarih", isGreaterThan: cutoff)` with franchise scope. Reduces snapshot size for large fleets.
2. **Lazy attach:** only start top-level hasar listener when user opens Reports, Panel, or Damage map — not at cold start (align with `attachExitHistoryListenerIfNeeded` pattern in `RaporView`).
3. **Per-vehicle subcollection** (`araclar/{id}/hasarKayitlari`) for detail screen only; top-level remains source of truth for reporting sync.

---

## 2. Save path (`HasarEkleView`)

### Current behavior
- Save blocks on photo upload progress (`isUploading`, `PendingPhotoUploadTracker`).
- Offline queue helps but online path still feels slow with many images.

### Recommendations
1. **Bounded parallel uploads** (e.g. 3 concurrent) instead of strict serial — typical 40–60% wall-clock reduction.
2. **Client-side resize** before upload (JPEG 0.82, max dimension 1920) — smaller Storage objects, faster upload.
3. **Optimistic UI:** mark record saved locally, show “Photos uploading…” badge on row until URLs resolve (already partially supported via offline queue — extend to online).
4. **Skip duplicate notifications** when `usedOfflineMediaQueue` (already done) — keep.

---

## 3. UI / SwiftUI

### Recommendations
1. **`OptimizationFeatureFlags.detailMemoV2`** — keep enabled; `cachedAracIadeleri` / exit caches avoid recomputing filters on every render in `AracDetayView`.
2. **Hasar list** — use stable `id` + avoid reloading full vehicle on each `hasarEkle` callback; patch single row in ViewModel.
3. **Kingfisher** — set memory/disk limits for damage thumbnails in list; use downsampling processor.
4. **Fleet Inspection damage tab** — already uses in-memory `arac.hasarKayitlari`; no extra Firestore read if vehicle is fresh.

---

## 4. PDF & export

### Current behavior
- `VehicleDamageMapView.buildDamageMapPDF` and `SwitzerlandDamageReportPDFLayout` render on main thread with UIKit PDF context.
- Fleet Inspection PDF (`FleetInspectionReportPDF`) is lightweight (table only).

### Recommendations
1. Generate PDFs on **background queue** (`Task.detached`) — already pattern in shuttle export; apply to damage PDF share.
2. For vehicles with **>30 damages**, PDF table paginates automatically; cap photo pages in combined export.
3. Cache last-generated PDF URL per `aracId` + day for repeat share.

---

## 5. Firestore indexes & rules

Add composite index (if filtering by date):

```json
{
  "collectionGroup": "hasarKayitlari",
  "fields": [
    { "fieldPath": "franchiseId", "order": "ASCENDING" },
    { "fieldPath": "tarih", "order": "DESCENDING" }
  ]
}
```

Ensure `live_activity` index exists for panel feed:

```json
{
  "collectionGroup": "live_activity",
  "fields": [
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

---

## 6. Quick wins (this week)

- [ ] Parallel photo upload (max 3) in `HasarEkleView` upload helper  
- [ ] Move damage PDF generation off main actor  
- [ ] Defer top-level hasar listener until Reports/Panel first open  
- [ ] Image resize helper shared with checkout/return capture  

---

## 7. Metrics to track

| Metric | Target |
|--------|--------|
| Hasar save → dismiss (online, 4 photos) | < 8 s on 4G |
| Vehicle detail open (memo on) | < 300 ms to interactive |
| Reports damage count refresh | No main-thread hitch > 100 ms |
| Firestore hasar listener docs per session | < 2k for CH franchise |

---

## 8. Live tracking (Panel)

Operational visibility is now fed by `live_activity` events (check-out, return, damage, inspection, shuttle). This does **not** replace audit logs; it complements them with sub-20s latency for admins. Damage events logged: `damage_created`, `damage_updated`, `damage_completed`.

---

*End of report.*
