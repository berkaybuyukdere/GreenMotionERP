#!/usr/bin/env bash
set -euo pipefail

# Purges legacy demo data from Firestore and Storage.
# Usage:
#   scripts/purge_demo_data.sh --dry-run
#   scripts/purge_demo_data.sh --execute

MODE="${1:-"--dry-run"}"
PROJECT_ID="${FIREBASE_PROJECT_ID:-greenmotionapp-33413}"
BUCKET="${FIREBASE_STORAGE_BUCKET:-greenmotionapp-33413.firebasestorage.app}"

if [[ "${MODE}" != "--dry-run" && "${MODE}" != "--execute" ]]; then
  echo "Invalid mode: ${MODE}"
  echo "Use --dry-run or --execute"
  exit 1
fi

DEMO_COLLECTIONS=(
  "demo_araclar"
  "demo_activities"
  "demo_servisler"
  "demo_servisFirmalari"
  "demo_iadeIslemleri"
  "demo_exitIslemleri"
  "demo_office_operations"
  "demo_officeOperations"
  "demo_office_Return"
  "demo_workSchedules"
  "demo_work_schedules"
  "demo_vacationTimes"
  "demo_assistantCompanies"
  "demo_adminTests"
  "demo_adminTestLogs"
  "demo_shuttleEntries"
  "demo_shuttleSessions"
  "demo_shuttleReports"
  "demo_notifications"
  "demo_fcmTokens"
  "demo_userPresence"
  "demo_protocols"
  "demo_raporGecmisi"
  "demo_trafficFines"
  "demo_bankingTransactions"
  "demo_additionalSales"
  "demo_semesInvoices"
  "demo_environments"
)

echo "Project: ${PROJECT_ID}"
echo "Bucket:  gs://${BUCKET}"
echo "Mode:    ${MODE}"
echo ""

echo "=== Firestore demo collections ==="
for coll in "${DEMO_COLLECTIONS[@]}"; do
  if [[ "${MODE}" == "--dry-run" ]]; then
    echo "[DRY] Would delete Firestore collection: ${coll}"
  else
    echo "[RUN] Deleting Firestore collection: ${coll}"
    firebase firestore:delete "${coll}" --project "${PROJECT_ID}" --recursive --force >/dev/null || true
  fi
done

echo ""
echo "=== Storage demo paths ==="
if [[ "${MODE}" == "--dry-run" ]]; then
  echo "[DRY] Would delete storage path: gs://${BUCKET}/demo_environments"
  gsutil ls "gs://${BUCKET}" | awk '/demo_environments\// {print "Found: "$0}'
else
  echo "[RUN] Deleting storage path: gs://${BUCKET}/demo_environments"
  gsutil -m rm -r "gs://${BUCKET}/demo_environments" || true
fi

echo ""
if [[ "${MODE}" == "--dry-run" ]]; then
  echo "Dry-run complete. No data deleted."
else
  echo "Purge complete."
fi
