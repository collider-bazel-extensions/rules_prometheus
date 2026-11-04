"""prometheus_toolchain — exposes the platform-resolved prometheus +
promtool binaries as a `ToolchainInfo`, so rules resolve them via
`ctx.toolchains["@rules_prometheus//toolchain:prometheus"]`.

`current_prometheus_toolchain` forwards the resolved binaries as a
plain target (files + runfiles) for `data = [...]` use in tests.
"""

load("//private:providers.bzl", "PrometheusBinaryInfo")

PROMETHEUS_TOOLCHAIN_TYPE = Label("//toolchain:prometheus")

def _toolchain_impl(ctx):
    info = PrometheusBinaryInfo(
        version        = ctx.attr.version,
        prometheus_bin = ctx.file.prometheus_bin,
        promtool_bin   = ctx.file.promtool_bin,
    )
    files = [ctx.file.prometheus_bin, ctx.file.promtool_bin]
    return [
        platform_common.ToolchainInfo(prometheus = info),
        DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files)),
    ]

prometheus_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version":        attr.string(mandatory = True),
        "prometheus_bin": attr.label(allow_single_file = True, mandatory = True),
        "promtool_bin":   attr.label(allow_single_file = True, mandatory = True),
    },
)

def _current_impl(ctx):
    info = ctx.toolchains[PROMETHEUS_TOOLCHAIN_TYPE].prometheus
    files = [info.prometheus_bin, info.promtool_bin]
    return [
        info,
        DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files)),
    ]

current_prometheus_toolchain = rule(
    implementation = _current_impl,
    toolchains = [PROMETHEUS_TOOLCHAIN_TYPE],
    doc = "The resolved prometheus + promtool, as files and runfiles.",
)
