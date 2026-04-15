# Firebase Rules Deploy Sequence

Scope: deploy only `firestore.rules` and `storage.rules` safely and quickly.

## Prechecks (2-3 min)

```bash
cd /Users/berkaybuyukdere/Desktop/AracHasarKayitv10_BEST
firebase --version
firebase login:list
firebase use
git status --short firestore.rules storage.rules
bash scripts/deploy_smoke_tenant_isolation.sh
```

Precheck gate: continue only if smoke script exits with `FAIL: 0`.

## Exact Deploy Order (prod)

1. Deploy Firestore rules first:

```bash
firebase deploy --only firestore:rules
```

2. Deploy Storage rules second:

```bash
firebase deploy --only storage
```

3. Optional single command (same order is preferred above for control):

```bash
firebase deploy --only firestore:rules,storage
```

## Rollback Notes

- Rollback is a redeploy of previous known-good rule files from git history.
- Fast path:

```bash
git checkout <known-good-commit> -- firestore.rules storage.rules
firebase deploy --only firestore:rules
firebase deploy --only storage
```

- Then restore your working branch files if needed:

```bash
git restore --source=HEAD -- firestore.rules storage.rules
```

## Post-Deploy Smoke Checks

Run the scripted checks again:

```bash
bash scripts/deploy_smoke_tenant_isolation.sh
```

Manual confirm (minimum):
- Non-admin cross-tenant Firestore access is denied.
- Non-admin cross-tenant Storage access is denied.
- Same-tenant read/write works.
- `globaladmin` cross-tenant access works where expected.

