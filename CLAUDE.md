# rules_prometheus

Bazel rules for Prometheus: build-time rule and config checks, rule unit
tests, a hermetic per-test Prometheus (runtime scrape targets, remote
write, OTLP), and a cluster install over the pinned prometheus-community
chart. It mirrors rules_alertmanager's structure; see DESIGN.md.

## Commit requirements

- All tests must pass before any commit with code changes
  (`bazel test //tests/...`; the kind smoke
  `//tests/install_smoke:smoke_test` too when install code changes).
- All documentation (`README.md`, `DESIGN.md`, `CLAUDE.md`) must be updated
  to reflect any code changes before committing: new rules, changed
  attributes, new public API surface, behaviour changes.

## Repo layout

```
rules_prometheus/
├── MODULE.bazel              # module; toolchain registration; dev deps (helm, itest, kind)
├── defs.bzl                  # public API re-exports
├── extensions.bzl            # `prometheus.version()` → prometheus_<ver>_<plat> repos (is_root-guarded)
├── private/
│   ├── versions.bzl          # PROMETHEUS_VERSIONS: url / sha256 / strip_prefix per platform
│   ├── repositories.bzl      # per-platform repo: release tarball → prometheus + promtool
│   ├── providers.bzl         # PrometheusBinaryInfo, PrometheusRulesInfo, PrometheusConfigInfo
│   ├── config.bzl            # prometheus_rules, prometheus_config (validation actions), prometheus_rules_test
│   ├── check.sh              # `check.sh rules|config` — lint flags, placeholders, promtool check
│   ├── rules_test.sh.tmpl    # `promtool test rules --junit=$XML_OUTPUT_FILE` in the staged dir
│   ├── server.bzl            # prometheus_server, prometheus_health_check, PrometheusServerInfo
│   ├── server.sh.tmpl        # runfiles resolution → launcher.py
│   ├── launcher.py           # port → stage + expand config → start → /-/ready → env file → SIGTERM
│   ├── test.bzl              # prometheus_test macro (+ default config with rules generator)
│   ├── prometheus_test_trampoline.sh  # server → env → test
│   ├── testlib.sh / testlib.py  # prom_query/value/wait/wait_alert/add_target/push/reload
│   ├── default_config.yml    # 1s intervals, self-scrape, file_sd (+ fallback_scrape_protocol)
│   ├── install.bzl           # prometheus_install(+config), prometheus_install_health_check
│   ├── install_config.awk    # replaces the chart ConfigMap's data with config + rule files
│   └── manifests/prometheus.yaml  # rendered chart, server only (committed; do not hand-edit)
├── toolchain/                # toolchain_type, per-platform toolchains, :current
├── config/prometheus-values.yaml  # render values: sub-charts off, fullnameOverride, flags
├── tools/                    # chart pin + render flow, update_checksums.sh
└── tests/
    ├── BUILD.bazel
    ├── analysis_tests.bzl    # install macros + server provider (analysis only)
    ├── testdata/             # config (APP_TARGET placeholder), rules, unit tests, bad inputs, .prom files
    ├── api_test.sh           # self-scrape, alert firing, recording rule, file_sd target, push, reload
    ├── default_config_test.sh  # default config + rules; args forwarded
    ├── server_test.sh        # env file keys, self-scrape, extra_args, SIGTERM, unset placeholder
    ├── health_check_test.sh
    ├── rules_unit_failure_test.sh  # wrong expectation fails; JUnit failure written
    ├── invalid_config_test.sh  # bad PromQL, duplicate rules (lint_fatal on/off), bad config, placeholder
    ├── install_config_test.sh  # configured manifest: only the ConfigMap changes
    ├── checksums_test.sh
    └── install_smoke/        # kind + prometheus_install(config) + promtool in the pod
```

## Key concepts

- **Rule files beside the config.** They are staged by basename, so
  `rule_files: ["*.rules.yml"]` works locally and at /etc/config in the
  cluster. `prometheus_rules_test` stages its test files and rule files
  together the same way.
