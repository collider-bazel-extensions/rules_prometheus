"""Bzlmod extension. Single `version` tag — fetches the upstream
prometheus release tarball (prometheus + promtool) for each supported
platform.
"""

load("//private:repositories.bzl", "prometheus_binary_repo")
load("//private:versions.bzl", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),  # e.g. "3.15.1"
})

def _impl(mctx):
    # Only honor `version` tags from the root module — same is_root guard
    # as rules_nats / rules_kind. Without it, rules_prometheus's own
    # MODULE.bazel and the consumer would each emit
    # `@prometheus_<ver>_<plat>` repos and Bazel would collide them.
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            for plat in PLATFORMS.keys():
                prometheus_binary_repo(
                    name = "prometheus_{}_{}".format(
                        tag.version.replace(".", "_"),
                        plat,
                    ),
                    version = tag.version,
                    platform = plat,
                )

prometheus = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
