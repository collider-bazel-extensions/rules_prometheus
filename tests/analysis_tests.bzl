"""Analysis-time tests: the install macros (with and without a config)
and prometheus_server instantiate correctly, without a cluster."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_prometheus//:defs.bzl",
     "PrometheusServerInfo",
     "prometheus_install",
     "prometheus_install_health_check")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def _server_info_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, PrometheusServerInfo in target, "expected PrometheusServerInfo")
    info = target[PrometheusServerInfo]
    asserts.equals(env, "3.15.1", info.binary.version)
    asserts.equals(env, "prometheus.yml", info.config.config.basename)
    return analysistest.end(env)

_server_info_test = analysistest.make(_server_info_impl)

def analysis_test_suite(name):
    prometheus_install(name = name + "_install", tags = ["manual"])
    prometheus_install(name = name + "_install_cfg", config = ":test_config", tags = ["manual"])
    prometheus_install_health_check(name = name + "_health", tags = ["manual"])

    tests = []
    for subject in ["_install", "_install_cfg", "_health"]:
        _has_executable_test(
            name = name + subject + "_executable",
            target_under_test = ":" + name + subject,
        )
        tests.append(":" + name + subject + "_executable")
    _server_info_test(name = name + "_server_info", target_under_test = ":test_server")
    tests.append(":" + name + "_server_info")
    native.test_suite(name = name, tests = tests)
