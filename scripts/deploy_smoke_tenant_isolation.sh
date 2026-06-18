#!/usr/bin/env bash
set -euo pipefail

# Deploy/post-deploy smoke verifier (non-destructive).
# Scope:
# - Firestore tenant isolation guardrails
# - Storage tenant isolation guardrails
# - Test bootstrap/snapshot smoke prerequisites
#
# This script does not mutate Firebase resources. It only reads local files.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRESTORE_RULES="${ROOT_DIR}/firestore.rules"
STORAGE_RULES="${ROOT_DIR}/storage.rules"
DEPLOY_CHECKLIST="${ROOT_DIR}/docs/DEPLOY_REGRESSION_CHECKLIST.md"

TEST_BOOTSTRAP_FILE="${ROOT_DIR}/AracHasarKayitTests/ViewTests/EmptyStateViewInspectorTests.swift"
SNAPSHOT_TEST_FILE="${ROOT_DIR}/AracHasarKayitTests/SnapshotTests/EmptyStateViewSnapshotTests.swift"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  echo "WARN: $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

must_contain() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"
  if [[ "${SEARCH_TOOL}" == "rg" ]]; then
    if rg -q "$pattern" "$file_path"; then
      pass "$description"
    else
      fail "$description (pattern not found: $pattern)"
    fi
    return
  fi

  if grep -Eq "$pattern" "$file_path"; then
    pass "$description"
  else
    fail "$description (pattern not found: $pattern)"
  fi
}

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

print_header "Deploy Smoke - Tenant Isolation + Test Bootstrap"
echo "Workspace: ${ROOT_DIR}"

SEARCH_TOOL="grep"
if command -v rg >/dev/null 2>&1; then
  SEARCH_TOOL="rg"
fi
echo "Search tool: ${SEARCH_TOOL}"

print_header "1) File presence checks"
if [[ -f "${FIRESTORE_RULES}" ]]; then
  pass "firestore.rules exists"
else
  fail "firestore.rules missing"
fi

if [[ -f "${STORAGE_RULES}" ]]; then
  pass "storage.rules exists"
else
  fail "storage.rules missing"
fi

if [[ -f "${DEPLOY_CHECKLIST}" ]]; then
  pass "docs/DEPLOY_REGRESSION_CHECKLIST.md exists"
else
  warn "docs/DEPLOY_REGRESSION_CHECKLIST.md missing"
fi

print_header "2) Firestore tenant isolation guards (static)"
if [[ -f "${FIRESTORE_RULES}" ]]; then
  must_contain "${FIRESTORE_RULES}" "hasScopedFranchiseAccess\\(" \
    "Scoped franchise helper exists"
  must_contain "${FIRESTORE_RULES}" "ud\\.data\\.role == 'globaladmin'" \
    "Global admin cross-franchise bypass exists"
  must_contain "${FIRESTORE_RULES}" "request\\.resource\\.data\\.franchiseId == franchiseId" \
    "Scoped write path enforces franchiseId == path franchiseId"
  must_contain "${FIRESTORE_RULES}" "match /returnFormData/\\{token\\}[[:space:]]*\\{" \
    "Legacy top-level return form rule block present"
  must_contain "${FIRESTORE_RULES}" "allow create: if false;" \
    "Legacy return form client create is blocked"
  must_contain "${FIRESTORE_RULES}" "publicCustomerSelfFillPayloadValid" \
    "Scoped customer QR form payload validator exists"
  must_contain "${FIRESTORE_RULES}" "match /checkoutFormData/\\{token\\}" \
    "Scoped checkoutFormData rules exist"
fi

IOS_CAPS="${ROOT_DIR}/AracHasarKayit/Utilities/OptimizationFeatureFlags.swift"
if [[ -f "${IOS_CAPS}" ]]; then
  must_contain "${IOS_CAPS}" "customerSelfFillQrEnabled" \
    "iOS customer QR capability helper exists"
  must_contain "${IOS_CAPS}" "isUK\\(franchiseId:" \
    "iOS UK franchise capability exists"
fi

WEB_REPO="${ROOT_DIR}/../GreenMotionWebApp/green-motion-web"
if [[ -d "${WEB_REPO}/public" ]]; then
  for f in return.html checkout.html customer-self-fill.js; do
    if [[ -f "${WEB_REPO}/public/${f}" ]]; then
      pass "Web customer QR asset exists: public/${f}"
    else
      fail "Missing web customer QR asset: public/${f}"
    fi
  done
fi

print_header "3) Storage tenant isolation guards (static)"
if [[ -f "${STORAGE_RULES}" ]]; then
  must_contain "${STORAGE_RULES}" "match /franchises/\\{franchiseId\\}/\\{folder\\}/\\{allPaths=\\*\\*\\}" \
    "Scoped storage franchise path rule exists"
  must_contain "${STORAGE_RULES}" "inOwnFranchise\\(franchiseId\\)" \
    "Scoped storage checks user franchise match"
  must_contain "${STORAGE_RULES}" "match /hasar_fotograflari/\\{allPaths=\\*\\*\\}" \
    "Legacy damage photo root path rule present"
  must_contain "${STORAGE_RULES}" "match /iade_fotograflari/\\{allPaths=\\*\\*\\}" \
    "Legacy return photo root path rule present"
  must_contain "${STORAGE_RULES}" "match /exit_fotograflari/\\{allPaths=\\*\\*\\}" \
    "Legacy exit photo root path rule present"
fi

print_header "4) Test bootstrap smoke checks"
if [[ -f "${TEST_BOOTSTRAP_FILE}" ]]; then
  pass "ViewInspector test file exists"
  must_contain "${TEST_BOOTSTRAP_FILE}" "EmptyStateView" \
    "ViewInspector test references EmptyStateView"
else
  fail "Missing ViewInspector bootstrap test file: ${TEST_BOOTSTRAP_FILE}"
fi

if [[ -f "${SNAPSHOT_TEST_FILE}" ]]; then
  pass "Snapshot smoke test file exists"
  must_contain "${SNAPSHOT_TEST_FILE}" "ENABLE_SNAPSHOT_TESTS" \
    "Snapshot test is environment-gated"
else
  warn "Snapshot smoke test file missing: ${SNAPSHOT_TEST_FILE}"
fi

print_header "5) Manual post-deploy prompts"
echo "- UK / new branch: open return + checkout QR from iOS, submit signature, confirm Firestore franchises/{id}/returnFormData|checkoutFormData/{token}."
echo "- Verify cross-tenant Firestore read denial (A -> B franchise) with non-admin user."
echo "- Verify cross-tenant Storage file read denial under /franchises/{otherFranchiseId}/..."
echo "- Verify same-franchise read/write success under /franchises/{ownFranchiseId}/..."
echo "- Verify globaladmin cross-franchise read succeeds where expected."
echo "- Run test bootstrap:"
echo "    xcodebuild test -scheme AracHasarKayit -destination 'platform=iOS Simulator,name=iPhone 16'"
echo "  Optional snapshot baseline:"
echo "    ENABLE_SNAPSHOT_TESTS=1 xcodebuild test -scheme AracHasarKayit -destination 'platform=iOS Simulator,name=iPhone 16'"

print_header "Result"
echo "PASS: ${PASS_COUNT}"
echo "WARN: ${WARN_COUNT}"
echo "FAIL: ${FAIL_COUNT}"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
  echo "Smoke verification FAILED."
  exit 1
fi

echo "Smoke verification PASSED."
