#!/usr/bin/env bash
# prometheus_test(rules = [...]) without a config: the default config
# (self-scrape, file_sd, 1s intervals) loads the rules. Args forwarded.
set -euo pipefail
# shellcheck disable=SC1090
source "$PROMETHEUS_TESTLIB"

[[ $# -eq 2 && "$1" == "one" && "$2" == "two words" ]] \
  || { echo "FAIL: args = [$*], want [one] [two words]" >&2; exit 1; }
echo "PASS: args forwarded"

prom_wait 'job:up:sum{job="prometheus"} == 1' >/dev/null \
  || { echo "FAIL: app.rules.yml not loaded by the default config" >&2; exit 1; }
echo "PASS: default config loads the test's rules"
