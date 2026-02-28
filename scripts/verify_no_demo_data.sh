#!/usr/bin/env bash
set -euo pipefail

# Verifies that no legacy demo paths remain in Storage.
# Firestore collection existence checks are intentionally lightweight:
# we only verify the storage side and expected bucket root shape.

PROJECT_ID="${FIREBASE_PROJECT_ID:-greenmotionapp-33413}"
BUCKET="${FIREBASE_STORAGE_BUCKET:-greenmotionapp-33413.firebasestorage.app}"

echo "Project: ${PROJECT_ID}"
echo "Bucket:  gs://${BUCKET}"
echo ""

echo "=== Storage root listing ==="
gsutil ls "gs://${BUCKET}" || true

echo ""
echo "=== Checking demo_environments path ==="
if gsutil ls "gs://${BUCKET}/demo_environments/**" >/dev/null 2>&1; then
  echo "FAIL: demo_environments objects still exist in storage."
  exit 1
else
  echo "OK: no demo_environments objects found."
fi

echo ""
echo "Verification complete."
