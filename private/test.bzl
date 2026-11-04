"""prometheus_test — sh_test macro with an auto-launched Prometheus.

Each target gets its own prometheus_server (own port, own TSDB, own
file_sd dir), so tests are safe under `--jobs=N`.

The trampoline (prometheus_test_trampoline.sh) starts the server, waits
for its env file, sources it (PROMETHEUS_URL, PROMETHEUS_HOST,
PROMETHEUS_PORT, PROMETHEUS_FILE_SD_DIR, PROMETHEUS_REMOTE_WRITE_URL,
PROMETHEUS_OTLP_URL, PROMTOOL), exports PROMETHEUS_TESTLIB (prom_query,
prom_wait, prom_value, prom_add_target, prom_push, prom_wait_alert,
prom_reload) and runs the test with the target's args.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":config.bzl", "prometheus_config")
load(":providers.bzl", "PrometheusRulesInfo")
load(":server.bzl", "prometheus_server")

def _default_config_with_rules_impl(ctx):
    names = []
    for t in ctx.attr.rules:
        files = t[PrometheusRulesInfo].rules if PrometheusRulesInfo in t else t[DefaultInfo].files
        names.extend([f.basename for f in files.to_list()])
    out = ctx.actions.declare_file(ctx.label.name + ".yml")
    ctx.actions.run_shell(
        inputs = [ctx.file.template],
        outputs = [out],
        command = 'out="$1"; tmpl="$2"; shift 2; { cat "$tmpl"; echo "rule_files:"; for n in "$@"; do echo "  - \\"$n\\""; done; } > "$out"',
        arguments = [out.path, ctx.file.template.path] + names,
    )
    return [DefaultInfo(files = depset([out]))]

_default_config_with_rules = rule(
    implementation = _default_config_with_rules_impl,
    attrs = {
        "template": attr.label(default = "//private:default_config.yml", allow_single_file = True),
        "rules": attr.label_list(allow_files = [".yml", ".yaml"]),
    },
)

def prometheus_test(
        name,
        srcs,
        config = None,
        rules = None,
        ready_timeout = 30,
        extra_args = None,
        deps = None,
        data = None,
        args = None,
        size = "medium",
        timeout = None,
        tags = None,
        **kwargs):
    """sh_test against an auto-launched Prometheus.

    Args:
      name: target name.
      srcs: the test script (one file).
      config: a prometheus_config. Default: the server default
        (1s intervals, self-scrape, file_sd) loading `rules`.
      rules: prometheus_rules for the default config. Use `config`'s own
        `rules` when you pass a config.
      ready_timeout: seconds to wait for the server's /-/ready.
      extra_args: extra prometheus flags.
      deps: forwarded to the inner sh_binary.
      data: forwarded to the inner sh_binary.
      args: arguments for the test script.
      size: sh_test size. Default "medium".
      timeout: sh_test timeout.
      tags: tags for the sh_test (helper targets also get "manual").
      **kwargs: forwarded to sh_test (env, env_inherit, flaky, ...).
    """
    tags = tags or []
    if config and rules:
        fail("prometheus_test {}: pass rules through the prometheus_config, not both".format(name))
    if config == None:
        if rules:
            _default_config_with_rules(
                name = name + "_config_src",
                rules = rules,
                tags = ["manual"],
                testonly = True,
            )
            prometheus_config(
                name = name + "_config",
                src = ":" + name + "_config_src",
                rules = rules,
                tags = ["manual"],
                testonly = True,
            )
            config = ":" + name + "_config"
        else:
            config = Label("//private:default_config")

    server_name = name + "_prometheus"
    prometheus_server(
        name = server_name,
        config = config,
        ready_timeout = str(ready_timeout),
        extra_args = extra_args or [],
        tags = tags + ["manual"],
        testonly = True,
    )

    inner_name = name + "_inner"
    sh_binary(
        name = inner_name,
        srcs = srcs,
        deps = deps,
        data = data,
        tags = tags + ["manual"],
        testonly = True,
    )

    sh_test(
        name = name,
        srcs = [Label("//private:prometheus_test_trampoline.sh")],
        args = [
            "$(rootpath :{})".format(server_name),
            "$(rootpath :{})".format(inner_name),
            server_name,
            "$(rootpath {})".format(Label("//private:testlib.sh")),
            "$(rootpath {})".format(Label("//private:testlib.py")),
        ] + (args or []),
        data = [
            ":" + server_name,
            ":" + inner_name,
            Label("//private:testlib.sh"),
            Label("//private:testlib.py"),
        ],
        size = size,
        timeout = timeout,
        tags = tags,
        **kwargs
    )
