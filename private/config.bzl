"""prometheus_rules, prometheus_config, prometheus_rules_test.

`prometheus_rules` checks rule files with `promtool check rules` (lint
`duplicate-rules`, fatal by default) as a validation action.

`prometheus_config` stages `prometheus.yml` and the rule files of its
`rules` targets into one directory (rule files beside the config under
their basenames, so `rule_files: ["*.rules.yml"]` resolves the same way
locally and in a cluster, where the chart mounts its ConfigMap at
/etc/config) and runs `promtool check config` as a validation action — a
broken config or rule file fails `bazel build`.

Configs may contain `${NAME}` placeholders. prometheus_server expands
them from its environment at start (and sets PROMETHEUS_ADDRESS and
PROMETHEUS_FILE_SD_DIR itself); the build-time check and
prometheus_install use the values in `placeholders`.

`prometheus_rules_test` runs `promtool test rules` over unit-test files,
with the rule files staged beside them by basename, and writes JUnit XML
for Bazel.
"""

load(":providers.bzl", "PrometheusConfigInfo", "PrometheusRulesInfo")

_TOOLCHAIN = "//toolchain:prometheus"

# Placeholders every config may use without declaring them; the server
# sets the real values at start.
DEFAULT_PLACEHOLDERS = {
    "PROMETHEUS_ADDRESS": "127.0.0.1:9090",
    "PROMETHEUS_FILE_SD_DIR": "/tmp/prometheus_file_sd",
}

def _rule_files(targets):
    return depset(transitive = [
        t[PrometheusRulesInfo].rules if PrometheusRulesInfo in t else t[DefaultInfo].files
        for t in targets
    ])

# ---- prometheus_rules -----------------------------------------------------------

def _prometheus_rules_impl(ctx):
    pt = ctx.toolchains[_TOOLCHAIN].prometheus
    stamp = ctx.actions.declare_file(ctx.label.name + ".rules_check")
    args = ctx.actions.args()
    args.add_all(["rules", pt.promtool_bin, stamp, ctx.attr.lint, "1" if ctx.attr.lint_fatal else "0"])
    args.add_all(ctx.files.srcs)
    ctx.actions.run(
        executable = ctx.executable._check,
        arguments = [args],
        inputs = ctx.files.srcs + [pt.promtool_bin],
        outputs = [stamp],
        mnemonic = "PromtoolCheckRules",
        progress_message = "promtool check rules %{label}",
    )
    rules = depset(ctx.files.srcs, transitive = [_rule_files(ctx.attr.deps)])
    return [
        DefaultInfo(files = rules),
        PrometheusRulesInfo(rules = rules),
        OutputGroupInfo(_validation = depset([stamp])),
    ]

