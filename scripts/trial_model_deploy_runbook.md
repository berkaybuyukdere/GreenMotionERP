# Trial Model Deploy Runbook

## 1) Deploy Rules

```bash
firebase deploy --only firestore:rules,storage --project greenmotionapp-33413
```

## 2) Deploy Functions

```bash
cd functions
npm install
npm run lint
cd ..
firebase deploy --only functions --project greenmotionapp-33413
```

## 3) Dry-run Demo Purge

```bash
bash scripts/purge_demo_data.sh --dry-run
```

## 4) Execute Demo Purge

```bash
bash scripts/purge_demo_data.sh --execute
```

## 5) Verify

```bash
bash scripts/verify_no_demo_data.sh
```

## 6) Smoke Test

- Trial user (active): login succeeds, data under `franchises/{id}/...`.
- Trial user (expired): login blocked with trial-expired message.
- Converted user: login succeeds after conversion.
- Storage root: only `franchises/` remains.
