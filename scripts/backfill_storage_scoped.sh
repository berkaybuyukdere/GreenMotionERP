#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BUCKET_NAME:-}" ]]; then
  echo "BUCKET_NAME is required. Example: BUCKET_NAME=greenmotionapp-33413.appspot.com"
  exit 1
fi

DEFAULT_FRANCHISE_ID="${DEFAULT_FRANCHISE_ID:-ch}"
REPORT_PATH="${REPORT_PATH:-$(pwd)/scripts/storage-backfill-report.txt}"

prefixes=(
  "hasar_fotograflari"
  "iade_fotograflari"
  "exit_fotograflari"
  "office_operations"
  "office_Return"
  "kafa_kagitlari"
  "iade_signatures"
  "return_pdfs"
)

echo "Storage scoped backfill starting" | tee "$REPORT_PATH"
echo "Bucket: $BUCKET_NAME" | tee -a "$REPORT_PATH"
echo "Default franchise: $DEFAULT_FRANCHISE_ID" | tee -a "$REPORT_PATH"

for prefix in "${prefixes[@]}"; do
  src="gs://${BUCKET_NAME}/${prefix}"
  dst="gs://${BUCKET_NAME}/franchises/${DEFAULT_FRANCHISE_ID}/${prefix}"
  if ! gsutil ls "${src}" >/dev/null 2>&1; then
    echo "Skip missing source prefix: ${src}" | tee -a "$REPORT_PATH"
    continue
  fi
  echo "Sync: ${src} -> ${dst}" | tee -a "$REPORT_PATH"
  gsutil -m rsync -r "${src}" "${dst}" | tee -a "$REPORT_PATH"
done

echo "Generating parity stats..." | tee -a "$REPORT_PATH"
for prefix in "${prefixes[@]}"; do
  if ! gsutil ls "gs://${BUCKET_NAME}/${prefix}" >/dev/null 2>&1; then
    echo "${prefix}: legacy=0 scoped=0 (source missing)" | tee -a "$REPORT_PATH"
    continue
  fi
  legacy_count=$(gsutil ls -r "gs://${BUCKET_NAME}/${prefix}/**" | awk '!/\/$/' | wc -l | xargs)
  scoped_count=$(gsutil ls -r "gs://${BUCKET_NAME}/franchises/${DEFAULT_FRANCHISE_ID}/${prefix}/**" | awk '!/\/$/' | wc -l | xargs)
  echo "${prefix}: legacy=${legacy_count} scoped=${scoped_count}" | tee -a "$REPORT_PATH"
done

echo "Storage scoped backfill completed." | tee -a "$REPORT_PATH"
