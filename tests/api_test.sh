#!/usr/bin/env bash
# prometheus_test against tests/testdata/prometheus.yml + app.rules.yml.
set -euo pipefail
# shellcheck disable=SC1090
source "$PROMETHEUS_TESTLIB"

fail() { echo "FAIL: $*" >&2; exit 1; }
data="$(dirname "$0")/testdata"
[[ -f "$data/web.prom" ]] || data="$TEST_SRCDIR/_main/tests/testdata"

for v in PROMETHEUS_URL PROMETHEUS_HOST PROMETHEUS_PORT PROMETHEUS_FILE_SD_DIR \
         PROMETHEUS_REMOTE_WRITE_URL PROMETHEUS_OTLP_URL PROMTOOL; do
  [[ -n "${!v:-}" ]] || fail "\$$v not set"
done
[[ "$PROMETHEUS_REMOTE_WRITE_URL" == "$PROMETHEUS_URL/api/v1/write" ]] || fail "remote write URL"

# 1. Self-scrape via ${PROMETHEUS_ADDRESS}.
prom_wait 'up{job="prometheus"} == 1' >/dev/null || fail "self-scrape not up"
echo "PASS: self-scrape up"

# 2. The app target (APP_TARGET from env, a closed port) is down, and
#    InstanceDown fires after its `for: 2s`.
prom_wait 'up{job="app", instance="127.0.0.1:9"} == 0' >/dev/null || fail "app target not scraped as down"
alerts=$(prom_wait_alert InstanceDown firing) || fail "InstanceDown not firing"
grep -q '"summary": "127.0.0.1:9 of app is down"' <<<"$alerts" || fail "annotation not templated: $alerts"
echo "PASS: InstanceDown firing for the placeholder target"

# 3. Recording rule.
prom_wait 'job:up:sum{job="prometheus"} == 1' >/dev/null || fail "recording rule job:up:sum missing"
echo "PASS: recording rule evaluated"

# 4. Runtime scrape target via file_sd.
web_dir="$TEST_TMPDIR/web"
mkdir -p "$web_dir"
cp "$data/web.prom" "$web_dir/metrics"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$web_dir" >/dev/null 2>&1 &
web_pid=$!
trap 'kill $web_pid 2>/dev/null || true' EXIT
prom_add_target web "127.0.0.1:$port" team=test
v=$(prom_wait 'rules_prometheus_test_value{job="web", team="test"}' 30 >/dev/null && \
    prom_value 'rules_prometheus_test_value{job="web", team="test"}') || fail "file_sd target not scraped"
[[ "$v" == 7 ]] || fail "scraped value $v, want 7"
echo "PASS: runtime target scraped (value $v)"

# 5. Remote write.
prom_push "$data/push.prom" job=pusher >/dev/null || fail "promtool push failed"
v=$(prom_wait 'rules_prometheus_pushed{job="pusher"}' 30 >/dev/null && \
    prom_value 'rules_prometheus_pushed{job="pusher"}') || fail "pushed sample not queryable"
[[ "$v" == 42 ]] || fail "pushed value $v, want 42"
echo "PASS: remote-write push queryable (value $v)"

# 6. Lifecycle reload.
prom_reload || fail "reload failed"
echo "PASS: reload"
