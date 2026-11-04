#!/usr/bin/env bash
# prometheus_install(config = ...) replaces exactly the chart's
# `prometheus` ConfigMap data with the resolved config + rule files and
# leaves every other document byte-for-byte unchanged.
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
orig="$root/$1"
got="$root/$2"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $(grep -c '^kind: ' "$got") -eq $(grep -c '^kind: ' "$orig") ]] || fail "document count changed"
cm=$(awk '/^kind: ConfigMap/{p=1} p && /^---/{exit} p' "$got")
grep -q '^  prometheus.yml: |$' <<<"$cm" || fail "no prometheus.yml key"
grep -q '^  app.rules.yml: |$' <<<"$cm" || fail "rule file not added under its basename"
grep -q '^    rule_files:$' <<<"$cm" || fail "config body not indented under the key"
grep -q 'alert: InstanceDown' <<<"$cm" || fail "rule body missing"
grep -q '127.0.0.1:9"' <<<"$cm" || fail "APP_TARGET not resolved"
grep -q 'kubernetes-api-servers\|alerting_rules.yml' <<<"$cm" && fail "chart's default config still present"
grep -q '^  namespace: prometheus$' <<<"$cm" || fail "ConfigMap metadata lost"

strip_cm() { awk '/^kind: ConfigMap/{skip=1} /^---/{skip=0} !skip' "$1"; }
diff <(strip_cm "$orig") <(strip_cm "$got") || fail "documents other than the ConfigMap changed"
echo "PASS"
