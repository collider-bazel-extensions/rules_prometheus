#!/usr/bin/env bash
# prometheus_server lifecycle:
#   - writes the env file once /-/ready answers, with every key
#   - default config scrapes itself; extra_args reach prometheus
#   - SIGTERM: exits 0 and removes the env file
#   - an unset config placeholder fails the start, naming it
set -euo pipefail

root="$TEST_SRCDIR/$TEST_WORKSPACE"
SERVER="$root/$1"
PLACEHOLDER_SERVER="$root/$2"
env_file="$TEST_TMPDIR/test_server.env"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$SERVER" 2>"$TEST_TMPDIR/server.log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for _ in $(seq 300); do
  [[ -f "$env_file" ]] && break
  kill -0 "$pid" 2>/dev/null || { cat "$TEST_TMPDIR/server.log" >&2; fail "server exited early"; }
  sleep 0.1
done
[[ -f "$env_file" ]] || fail "env file not written within 30 s"
cat "$env_file"
for k in PROMETHEUS_URL PROMETHEUS_HOST PROMETHEUS_PORT PROMETHEUS_FILE_SD_DIR \
         PROMETHEUS_REMOTE_WRITE_URL PROMETHEUS_OTLP_URL PROMTOOL; do
  grep -q "^$k=." "$env_file" || fail "env file lacks $k"
done
# shellcheck disable=SC1090
source "$env_file"
[[ -d "$PROMETHEUS_FILE_SD_DIR" ]] || fail "file_sd dir missing"
[[ -x "$PROMTOOL" ]] || fail "PROMTOOL not executable"
deadline=$(( $(date +%s) + 60 ))
until [[ -n "$("$PROMTOOL" query instant "$PROMETHEUS_URL" 'up{job="prometheus"} == 1')" ]]; do
  (( $(date +%s) < deadline )) || fail "default config does not scrape itself"
  sleep 0.5
done
grep -q "level=debug\|level=DEBUG" "$TEST_TMPDIR/prometheus-test_server/prometheus.log" \
  || fail "extra_args --log.level=debug had no effect"
echo "PASS: env file, readiness, self-scrape, extra_args"

kill -TERM "$pid"
rc=0; wait "$pid" || rc=$?
[[ $rc -eq 0 ]] || fail "SIGTERM exit status $rc, want 0"
[[ ! -e "$env_file" ]] || fail "env file left after SIGTERM"
echo "PASS: SIGTERM shuts down cleanly"

rc=0
env -u MISSING_TARGET "$PLACEHOLDER_SERVER" 2>"$TEST_TMPDIR/placeholder.log" || rc=$?
cat "$TEST_TMPDIR/placeholder.log"
[[ $rc -ne 0 ]] || fail "server with an unset placeholder started"
grep -q "placeholders not set in the environment: MISSING_TARGET" "$TEST_TMPDIR/placeholder.log" \
  || fail "unset placeholder not named"
echo "PASS: unset placeholder is an error naming it"
