"""Maintainer-only chart fetch — fires only when rules_prometheus is the
root module. Consumers don't pull the chart .tgz.
"""

load("//tools:repositories.bzl", "prometheus_chart_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            prometheus_chart_repository(
                name = "prometheus_chart_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

prometheus_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
