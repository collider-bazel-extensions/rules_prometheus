"""Public API for rules_prometheus.

Config + rules (build time):
  prometheus_rules         — rule files, checked by `promtool check rules`.
  prometheus_config        — prometheus.yml + rule files, checked by
                             `promtool check config` on every build.
  prometheus_rules_test    — rule unit tests (`promtool test rules`).

Hermetic server (test-time):
  prometheus_server        — long-running prometheus; writes
                             $TEST_TMPDIR/<name>.env when /-/ready.
  prometheus_health_check  — pairs with prometheus_server for itest_service.
  prometheus_test          — sh_test macro: auto-launched server with
                             runtime scrape targets, remote write and OTLP.

Cluster install (kind / production):
  prometheus_install              — applies the pinned Helm chart (server
                                    only), optionally with your config.
  prometheus_install_health_check — paired readiness probe.
"""

load("//private:config.bzl",
     _prometheus_config = "prometheus_config",
     _prometheus_rules = "prometheus_rules",
     _prometheus_rules_test = "prometheus_rules_test")
load("//private:install.bzl",
     _prometheus_install = "prometheus_install",
     _prometheus_install_health_check = "prometheus_install_health_check")
load("//private:providers.bzl",
     _PrometheusBinaryInfo = "PrometheusBinaryInfo",
     _PrometheusConfigInfo = "PrometheusConfigInfo",
     _PrometheusRulesInfo = "PrometheusRulesInfo")
load("//private:server.bzl",
     _PrometheusServerInfo = "PrometheusServerInfo",
     _prometheus_health_check = "prometheus_health_check",
     _prometheus_server = "prometheus_server")
load("//private:test.bzl", _prometheus_test = "prometheus_test")

prometheus_rules = _prometheus_rules
prometheus_config = _prometheus_config
prometheus_rules_test = _prometheus_rules_test
prometheus_server = _prometheus_server
prometheus_health_check = _prometheus_health_check
prometheus_test = _prometheus_test
prometheus_install = _prometheus_install
prometheus_install_health_check = _prometheus_install_health_check

PrometheusBinaryInfo = _PrometheusBinaryInfo
PrometheusConfigInfo = _PrometheusConfigInfo
PrometheusRulesInfo = _PrometheusRulesInfo
PrometheusServerInfo = _PrometheusServerInfo
