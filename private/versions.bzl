"""Prometheus binary pins.

One upstream tarball per platform carries both `prometheus` and
`promtool`:

    https://github.com/prometheus/prometheus/releases/download/v<ver>/prometheus-<ver>.<os>-<arch>.tar.gz
    (extracts to `prometheus-<ver>.<os>-<arch>/{prometheus,promtool}`)

SHA-256s are the release's published `sha256sums.txt`. Maintainer flow:

    tools/update_checksums.sh <ver>     # add / re-pin <ver> from sha256sums.txt
    tools/update_checksums.sh --check   # verify every pin, no writes

//tests:checksums_test fails on an empty or malformed value.
"""

PROMETHEUS_VERSIONS = {
    "3.15.1": {
        "linux_amd64": {
            "url": "https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.linux-amd64.tar.gz",
            "sha256": "6a726885328ad9efebbf36e876ce2fb6225468a71fd1e7ce3ba666d5f4d97a84",
            "strip_prefix": "prometheus-3.15.1.linux-amd64",
        },
        "linux_arm64": {
            "url": "https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.linux-arm64.tar.gz",
            "sha256": "ceb6d21493c37ca0b4513b147642797c68cf39a0f50a444d50e1e80c74f21b26",
            "strip_prefix": "prometheus-3.15.1.linux-arm64",
        },
        "darwin_amd64": {
            "url": "https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.darwin-amd64.tar.gz",
            "sha256": "c89fcb30045d8c394c9d93e96cbbee3aaf2448a48326b417e811eb4e528edf88",
            "strip_prefix": "prometheus-3.15.1.darwin-amd64",
        },
        "darwin_arm64": {
            "url": "https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.darwin-arm64.tar.gz",
            "sha256": "0d4d3d9837d27e4fcd0bd16d115b1b8d6732a4bf3e69107f1190d9ef653ae471",
            "strip_prefix": "prometheus-3.15.1.darwin-arm64",
        },
    },
}

PLATFORMS = {
    "linux_amd64":  ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "linux_arm64":  ["@platforms//os:linux", "@platforms//cpu:arm64"],
    "darwin_amd64": ["@platforms//os:osx",   "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:osx",   "@platforms//cpu:arm64"],
}
