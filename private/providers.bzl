"""Providers exposed by rules_prometheus."""

PrometheusBinaryInfo = provider(
    doc = "Prometheus toolchain binaries (one upstream tarball).",
    fields = {
        "version":        "string — pinned Prometheus version",
        "prometheus_bin": "File — the prometheus server executable",
        "promtool_bin":   "File — the promtool CLI executable",
    },
)

PrometheusRulesInfo = provider(
    doc = "Checked Prometheus rule files (prometheus_rules).",
    fields = {
        "rules": "depset of File — rule files, each passed `promtool check rules`",
    },
)

PrometheusConfigInfo = provider(
    doc = "A checked Prometheus configuration (prometheus_config).",
    fields = {
        "config":          "File — the staged prometheus.yml, ${VAR} placeholders intact",
        "rules":           "list of File — rule files staged beside `config`",
        "files":           "depset of File — `config` + `rules` (one directory)",
        "resolved_config": "File — copy with placeholders replaced by their build-time " +
                           "`placeholders` values; what promtool checked",
        "placeholders":    "dict string→string — build-time value for each ${VAR}",
    },
)
