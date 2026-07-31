#!/usr/bin/env sh
# Tests for cluster-forget-safety.sh
# Run: ./tests/cluster-forget-safety.test.sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SAFETY_SCRIPT="$SCRIPT_DIR/../scripts/cluster-forget-safety.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== cluster-forget-safety.sh tests ==="
echo ""

# Test 1: missing cluster-id argument exits non-zero
echo "Test: missing cluster-id argument"
if ! "$SAFETY_SCRIPT" 2>/dev/null; then
  pass "exits non-zero when cluster-id is missing"
else
  fail "should exit non-zero when cluster-id is missing"
fi

# Test 2: script is executable (syntax check)
echo "Test: shell syntax check"
if sh -n "$SAFETY_SCRIPT" 2>/dev/null; then
  pass "valid shell syntax"
else
  fail "shell syntax error"
fi

# Test 3: script has set -eu (fail-fast behavior)
echo "Test: contains set -eu"
if grep -q "set -eu" "$SAFETY_SCRIPT"; then
  pass "contains set -eu for fail-fast"
else
  fail "missing set -eu"
fi

# Test 4: safety guard exists
echo "Test: contains safety guard logic"
if grep -q "cluster status" "$SAFETY_SCRIPT" && grep -q "ABORTED" "$SAFETY_SCRIPT"; then
  pass "contains safety guard with abort logic"
else
  fail "missing safety guard logic"
fi

# Test 5: error message exists for probe failure
echo "Test: contains error/warning for probe failure"
if grep -q "WARNING.*probe failed" "$SAFETY_SCRIPT" || grep -q "status probe failed" "$SAFETY_SCRIPT"; then
  pass "contains probe failure warning"
else
  fail "missing probe failure warning"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