prometheus_rules = rule(
    implementation = _prometheus_rules_impl,
    doc = """\
Prometheus recording / alerting rule files, checked with
`promtool check rules` at build time.

    prometheus_rules(
        name = "rules",
        srcs = glob(["*.rules.yml"]),
    )
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".yml", ".yaml"],
            mandatory = True,
            doc = "Rule files.",
        ),
        "deps": attr.label_list(
            providers = [PrometheusRulesInfo],
            doc = "Other prometheus_rules whose files come along (not re-checked).",
        ),
        "lint": attr.string(
            default = "duplicate-rules",
            doc = "promtool --lint value: duplicate-rules, all or none.",
        ),
        "lint_fatal": attr.bool(
            default = True,
            doc = "Fail the build on lint findings (promtool --lint-fatal).",
        ),
        "_check": attr.label(default = "//private:check", executable = True, cfg = "exec"),
    },
    toolchains = [_TOOLCHAIN],
)

# ---- prometheus_config ----------------------------------------------------------

def _stage(ctx, prefix, files, reserved):
    out = []
    seen = {}
    for f in files:
        if f.basename == reserved or f.basename in seen:
            fail("{}: staged file basenames must be unique and not {}: {}".format(
                ctx.label, reserved, f.basename))
        seen[f.basename] = True
        s = ctx.actions.declare_file(prefix + "/" + f.basename)
        ctx.actions.symlink(output = s, target_file = f)
        out.append(s)
    return out

def _prometheus_config_impl(ctx):
    pt = ctx.toolchains[_TOOLCHAIN].prometheus

    config = ctx.actions.declare_file(ctx.label.name + "/prometheus.yml")
    ctx.actions.symlink(output = config, target_file = ctx.file.src)
    rules = _stage(ctx, ctx.label.name, _rule_files(ctx.attr.rules).to_list(), "prometheus.yml")

    placeholders = dict(DEFAULT_PLACEHOLDERS)
    placeholders.update(ctx.attr.placeholders)

    resolved = ctx.actions.declare_file(ctx.label.name + ".resolved.yml")
    args = ctx.actions.args()
    args.add_all(["config", pt.promtool_bin, config, resolved])
    args.add_all(["{}={}".format(k, v) for k, v in sorted(placeholders.items())])
    ctx.actions.run(
        executable = ctx.executable._check,
        arguments = [args],
        inputs = [config, pt.promtool_bin] + rules,
        outputs = [resolved],
        mnemonic = "PromtoolCheckConfig",
        progress_message = "promtool check config %{label}",
    )

    files = depset([config] + rules)
    return [
        DefaultInfo(files = files),
        PrometheusConfigInfo(
            config = config,
            rules = rules,
            files = files,
            resolved_config = resolved,
            placeholders = placeholders,
        ),
        OutputGroupInfo(_validation = depset([resolved])),
    ]

prometheus_config = rule(
    implementation = _prometheus_config_impl,
    doc = """\
A Prometheus configuration plus its rule files, checked with
`promtool check config` at build time.

    prometheus_config(
        name = "config",
        src = "prometheus.yml",          # rule_files: ["*.rules.yml"]
        rules = [":rules"],
        placeholders = {"API_TARGET": "api:8080"},
    )
""",
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = [".yml", ".yaml"],
            doc = "prometheus.yml.",
        ),
        "rules": attr.label_list(
            allow_files = [".yml", ".yaml"],
            doc = "prometheus_rules targets (or rule files), staged beside " +
                  "the config by basename. The config's `rule_files` must " +
                  "name them, e.g. `rule_files: [\"*.rules.yml\"]`.",
        ),
        "placeholders": attr.string_dict(
            doc = "Build-time value for each `${NAME}` in the config. " +
                  "PROMETHEUS_ADDRESS and PROMETHEUS_FILE_SD_DIR have " +
                  "defaults. A placeholder with no value fails the build.",
        ),
        "_check": attr.label(default = "//private:check", executable = True, cfg = "exec"),
    },
    toolchains = [_TOOLCHAIN],
)

# ---- prometheus_rules_test ---------------------------------------------------------

def _rules_test_impl(ctx):
    pt = ctx.toolchains[_TOOLCHAIN].prometheus
    rules = _rule_files(ctx.attr.rules).to_list()
    staged = _stage(ctx, ctx.label.name + "_files", ctx.files.srcs + rules, "")

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = script,
        substitutions = {
            "__PROMTOOL__": pt.promtool_bin.short_path,
            "__DIR__":      staged[0].short_path.rsplit("/", 1)[0],
            "__TESTS__":    " ".join([f.basename for f in ctx.files.srcs]),
            "__RUN__":      " ".join(["--run=" + r for r in ctx.attr.run]),
        },
        is_executable = True,
    )
    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(files = [pt.promtool_bin] + staged),
    )]

_prometheus_rules_test = rule(
    implementation = _rules_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(allow_files = [".yml", ".yaml"], mandatory = True),
        "rules": attr.label_list(allow_files = [".yml", ".yaml"]),
        "run": attr.string_list(),
        "_tmpl": attr.label(default = "//private:rules_test.sh.tmpl", allow_single_file = True),
    },
    toolchains = [_TOOLCHAIN],
)

def prometheus_rules_test(name, srcs, rules = [], run = [], **kwargs):
    """Rule unit tests: `promtool test rules` over `srcs`.

    The test files and the rule files of `rules` are staged in one
    directory by basename, so a test file's `rule_files:` names them by
    basename. Results go to Bazel's test XML (JUnit).

    Args:
      name: target name.
      srcs: promtool unit-test files.
      rules: prometheus_rules targets (or rule files) under test.
      run: only run test groups whose names match these regexps
        (promtool --run).
      **kwargs: forwarded to the test rule (size, tags, ...).

    Example:

        prometheus_rules_test(
            name = "rules_test",
            srcs = ["alerts_test.yml"],     # rule_files: [alerts.rules.yml]
            rules = [":rules"],
        )
    """
    kwargs.setdefault("size", "small")
    _prometheus_rules_test(name = name, srcs = srcs, rules = rules, run = run, **kwargs)