- **Placeholders.** `${NAME}` is expanded from the server's environment.
  The launcher sets `PROMETHEUS_ADDRESS` (its own address, chosen before
  staging) and `PROMETHEUS_FILE_SD_DIR`. Build-time uses (the check and the
  install) take the target's `placeholders`, which have defaults for those
  two.
- **Runtime targets.** `prom_add_target` writes `<name>.json` into
  `PROMETHEUS_FILE_SD_DIR`; the default config re-reads it every 1 s.
  `fallback_scrape_protocol` is required for exporters that send no
  Content-Type (Prometheus 3).
- **Receivers.** The hermetic server always runs with remote-write, OTLP
  and lifecycle enabled. `promtool push metrics` takes the *base* URL (it
  appends /api/v1/write).
- **Shutdown.** The SIGTERM handler only terminates and arms a kill timer.
  It must not `wait()`, because the main thread holds Popen's wait lock.
- **Install.** Server only, pinned to namespace `prometheus`; every object
  is named `prometheus`; the health check waits for `deploy/prometheus`.
  The ConfigMap overlay drops the chart's Kubernetes service-discovery
  config.

## Public API

```python
load("@rules_prometheus//:defs.bzl",
    "prometheus_rules",            # srcs, deps, lint, lint_fatal
    "prometheus_config",           # src, rules, placeholders
    "prometheus_rules_test",       # srcs, rules, run
    "prometheus_server",           # config, ready_timeout, extra_args
    "prometheus_health_check",     # server
    "prometheus_test",             # srcs, config | rules, ready_timeout, extra_args, args, env, ...
    "prometheus_install",          # namespace, config, wait_timeout
    "prometheus_install_health_check",
    "PrometheusBinaryInfo", "PrometheusConfigInfo", "PrometheusRulesInfo", "PrometheusServerInfo",
)
```

## Development

```sh
bazel test //tests/...                                  # no container runtime
systemd-run --scope --user --property=Delegate=yes -- \
    bazel test //tests/install_smoke:smoke_test --test_output=streamed   # kind (podman)
tools/update_checksums.sh 3.15.1      # re-pin binaries; --check to verify
tools/render_prometheus.sh 29.40.3    # re-render the chart manifest
```

### Test results (last full run: 2026-11-03)

All 14 test targets pass on Linux x86_64 (Prometheus 3.15.1): 13 in
`//tests/...` and the kind smoke. Six runs of each server test in parallel
are clean. Invalid PromQL and duplicate rules in a `prometheus_rules` fail
`bazel build`; this was checked by hand.

| Test target | What it verifies | Result |
|---|---|---|
| `//tests:rules_unit_test` | promtool unit tests: alert after `for`, templated annotation, recording rule | PASSED |
| `//tests:rules_unit_failure_test` | wrong expectation fails, names the alert, writes a JUnit failure | PASSED |
| `//tests:invalid_config_test` | accepts good rules/config; rejects bad PromQL, duplicates (and only warns with lint_fatal off), bad config, unresolved placeholder | PASSED |
| `//tests:api_test` | self-scrape, placeholder target down → InstanceDown firing, recording rule, file_sd target scraped, remote-write push, reload | PASSED |
| `//tests:default_config_test` | default config loads the test's rules; args forwarded | PASSED |
| `//tests:server_test` | env file keys, self-scrape, extra_args, SIGTERM exit 0 + env removed, unset placeholder named | PASSED |
| `//tests:health_check_test` | exits non-zero without env file, 0 with | PASSED |
| `//tests:install_config_test` | configured manifest: config + rule file in the ConfigMap, rest unchanged | PASSED |
| `//tests:analysis_tests` (4) | install (with/without config), health check executables; server provider | PASSED |
| `//tests:checksums_test` | every pinned URL has a 64-hex SHA-256 | PASSED |
| `//tests/install_smoke:smoke_test` | kind: our scrape job up, rule mounted + evaluated, remote write in-cluster (podman locally, Docker in CI) | PASSED |

## Known limitations

- `python3` is required on the host for the server, test helpers and launcher.
- `prometheus_test` wraps `sh_test`; other languages use `prometheus_server`
  through rules_itest.
- The install is server only, and its namespace is fixed to `prometheus`.
