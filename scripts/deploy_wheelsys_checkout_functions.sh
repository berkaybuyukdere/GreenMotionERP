#!/usr/bin/env bash
# Deploy WheelSys checkout/journal callables.
# Large functions/index.js needs extra discovery time + heap during analysis.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export FUNCTIONS_DISCOVERY_TIMEOUT="${FUNCTIONS_DISCOVERY_TIMEOUT:-90}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"

TARGETS="functions:wheelsysGetJournal,\
functions:wheelsysGetBookingPreview,\
functions:wheelsysSearchAvailableVehicles,\
functions:wheelsysAssignVehicleToBooking"

echo "FUNCTIONS_DISCOVERY_TIMEOUT=$FUNCTIONS_DISCOVERY_TIMEOUT"
echo "NODE_OPTIONS=$NODE_OPTIONS"
firebase deploy --only "$TARGETS"
