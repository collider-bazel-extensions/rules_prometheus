# rules_prometheus

Bazel rules for [Prometheus](https://prometheus.io). They check configs and rules at build time, unit-test alerting and recording rules, run a hermetic Prometheus in tests, and install Prometheus into a cluster. Three families in one repo:

- **Config + rules (build time)**
  - `prometheus_rules` — rule files. `promtool check rules` (with the duplicate-rules lint, fatal by default) runs as a validation action, so broken PromQL fails `bazel build`.
  - `prometheus_config` — `prometheus.yml` plus its rule files, checked with `promtool check config` on every build.
  - `prometheus_rules_test` — rule unit tests (`promtool test rules`), reported as JUnit XML in Bazel's test results.
- **Hermetic server (test-time)**
  - `prometheus_server` — long-running `prometheus` on a free port; writes `$TEST_TMPDIR/<name>.env` once `/-/ready` answers.
  - `prometheus_health_check` — pairs with `prometheus_server` for `itest_service`.
  - `prometheus_test` — sh_test macro. It auto-launches a server that:
    - scrapes targets your test registers at runtime;
    - accepts remote write and OTLP;
    - loads your rules.
- **Cluster install (kind / production)**
  - `prometheus_install` — applies the pinned prometheus-community chart (server only), optionally with your `prometheus_config`, and waits for `deploy/prometheus`.
  - `prometheus_install_health_check` — paired readiness probe.

No host `prometheus`, `promtool`, `helm` or Go needed: binaries come from the pinned, SHA-256-verified upstream release tarballs.

## Install (Bzlmod)

```python
bazel_dep(name = "rules_prometheus", version = "0.1.1")
git_override(
    module_name = "rules_prometheus",
    remote = "https://github.com/collider-bazel-extensions/rules_prometheus",
    commit = "e589ff5fad0ae5e81f70822f3130b13029b7c509",  # v0.1.1
)

prometheus = use_extension("@rules_prometheus//:extensions.bzl", "prometheus")
prometheus.version(version = "3.15.1")
use_repo(
    prometheus,
    "prometheus_3_15_1_darwin_amd64",
    "prometheus_3_15_1_darwin_arm64",
    "prometheus_3_15_1_linux_amd64",
    "prometheus_3_15_1_linux_arm64",
)
register_toolchains("@rules_prometheus//toolchain:all")
```

To pin by archive and integrity instead of a git commit, replace the `git_override` with:

```python
archive_override(
    module_name = "rules_prometheus",
    urls = ["https://github.com/collider-bazel-extensions/rules_prometheus/archive/refs/tags/v0.1.1.tar.gz"],
    strip_prefix = "rules_prometheus-0.1.1",
    integrity = "sha256-KIi2GiRpxnYY7nqIPKHpodKJt2tO7HKG7lC3+sVH4kM=",
)
```

rules_kubectl isn't in the BCR either, so a consumer overrides it too:

```python
bazel_dep(name = "rules_kubectl", version = "0.2.0")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "81b60ab80df46b64c612f2576ffef0a7af98ccb6",  # v0.2.0
)
```

The `prometheus` extension only honours the root module's `version` tags (the `mod.is_root` guard used across this organization), so declare it in your own `MODULE.bazel`. The install primitives pull in [rules_kubectl](https://github.com/collider-bazel-extensions/rules_kubectl). The server and test rules need `python3` on the host.

## Rules, config and rule unit tests

```python
load("@rules_prometheus//:defs.bzl",
    "prometheus_config", "prometheus_rules", "prometheus_rules_test")

prometheus_rules(
    name = "rules",
    srcs = glob(["*.rules.yml"]),
)

prometheus_rules_test(
    name = "rules_test",
    srcs = ["alerts_test.yml"],        # rule_files: [alerts.rules.yml]  (basenames)
    rules = [":rules"],
)

prometheus_config(
    name = "config",
    src = "prometheus.yml",            # rule_files: ["*.rules.yml"]
    rules = [":rules"],
    placeholders = {"API_TARGET": "api.default.svc:8080"},
)
```

- **Rule unit tests:** `prometheus_rules_test` stages the test files and the rule files side by side by basename, so a test's `rule_files:` names rules by basename. `run = ["regexp"]` limits which test groups run. A failing test prints promtool's diff of expected against actual alerts and samples.
- **Rule files beside the config:** `prometheus_config` stages its rule files beside `prometheus.yml`. A `rule_files: ["*.rules.yml"]` glob therefore resolves the same way locally and in the cluster, where the chart mounts them at `/etc/config`.
- **`${NAME}` placeholders:**
  - `prometheus_server` expands them from its environment at start. It also sets two itself:
    - `PROMETHEUS_ADDRESS` — its own `127.0.0.1:<port>`, for self-scrape;
    - `PROMETHEUS_FILE_SD_DIR` — the directory for runtime targets.
  - An unset placeholder fails the start and names it.
  - The build-time check and `prometheus_install` use the values in `placeholders`. A placeholder with no value fails the build.

| Rule | Attributes |
|---|---|
| `prometheus_rules` | `srcs`; `deps` (other `prometheus_rules`); `lint` (`"duplicate-rules"`, `"all"`, `"none"`); `lint_fatal` (default `True`) |
| `prometheus_config` | `src`; `rules` (`prometheus_rules` or files); `placeholders` |
| `prometheus_rules_test` | `srcs` (test files); `rules`; `run` |

## Hermetic server

### `prometheus_test`

```python
load("@rules_prometheus//:defs.bzl", "prometheus_test")

prometheus_test(
    name = "metrics_test",
    srcs = ["metrics_test.sh"],
    rules = [":rules"],                 # or config = ":config" (with its own rules)
    data = [":my_exporter"],
)
```

```sh
# metrics_test.sh
source "$PROMETHEUS_TESTLIB"
./my_exporter --listen=127.0.0.1:9100 &
prom_add_target exporter 127.0.0.1:9100 team=a    # scraped as job="exporter" within ~1 s
prom_wait 'up{job="exporter"} == 1'
[[ "$(prom_value 'my_metric{job="exporter"}')" == 3 ]]
prom_wait_alert MyAlert firing
prom_push samples.prom job=batch                   # remote write
```

Environment of the test:

| Variable | |
|---|---|
| `PROMETHEUS_URL`, `PROMETHEUS_HOST`, `PROMETHEUS_PORT` | the server |
| `PROMETHEUS_FILE_SD_DIR` | drop `<name>.json` [file_sd](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#file_sd_config) target groups here (`prom_add_target` does it for you) |
| `PROMETHEUS_REMOTE_WRITE_URL` | `…/api/v1/write` |
| `PROMETHEUS_OTLP_URL` | `…/api/v1/otlp/v1/metrics` (point an OTel SDK / collector here) |
| `PROMTOOL` | the toolchain's promtool |
| `PROMETHEUS_TESTLIB` | `prom_query`, `prom_value`, `prom_wait`, `prom_wait_alert`, `prom_add_target`, `prom_push`, `prom_reload` |

**Default config** (`prometheus_server` with no `config`):
- 1 s scrape and evaluation intervals;
- a self-scrape (`job="prometheus"`);
- a `file_sd` job over `PROMETHEUS_FILE_SD_DIR` that re-reads every 1 s, with `fallback_scrape_protocol: PrometheusText0.0.4`. Prometheus 3 otherwise refuses targets that send no `Content-Type`, which ad-hoc test exporters often don't.

`prometheus_test(rules = ...)` appends the rules to this default as `rule_files`.

| `prometheus_test` argument | Default | |
|---|---|---|
| `srcs` | — | the test script |
| `config` / `rules` | default config, no rules | one or the other |
| `ready_timeout` | `30` | seconds to wait for `/-/ready` |
| `extra_args` | `[]` | extra `prometheus` flags |
| `args`, `env`, `data`, `deps`, `size`, `timeout`, `tags`, … | | as for `sh_test` |

The server runs with remote write, OTLP and lifecycle (`/-/reload`) enabled. Each test gets its own server: its own port, TSDB and target directory. Tests are safe under `--jobs=N`.

### `prometheus_server` + `prometheus_health_check` (rules_itest)

```python
prometheus_server(name = "prom", config = ":config", tags = ["manual"])
prometheus_health_check(name = "prom_health", server = ":prom", tags = ["manual"])

itest_service(
    name = "prom_svc",
    exe = ":prom",
    health_check = ":prom_health",
    env = {"API_TARGET": "127.0.0.1:8080"},
)
```

The server writes `$TEST_TMPDIR/prom.env` with the variables above. It stops on SIGTERM and removes the file. Its attributes are `config`, `ready_timeout` (`"30"`) and `extra_args`.

## Cluster install

```python
load("@rules_prometheus//:defs.bzl", "prometheus_install", "prometheus_install_health_check")

prometheus_install(name = "prom_install", config = ":config", tags = ["manual"])
prometheus_install_health_check(name = "prom_install_health", tags = ["manual"])

itest_service(
    name = "prom_install_svc",
    exe = ":prom_install",
    health_check = ":prom_install_health",
    deps = [":kind_svc"],
    tags = ["manual"],
)
```

- **What's rendered:** only the server; the chart's alertmanager, kube-state-metrics, node-exporter and pushgateway sub-charts are disabled. Use [rules_alertmanager](https://github.com/collider-bazel-extensions/rules_alertmanager) for Alertmanager. Remote write and lifecycle are enabled.
- **Default config:** without `config`, the chart's own configuration applies. It scrapes the Kubernetes API, nodes and annotated pods.
- **Your config:** with `config`, the chart's `prometheus` ConfigMap is replaced at build time by your resolved config and rule files, mounted together at `/etc/config`. The configmap-reload sidecar picks up later edits to the ConfigMap.
- **Namespace:** the rendered manifest is pinned to the `prometheus` namespace.
- **Smoke test:** `tests/install_smoke/` deploys to kind and runs promtool in the pod. It checks that our scrape job is up, that our rule is evaluated, and that remote write accepts a pushed sample.

## Pinned versions

| Component | Version | Source |
|---|---|---|
| prometheus + promtool | `3.15.1` | https://github.com/prometheus/prometheus/releases (`sha256sums.txt`) |
| Helm chart | `prometheus-29.40.3` (appVersion v3.15.1) | https://github.com/prometheus-community/helm-charts/releases |

Maintainer flows:
- **New binaries:** `tools/update_checksums.sh <version>` pins the four platforms from `sha256sums.txt`, cross-checked against the downloads. `--check` verifies the pins without writing anything.
- **Chart:** edit `tools/versions.bzl` and `tools/BUILD.bazel`, then run `tools/render_prometheus.sh <version>`. No host helm is needed. CI fails if the committed manifest drifts from the render.

## Development

```sh
bazel test //tests/...                                                # no container runtime
bazel test //tests/install_smoke:smoke_test --test_output=streamed    # needs Docker or podman
```

See [DESIGN.md](DESIGN.md) for the architecture and trade-offs.
