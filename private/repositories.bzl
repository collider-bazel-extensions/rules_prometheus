"""Per-platform Prometheus repo: downloads the release tarball at the
pinned sha and exposes `prometheus` + `promtool` as filegroups.
"""

load(":versions.bzl", "PROMETHEUS_VERSIONS")

_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "prometheus_bin",
    srcs = ["prometheus"],
)

filegroup(
    name = "promtool_bin",
    srcs = ["promtool"],
)

filegroup(
    name = "all_bins",
    srcs = [
        ":prometheus_bin",
        ":promtool_bin",
    ],
)
"""

def _impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform

    if version not in PROMETHEUS_VERSIONS:
        fail("rules_prometheus: unknown Prometheus version '{}'. Known: {}".format(
            version, sorted(PROMETHEUS_VERSIONS.keys()),
        ))
    pin = PROMETHEUS_VERSIONS[version].get(platform)
    if not pin:
        fail("rules_prometheus: platform '{}' missing for version {}".format(platform, version))

    rctx.download_and_extract(
        url = pin["url"],
        sha256 = pin["sha256"],
        stripPrefix = pin["strip_prefix"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD_TMPL)

prometheus_binary_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
