#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no prometheus.version() in the root resolves, and a
#      prometheus_rules_test runs promtool at rules_prometheus's version
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming prometheus.version
#   4. @rules_prometheus//... loads (tests/ and tools/ are not shipped)
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_prometheus"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
version="$(sed -n 's/^prometheus.version(version = "\(.*\)")$/\1/p' "$src/MODULE.bazel")"
kubectl_commit="$(grep -A3 'module_name = "rules_kubectl"' "$src/MODULE.bazel" | sed -n 's/.*commit = "\([0-9a-f]*\)".*/\1/p')"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cp "$repo/tests/testdata/app.rules.yml" "$repo/tests/testdata/app_test.yml" "$c/"
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_prometheus//:defs.bzl", "prometheus_rules", "prometheus_rules_test")

prometheus_rules(
    name = "app_rules",
    srcs = ["app.rules.yml"],
)

prometheus_rules_test(
    name = "rules_unit_test",
    srcs = ["app_test.yml"],
    rules = [":app_rules"],
)
BUILD
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_prometheus")
local_path_override(module_name = "rules_prometheus", path = "$src")
bazel_dep(name = "rules_kubectl", version = "0.2.0")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "$kubectl_commit",
)
$2
MOD
    echo "$c"
}

# 1. No prometheus.version(): resolves; promtool runs at the library's version.
c="$(consumer untagged "")"
(cd "$c" && bazel mod deps >/dev/null)
(cd "$c" && bazel test //:rules_unit_test --test_output=errors)
promtool="$(cd "$c" && bazel info output_base)/external/rules_prometheus++prometheus+prometheus_${version//./_}_linux_amd64"
promtool="$(find "$promtool" -name promtool -type f | head -1)"
"$promtool" --version 2>&1 | tee "$work/untagged.out"
grep -q "version $version" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get promtool $version" >&2; exit 1; }
echo "PASS: untagged root resolves, promtool $version"

# 2. The same version twice in the root.
c="$(consumer twice "prometheus = use_extension(\"@rules_prometheus//:extensions.bzl\", \"prometheus\")
prometheus.version(version = \"$version\")
prometheus.version(version = \"$version\")")"
(cd "$c" && bazel mod deps >/dev/null)
echo "PASS: repeated identical prometheus.version resolves"

# 3. An unsupported version fails with a message naming prometheus.version.
c="$(consumer unsupported 'prometheus = use_extension("@rules_prometheus//:extensions.bzl", "prometheus")
prometheus.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'prometheus.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_prometheus//... >/dev/null)
echo "PASS: @rules_prometheus//... loads"
