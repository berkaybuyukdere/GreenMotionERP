#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BUCKET_NAME:-}" ]]; then
  echo "BUCKET_NAME is required."
  exit 1
fi

REPORT_PATH="${REPORT_PATH:-$(pwd)/scripts/storage-scoped-lower-to-upper-report.txt}"
lower_ids=(ch tr de)

echo "Scoped storage lowercase->uppercase migration" | tee "$REPORT_PATH"
echo "Bucket: $BUCKET_NAME" | tee -a "$REPORT_PATH"

for lower in "${lower_ids[@]}"; do
  upper="$(echo "$lower" | tr '[:lower:]' '[:upper:]')"
  src="gs://${BUCKET_NAME}/franchises/${lower}"
  dst="gs://${BUCKET_NAME}/franchises/${upper}"
  if ! gsutil ls "${src}" >/dev/null 2>&1; then
    echo "Skip missing source: ${src}" | tee -a "$REPORT_PATH"
    continue
  fi
  echo "Sync: ${src} -> ${dst}" | tee -a "$REPORT_PATH"
  gsutil -m rsync -r "${src}" "${dst}" | tee -a "$REPORT_PATH"
done

echo "Parity check..." | tee -a "$REPORT_PATH"
for lower in "${lower_ids[@]}"; do
  upper="$(echo "$lower" | tr '[:lower:]' '[:upper:]')"
  src="gs://${BUCKET_NAME}/franchises/${lower}"
  dst="gs://${BUCKET_NAME}/franchises/${upper}"
  if ! gsutil ls "${src}" >/dev/null 2>&1; then
    echo "${lower}->${upper}: source missing" | tee -a "$REPORT_PATH"
    continue
  fi
  lower_count=$(gsutil ls -r "${src}/**" | awk '!/\/$/' | wc -l | xargs)
  upper_count=$(gsutil ls -r "${dst}/**" | awk '!/\/$/' | wc -l | xargs)
  echo "${lower}->${upper}: lower=${lower_count} upper=${upper_count}" | tee -a "$REPORT_PATH"
done

echo "Done." | tee -a "$REPORT_PATH"
