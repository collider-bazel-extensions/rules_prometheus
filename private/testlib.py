#!/usr/bin/env python3
"""HTTP helpers behind testlib.sh (prometheus_test). Talks to
$PROMETHEUS_URL; no third-party modules.

  testlib.py query EXPR               print the instant-query result (JSON list)
  testlib.py value EXPR               print the first sample's value
  testlib.py wait EXPR TIMEOUT        wait until EXPR returns a sample; print result
  testlib.py wait-alert NAME STATE TIMEOUT
                                      wait until alert NAME is STATE (pending|firing)
  testlib.py add-target NAME ADDR [LABEL=VALUE...]
                                      write $PROMETHEUS_FILE_SD_DIR/NAME.json (job=NAME)
  testlib.py reload                   POST /-/reload
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request


def _get(path, params=None):
    url = os.environ["PROMETHEUS_URL"] + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=10) as r:
        body = json.load(r)
    if body.get("status") != "success":
        raise RuntimeError(f"{path}: {body}")
    return body["data"]


def query(expr):
    return _get("/api/v1/query", {"query": expr})["result"]


def main(argv):
    cmd = argv[0]
    if cmd == "query":
        print(json.dumps(query(argv[1])))
    elif cmd == "value":
        result = query(argv[1])
        if not result:
            print(f"prom_value: no sample for {argv[1]}", file=sys.stderr)
            return 1
        print(result[0]["value"][1])
    elif cmd == "wait":
        expr, timeout = argv[1], float(argv[2])
        deadline = time.monotonic() + timeout
        while True:
            result = query(expr)
            if result:
                print(json.dumps(result))
                return 0
            if time.monotonic() >= deadline:
                print(f"prom_wait: {expr} returned nothing within {timeout:g}s", file=sys.stderr)
                return 1
            time.sleep(0.5)
    elif cmd == "wait-alert":
        name, state, timeout = argv[1], argv[2], float(argv[3])
        deadline = time.monotonic() + timeout
        while True:
            alerts = [a for a in _get("/api/v1/alerts")["alerts"]
                      if a["labels"].get("alertname") == name]
            if any(a["state"] == state for a in alerts):
                print(json.dumps(alerts))
                return 0
            if time.monotonic() >= deadline:
                seen = sorted({a["state"] for a in alerts}) or ["absent"]
                print(f"prom_wait_alert: {name} not {state} within {timeout:g}s (is: {', '.join(seen)})",
                      file=sys.stderr)
                return 1
            time.sleep(0.5)
    elif cmd == "add-target":
        name, addr = argv[1], argv[2]
        labels = {"job": name}
        for kv in argv[3:]:
            k, _, v = kv.partition("=")
            labels[k] = v
        path = os.path.join(os.environ["PROMETHEUS_FILE_SD_DIR"], name + ".json")
        with open(path + ".tmp", "w") as f:
            json.dump([{"targets": [addr], "labels": labels}], f)
        os.replace(path + ".tmp", path)
    elif cmd == "reload":
        req = urllib.request.Request(os.environ["PROMETHEUS_URL"] + "/-/reload", method="POST")
        urllib.request.urlopen(req, timeout=30).close()
    else:
        print(f"testlib.py: unknown command {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
