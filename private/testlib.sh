#!/usr/bin/env bash
# Helpers for prometheus_test scripts:  source "$PROMETHEUS_TESTLIB"
#
#   prom_query EXPR                 instant-query result as JSON
#   prom_value EXPR                 value of the first sample (fails if none)
#   prom_wait EXPR [TIMEOUT_S]      wait until EXPR returns a sample (default 60 s)
#   prom_wait_alert NAME [STATE] [TIMEOUT_S]
#                                   wait until alert NAME is STATE (default firing, 60 s)
#   prom_add_target NAME HOST:PORT [LABEL=VALUE...]
#                                   scrape HOST:PORT as job NAME (file_sd; picked up in ~1 s
#                                   with the default config's refresh_interval)
#   prom_push FILE [LABEL=VALUE...] push a text-format metrics file via remote write
#   prom_reload                     reload the config (POST /-/reload)

_prom_py() { python3 "$PROMETHEUS_TESTLIB_PY" "$@"; }

prom_query()      { _prom_py query "$1"; }
prom_value()      { _prom_py value "$1"; }
prom_wait()       { _prom_py wait "$1" "${2:-60}"; }
prom_wait_alert() { _prom_py wait-alert "$1" "${2:-firing}" "${3:-60}"; }
prom_add_target() { _prom_py add-target "$@"; }
prom_reload()     { _prom_py reload; }

prom_push() {
  local file="$1"; shift
  local kv label_flags=()
  for kv in "$@"; do label_flags+=("--label=$kv"); done
  "$PROMTOOL" push metrics "${label_flags[@]}" "$PROMETHEUS_URL" "$file"
}
