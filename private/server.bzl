"""prometheus_server + prometheus_health_check — hermetic Prometheus test
fixtures.

`prometheus_server` is a long-running executable (see launcher.py) that
starts one prometheus on a free 127.0.0.1 port, waits for GET /-/ready,
then writes `$TEST_TMPDIR/<name>.env`:

    PROMETHEUS_URL=http://127.0.0.1:<port>
    PROMETHEUS_HOST / PROMETHEUS_PORT
    PROMETHEUS_FILE_SD_DIR=<dir>        # drop <name>.json scrape targets here
    PROMETHEUS_REMOTE_WRITE_URL=<url>/api/v1/write
    PROMETHEUS_OTLP_URL=<url>/api/v1/otlp/v1/metrics
    PROMTOOL=/abs/path/to/promtool

and runs until SIGTERM. `prometheus_health_check` exits 0 iff that file
exists; it drops into `itest_service.health_check`.
"""

load(":providers.bzl", "PrometheusConfigInfo")

_TOOLCHAIN = "//toolchain:prometheus"

PrometheusServerInfo = provider(
    doc = "A prometheus_server target.",
    fields = {
        "binary": "PrometheusBinaryInfo: the toolchain's binaries.",
        "config": "PrometheusConfigInfo: the config it runs.",
    },
)

def _shell_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def check_timeout(label, value):
    """Validate a timeout attribute: a positive number of seconds."""
    raw = value.strip()
    digits = raw.replace(".", "", 1)
    if not raw or not digits.isdigit() or not digits.replace("0", ""):
        fail("{}: ready_timeout = {}: expected a positive number of seconds.".format(
            label, repr(value)))
    return raw

def _prometheus_server_impl(ctx):
    pt = ctx.toolchains[_TOOLCHAIN].prometheus
    cfg = ctx.attr.config[PrometheusConfigInfo]

    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = wrapper,
        substitutions = {
            "__NAME__":          ctx.label.name,
            "__CONFIG__":        cfg.config.short_path,
            "__LAUNCHER__":      ctx.file._launcher.short_path,
            "__PROMETHEUS__":    pt.prometheus_bin.short_path,
            "__PROMTOOL__":      pt.promtool_bin.short_path,
            "__READY_TIMEOUT__": check_timeout(ctx.label, ctx.attr.ready_timeout),
            "__EXTRA_ARGS__":    " ".join([_shell_quote(a) for a in ctx.attr.extra_args]),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [wrapper, ctx.file._launcher, pt.prometheus_bin, pt.promtool_bin],
        transitive_files = cfg.files,
    )
    return [
        DefaultInfo(executable = wrapper, runfiles = runfiles),
        PrometheusServerInfo(binary = pt, config = cfg),
    ]

prometheus_server = rule(
    implementation = _prometheus_server_impl,
    executable = True,
    doc = """\
Long-running Prometheus for tests and rules_itest compositions. Writes
`$TEST_TMPDIR/<name>.env` once /-/ready answers.

`${NAME}` placeholders in the config are expanded from the server's
environment at start, plus PROMETHEUS_ADDRESS and PROMETHEUS_FILE_SD_DIR,
which the launcher sets; an unset one fails the start, naming it.
""",
    attrs = {
        "config": attr.label(
            default = "//private:default_config",
            providers = [PrometheusConfigInfo],
            doc = "A prometheus_config. Default: 1s scrape/evaluation " +
                  "intervals, self-scrape, and file_sd over " +
                  "PROMETHEUS_FILE_SD_DIR.",
        ),
        "ready_timeout": attr.string(
            default = "30",
            doc = "Seconds to wait for /-/ready. A positive number.",
        ),
        "extra_args": attr.string_list(
            doc = "Extra prometheus flags, e.g. " +
                  "[\"--storage.tsdb.retention.time=1h\", \"--log.level=debug\"].",
        ),
        "_launcher": attr.label(default = "//private:launcher.py", allow_single_file = True),
        "_tmpl": attr.label(default = "//private:server.sh.tmpl", allow_single_file = True),
    },
    toolchains = [_TOOLCHAIN],
)

# ---- prometheus_health_check -----------------------------------------------------

def _prometheus_health_check_impl(ctx):
    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = wrapper,
        substitutions = {"__ENV_FILE_NAME__": ctx.attr.server.label.name + ".env"},
        is_executable = True,
    )
    return [DefaultInfo(executable = wrapper)]

prometheus_health_check = rule(
    implementation = _prometheus_health_check_impl,
    executable = True,
    attrs = {
        "server": attr.label(
            mandatory = True,
            providers = [PrometheusServerInfo],
            doc = "The prometheus_server this check pairs with.",
        ),
        "_tmpl": attr.label(default = "//private:health_check.sh.tmpl", allow_single_file = True),
    },
)
