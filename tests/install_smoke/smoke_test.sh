#!/usr/bin/env bash
# Full E2E install smoke for prometheus_install(config = ...):
#
#   1. The itest chain (kind → prometheus_install) has applied the chart
#      (server only) with our ConfigMap and waited for deploy/prometheus.
#   2. kubectl exec promtool inside the server container (the image ships
#      it):
#      - our scrape job (smoke-self) is up — the running config is ours
#      - our rule file is mounted at /etc/config and evaluated
#      - remote write (enabled at render time) accepts a pushed sample.
set -euo pipefail

env_file="$TEST_TMPDIR/cluster.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")
NS=prometheus
fail() {
  echo "smoke: FAIL — $*" >&2
  "${KCTL[@]}" -n "$NS" get pods -o wide >&2 || true
  "${KCTL[@]}" -n "$NS" logs deploy/prometheus -c prometheus-server --tail=100 >&2 || true
  exit 1
}

"${KCTL[@]}" -n "$NS" wait pod -l app.kubernetes.io/component=server --for=condition=Ready --timeout=180s
KEXEC=("${KCTL[@]}" -n "$NS" exec deploy/prometheus -c prometheus-server --)
q() { "${KEXEC[@]}" promtool query instant http://127.0.0.1:9090 "$1"; }
wait_q() {
  local deadline=$(( $(date +%s) + 90 )) out
  until out=$(q "$1") && [[ -n "$out" ]]; do
    (( $(date +%s) < deadline )) || fail "no result for $1 within 90 s"
    sleep 2
  done
  echo "$out"
}

wait_q 'up{job="smoke-self"} == 1' >/dev/null
q 'up{job="kubernetes-apiservers"}' | grep -q . && fail "chart's default scrape jobs still running"
echo "smoke: running config is ours (job smoke-self up)"

"${KEXEC[@]}" ls /etc/config | grep -qx smoke.rules.yml || fail "smoke.rules.yml not mounted"
wait_q 'smoke:up:sum == 1' >/dev/null
echo "smoke: smoke.rules.yml mounted and evaluated (smoke:up:sum == 1)"

"${KEXEC[@]}" sh -c 'printf "# TYPE smoke_pushed gauge\nsmoke_pushed 5\n" > /tmp/smoke.prom && promtool push metrics --label=job=smoke-push http://127.0.0.1:9090 /tmp/smoke.prom' >/dev/null \
  || fail "remote write push"
wait_q 'smoke_pushed{job="smoke-push"} == 5' >/dev/null
echo "smoke: OK — remote write accepted a pushed sample"
