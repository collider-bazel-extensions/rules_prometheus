# rules_prometheus — design notes

rules_prometheus deliberately mirrors rules_alertmanager: same toolchain shape, validation actions, placeholder model, launcher, trampoline and install overlay. A team using both learns one set of conventions. These notes cover what is specific to Prometheus. Read rules_alertmanager's DESIGN.md for the shared reasoning.

## Three families

- **Rules and config, at build time.** Most Prometheus mistakes are in PromQL and rule files. `prometheus_rules` runs `promtool check rules` as a validation action, so a bad expression fails `bazel build //...` with no test to remember to run. The duplicate-rules lint is fatal by default: a duplicated recording rule is a bug, and it only warns upstream because promtool is used interactively.
- **Rule unit tests.** `promtool test rules` checks alerting and recording logic against synthetic series, with no server. `prometheus_rules_test` stages the test files and rule files flat by basename, so a test's `rule_files:` names them the way the files are written in the repo. It also passes `--junit=$XML_OUTPUT_FILE`, so each test group appears in Bazel's results.
- **Hermetic server and cluster install.** These follow the pattern of rules_alertmanager and rules_nats.

## Runtime scrape targets (file_sd)

A test usually wants Prometheus to scrape something the test itself starts: an exporter, or the service under test. Its port is chosen at run time, after Prometheus has started. The launcher therefore creates a per-server `file_sd` directory and exports it as `PROMETHEUS_FILE_SD_DIR`. The default config has a `file_sd` job over `${PROMETHEUS_FILE_SD_DIR}/*.json` that re-reads every 1 s. `prom_add_target NAME ADDR` writes `NAME.json` atomically, with `job=NAME`. Labels in a target group override `job_name`, so each target gets its own job.

This job sets `fallback_scrape_protocol: PrometheusText0.0.4`. Prometheus 3 refuses responses without a recognized `Content-Type` unless a fallback is set. Test exporters (`python -m http.server`, hand-rolled handlers) often send `application/octet-stream`, and such targets would show as down for a reason unrelated to the test. That was the first failure seen while building this.

The alternative was reloading the config with new `static_configs` through `/-/reload`. It would need config rewriting, and the 1 s file_sd refresh is simpler and doesn't race the reload.

## Placeholders set by the launcher

The launcher picks the port *before* staging the config. That lets it set `PROMETHEUS_ADDRESS` (for self-scrape) and `PROMETHEUS_FILE_SD_DIR` in the environment used for `${NAME}` expansion. If the port turns out to be taken, it re-stages with the next port. Both have build-time defaults in `DEFAULT_PLACEHOLDERS`, so configs that use them pass `promtool check config` without declaring them.

## Receivers on by default

The hermetic server passes `--web.enable-remote-write-receiver`, `--web.enable-otlp-receiver` and `--web.enable-lifecycle`. Tests of remote-write clients and OpenTelemetry exporters need the receivers. `prom_reload` needs lifecycle. None of them matter for an isolated per-test instance. The chart render enables remote write and lifecycle too; the smoke test pushes a sample in the cluster.

`promtool push metrics` appends `--remote-write.path` (default `/api/v1/write`) to the URL it's given. So `prom_push` passes the base URL. `PROMETHEUS_REMOTE_WRITE_URL` is the full endpoint, for other clients.

## `prometheus_test(rules = ...)`

Most tests want the default config plus their rules. Prometheus has no `rule_files` override flag, so the macro generates a config at build time: the default config plus `rule_files:` listing the rules' basenames. It runs that through `prometheus_config`, which checks it. Passing both `config` and `rules` is an error, because a config's rules belong in its own `prometheus_config(rules = ...)`.

## Check script: read-only inputs

The config check copies the staged directory to a scratch dir, resolves placeholders and runs `promtool check config` there; rule paths resolve relative to the config. Generated inputs, such as `prometheus_test`'s generated config, are read-only in Bazel's output tree. So the copies are made writable (`chmod -R u+w`) before the config is overwritten. rules_alertmanager v0.1.0 had the same latent bug, for generated alertmanager configs.

## Cluster install

- **Chart and render:** the prometheus-community `prometheus` chart is rendered server-only, since its sub-charts (Alertmanager, kube-state-metrics, node-exporter, pushgateway) are separate concerns. `server.fullnameOverride: prometheus` names the Deployment, Service and ConfigMap `prometheus`. The rollout wait is `deploy/prometheus`, a Deployment (the chart's default for a single server), not a StatefulSet.
- **Custom config:** `prometheus_install(config = ...)` swaps the data of that ConfigMap with the same awk overlay as rules_alertmanager (parameterized by ConfigMap name and first key). That drops the chart's Kubernetes service-discovery jobs and empty rule keys in favour of your config and rule files.

## Extension: root's versions plus rules_prometheus's own (v0.1.2)

The `prometheus` extension runs once for the whole build and sees every module's tags. Repos are named per version (`prometheus_<ver>_<plat>`), so it creates them for the root module's versions and for rules_prometheus's own, whose `MODULE.bazel` imports them and whose toolchains use them for every consumer; each once, so a repeated tag is harmless. Other modules' tags are ignored. Through v0.1.1 only the root's tags counted (`if not mod.is_root: continue`, against a collision that per-version names can't produce), so a root without `prometheus.version()` failed to resolve. An unsupported version now fails in the extension, naming `prometheus.version`.

CI's `consumer` job (`.github/consumer/check.sh`) runs rules_prometheus as a dependency from the commit's `git archive`: an untagged root resolves and runs a `prometheus_rules_test` (promtool 3.15.1), a repeated tag resolves, an unsupported version fails clearly, and `@rules_prometheus//...` loads.

## Release archive contents (v0.1.2)

`tests/` and `tools/` are `export-ignore` (`.gitattributes`): they load dev-only `rules_itest` / `rules_kind` / `rules_helm`, which made `@rules_prometheus//...` unloadable for consumers. `REPO.bazel` `ignore_directories` would also hide them from this repo's own `bazel test`. The dev-only `use_extension("//tools:extensions.bzl", ...)` is skipped for a non-root module. A `git_override` clone still contains both.

## What this repo does not (yet) do

- **Agent mode, Thanos and Mimir.** Remote write to a long-term store is a client config concern. rules_mimir installs Mimir.
- **Pushgateway, exporters and the operator.** There is no `ServiceMonitor` support and no prometheus-operator install. The chart is rendered without the operator's CRDs.
- **Non-shell `prometheus_test`.** Use `prometheus_server` + `prometheus_health_check` through rules_itest, and read the env file.
- **Install namespaces other than `prometheus`.** The rendered manifest pins the namespace.
