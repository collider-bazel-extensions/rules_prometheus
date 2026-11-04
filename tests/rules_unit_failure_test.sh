#!/usr/bin/env bash
# prometheus_rules_test with a wrong expectation fails with promtool's
# explanation of the mismatch.
set -euo pipefail

out="$TEST_TMPDIR/out.log"
rc=0
XML_OUTPUT_FILE="$TEST_TMPDIR/junit.xml" "$TEST_SRCDIR/$TEST_WORKSPACE/$1" >"$out" 2>&1 || rc=$?
cat "$out"
[[ $rc -ne 0 ]] || { echo "FAIL: wrong expectation passed" >&2; exit 1; }
grep -q "alertname: InstanceDown" "$out" || { echo "FAIL: failing alert not named" >&2; exit 1; }
grep -q "exp:\[\]" "$out" || grep -q "exp: \[\]" "$out" || { echo "FAIL: expectation not shown" >&2; exit 1; }
grep -q "<testsuites" "$TEST_TMPDIR/junit.xml" && grep -q "<failure" "$TEST_TMPDIR/junit.xml" \
  || { echo "FAIL: no JUnit failure written" >&2; exit 1; }
echo "PASS"
