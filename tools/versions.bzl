"""Maintainer-side: Prometheus Helm chart pin for the helm-render flow.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifest at
`//private/manifests:prometheus.yaml` is what consumers apply.

The chart is the prometheus-community `prometheus` chart, published as a
packaged `.tgz` on the helm-charts GitHub release. Its sub-charts
(alertmanager, kube-state-metrics, node-exporter, pushgateway) are
disabled in config/prometheus-values.yaml; only the server is rendered.

Update flow:
    1. Add an entry (chart_url + chart_sha256):
           curl -fsSL "<url>" | sha256sum
    2. Add (or update) a `helm_template` + `sh_binary` block in
       tools/BUILD.bazel for the new version.
    3. `tools/render_prometheus.sh <version>`.
"""

PROMETHEUS_CHART_VERSIONS = {
    "29.40.3": {
        # appVersion v3.15.1 (matches the pinned binaries).
        "chart_url":    "https://github.com/prometheus-community/helm-charts/releases/download/prometheus-29.40.3/prometheus-29.40.3.tgz",
        "chart_sha256": "901a2facca394c3c01d3e0e88b1d80a325a15c702d002de685e420d6909bd30f",
    },
}
