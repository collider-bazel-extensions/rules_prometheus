#!/usr/bin/env bash
# private/check.sh: accepts the test config + rules; rejects invalid
# PromQL, duplicate rules (lint), an invalid config and an unresolved
# placeholder.
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
CHECK="$root/$1"; shift
PROMTOOL=""
for p in "$@"; do [[ "$p" == */promtool ]] && PROMTOOL="$(cd "$root" && realpath "$p")"; done
[[ -x "$PROMTOOL" ]] || { echo "FAIL: promtool not in runfiles" >&2; exit 1; }
data="$root/tests/testdata"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_fail() {  # <name> <pattern> <check args...>
  local name="$1" pattern="$2"; shift 2
  if "$CHECK" "$@" 2>"$TEST_TMPDIR/$name.log"; then fail "$name accepted"; fi
  cat "$TEST_TMPDIR/$name.log"
  grep -q "$pattern" "$TEST_TMPDIR/$name.log" || fail "$name: no '$pattern' in the error"
  echo "PASS: $name rejected"
}

"$CHECK" rules "$PROMTOOL" "$TEST_TMPDIR/ok.stamp" duplicate-rules 1 "$data/app.rules.yml" || fail "valid rules rejected"
stage="$TEST_TMPDIR/stage"; mkdir -p "$stage"
cp "$data/prometheus.yml" "$data/app.rules.yml" "$stage/"
"$CHECK" config "$PROMTOOL" "$stage/prometheus.yml" "$TEST_TMPDIR/ok.yml" \
  APP_TARGET=10.0.0.1:80 PROMETHEUS_ADDRESS=127.0.0.1:9090 PROMETHEUS_FILE_SD_DIR=/tmp/sd \
  || fail "valid config rejected"
grep -q '10.0.0.1:80' "$TEST_TMPDIR/ok.yml" || fail "placeholder not resolved in output"
echo "PASS: valid rules and config accepted"

expect_fail bad_promql "parse error" rules "$PROMTOOL" "$TEST_TMPDIR/x" duplicate-rules 1 "$data/bad.rules.yml"
expect_fail duplicate_rules "duplicate" rules "$PROMTOOL" "$TEST_TMPDIR/x" duplicate-rules 1 "$data/dup.rules.yml"
"$CHECK" rules "$PROMTOOL" "$TEST_TMPDIR/x" duplicate-rules 0 "$data/dup.rules.yml" 2>/dev/null \
  || fail "duplicate rules failed with lint_fatal = False"
echo "PASS: lint_fatal = False only warns"
expect_fail bad_config "scrape_interval\|often" config "$PROMTOOL" "$data/bad_config.yml" "$TEST_TMPDIR/x.yml"
expect_fail placeholder "MISSING_TARGET" config "$PROMTOOL" "$data/needs_placeholder.yml" "$TEST_TMPDIR/x.yml"
