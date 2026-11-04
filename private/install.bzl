"""prometheus_install + prometheus_install_health_check — cluster
primitives wrapping rules_kubectl's `kubectl_apply` over the pinned,
pre-rendered prometheus-community `prometheus` chart (server only; the
sub-charts are disabled at render time).

Wait shape: Deployment `<namespace>/prometheus` rolled out.

With `config = ":my_config"` (a prometheus_config), the chart's
`prometheus` ConfigMap is replaced at build time by your config — its
placeholders resolved with the target's build-time `placeholders` values
— plus its rule files, keyed by basename and mounted beside the config
(/etc/config), so `rule_files: ["*.rules.yml"]` works unchanged.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")
load(":providers.bzl", "PrometheusConfigInfo")

_DEPLOY = "deploy/prometheus"
_MANIFEST = Label("//private/manifests:prometheus.yaml")

def _configured_manifest_impl(ctx):
    cfg = ctx.attr.config[PrometheusConfigInfo]
    out = ctx.actions.declare_file(ctx.label.name + ".yaml")
    data = [cfg.resolved_config] + cfg.rules
    ctx.actions.run_shell(
        inputs = data + [ctx.file.manifest, ctx.file._awk],
        outputs = [out],
        command = 'awk -v cm_name=prometheus -v first_key=prometheus.yml -v ndata="$1" -f "$2" "${@:4}" "$3" > "$OUT"',
        arguments = [str(len(data)), ctx.file._awk.path, ctx.file.manifest.path] + [f.path for f in data],
        env = {"OUT": out.path},
        mnemonic = "PrometheusInstallConfig",
        progress_message = "Applying %{label}'s config to the Prometheus chart manifest",
    )
    return [DefaultInfo(files = depset([out]))]

prometheus_configured_manifest = rule(
    implementation = _configured_manifest_impl,
    doc = "The pinned chart manifest with its ConfigMap replaced by `config`.",
    attrs = {
        "config": attr.label(mandatory = True, providers = [PrometheusConfigInfo]),
        "manifest": attr.label(default = _MANIFEST, allow_single_file = True),
        "_awk": attr.label(default = "//private:install_config.awk", allow_single_file = True),
    },
)

def prometheus_install(
        name,
        namespace = "prometheus",
        config = None,
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Prometheus chart (server only) into `namespace` and
    block until `deploy/prometheus` has rolled out.

    Drops into `itest_service.exe`.

    Args:
      name: target name.
      namespace: namespace to install into (created if missing). The
        rendered manifest is pinned to `prometheus`.
      config: optional prometheus_config to run instead of the chart's
        default config (which scrapes the Kubernetes API, nodes and pods).
      wait_timeout: rollout wait.
      **kwargs: forwarded to kubectl_apply (tags, visibility,
        wait_for_rollouts, ...).
    """
    manifest = _MANIFEST
    if config:
        manifest = ":" + name + "_manifest"
        prometheus_configured_manifest(
            name = name + "_manifest",
            config = config,
            tags = kwargs.get("tags"),
            visibility = ["//visibility:private"],
        )
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply(
        name = name,
        manifests = [manifest],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_rollouts = [_DEPLOY] + list(extra_rollouts),
        wait_timeout = wait_timeout,
        **kwargs
    )

def prometheus_install_health_check(
        name,
        namespace = "prometheus",
        **kwargs):
    """Readiness probe paired with `prometheus_install`: same wait shape
    with `--timeout=0s`. Drops into `itest_service.health_check`."""
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_rollouts = [_DEPLOY] + list(extra_rollouts),
        **kwargs
    )
