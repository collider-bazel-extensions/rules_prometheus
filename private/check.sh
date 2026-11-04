#!/usr/bin/env bash
# Validation actions for prometheus_rules / prometheus_config (also used
# by //tests:invalid_config_test).
#
#   check.sh rules  <promtool> <stamp> <lint> <lint_fatal:0|1> <rule-file>...
#   check.sh config <promtool> <config> <out_resolved> [NAME=VALUE ...]
#
# `config` copies <config> (and the rule files beside it) to a scratch
# dir, replaces each ${NAME} with VALUE, fails if any ${...} is left, runs
# `promtool check config` (which also checks the rule files it names) and
# writes the resolved config to <out_resolved>.
set -euo pipefail

mode="$1"; promtool="$2"; shift 2
[[ "$promtool" == /* ]] || promtool="$PWD/$promtool"

case "$mode" in
rules)
    stamp="$1"; lint="$2"; fatal="$3"; shift 3
    flags=(--lint="$lint")
    [[ "$fatal" == 1 ]] && flags+=(--lint-fatal)
    if ! report=$("$promtool" check rules "${flags[@]}" "$@" 2>&1); then
        echo "prometheus_rules: promtool check rules failed:" >&2
        echo "$report" >&2
        exit 1
    fi
    echo "$report" > "$stamp"
    ;;
config)
    config="$1"; out="$2"; shift 2
    work="$(mktemp -d)"
    trap 'rm -r -f -- "$work"' EXIT
    cp -L "$(dirname "$config")"/* "$work"/ 2>/dev/null || true
    # Generated inputs are read-only; the copies must be writable.
    chmod -R u+w "$work"
    cp -L "$config" "$work/prometheus.yml"
    for pair in "$@"; do
        NAME="\${${pair%%=*}}" VALUE="${pair#*=}" awk '
            BEGIN { n = ENVIRON["NAME"]; v = ENVIRON["VALUE"] }
            {
                line = $0; res = ""
                while ((i = index(line, n)) > 0) {
                    res = res substr(line, 1, i - 1) v
                    line = substr(line, i + length(n))
                }
                print res line
            }' "$work/prometheus.yml" > "$work/resolved.yml"
        mv "$work/resolved.yml" "$work/prometheus.yml"
    done
    if left=$(grep -noE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$work/prometheus.yml"); then
        echo "prometheus_config: $config uses placeholders with no build-time value:" >&2
        echo "$left" | sed 's/^/  line /' >&2
        echo "Add them to the target's \`placeholders\` attribute." >&2
        exit 1
    fi
    # --syntax-only would skip rule files; a missing file_sd file is only a
    # warning, so runtime-populated discovery dirs are fine.
    if ! report=$(cd "$work" && "$promtool" check config prometheus.yml 2>&1); then
        echo "prometheus_config: promtool check config failed for $config:" >&2
        echo "$report" >&2
        exit 1
    fi
    cp "$work/prometheus.yml" "$out"
    ;;
*)
    echo "check.sh: unknown mode $mode" >&2
    exit 2
    ;;
esac
