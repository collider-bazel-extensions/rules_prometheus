"""Bzlmod extension. Single `version` tag — fetches the upstream
prometheus release tarball (prometheus + promtool) for each supported
platform.
"""

load("//private:repositories.bzl", "prometheus_binary_repo")
load("//private:versions.bzl", "PLATFORMS", "PROMETHEUS_VERSIONS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),  # e.g. "3.15.1"
})

def _impl(mctx):
    # The extension runs once for the whole build and sees every module's
    # tags. Repos are named per version (`prometheus_<ver>_<plat>`), so the
    # root module's versions and rules_prometheus's own (which its
    # MODULE.bazel imports and its toolchains use, for every consumer) are
    # both created; each once, so a repeated tag is harmless. Other
    # modules' tags are ignored. Through v0.1.1 only the root's tags
    # counted, so a root without `prometheus.version()` failed to resolve
    # ("does not generate repository prometheus_3_15_1_linux_amd64").
    versions = {}
    for mod in mctx.modules:
        if mod.is_root or mod.name == "rules_prometheus":
            for tag in mod.tags.version:
                if tag.version not in PROMETHEUS_VERSIONS:
                    fail("rules_prometheus: prometheus.version(version = \"{}\") is not supported. Supported: {}".format(
                        tag.version,
                        ", ".join(sorted(PROMETHEUS_VERSIONS.keys())),
                    ))
                versions[tag.version] = None
    for version in versions.keys():
        for plat in PLATFORMS.keys():
            prometheus_binary_repo(
                name = "prometheus_{}_{}".format(version.replace(".", "_"), plat),
                version = version,
                platform = plat,
            )

prometheus = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
