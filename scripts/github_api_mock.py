#!/usr/bin/env python3
"""A local stand-in for api.github.com, for exercising the rate-limit gate.

A developer build (`make install`, which compiles `DUO_DEV_HOOKS`) sends every
GitHub API request here when started with DUO_GITHUB_API_MOCK pointing at it
(`GitHubAPIMock`). No real budget is spent and nothing between this Mac and
GitHub is touched. A release build cannot read the variable at all
(`scripts/check-no-dev-hooks.sh`).

    python3 scripts/github_api_mock.py --port 18765 --scenario exhausted --reset-in 300
    open -n /Applications/DuoUpdater.app --env DUO_GITHUB_API_MOCK=http://127.0.0.1:18765
    duo check   # with DUO_GITHUB_API_MOCK=http://127.0.0.1:18765 in its environment

Scenarios (switch while running: `curl -X POST 127.0.0.1:18765/__mock/scenario/<name>`):

  ok         /rate_limit has room; every endpoint answers 404 with room left
  exhausted  /rate_limit says 0 left; every endpoint 403, 0 left (primary limit)
  canary     /rate_limit has room; every endpoint 403, 0 left — the probe's
             window had room, the endpoint's did not
  secondary  /rate_limit has room; every endpoint 403 "secondary rate limit"
             with no rate-limit headers to wait by

`--reset-in` sets x-ratelimit-reset that many seconds from when the scenario
was set. Every request is logged to stdout and kept:

    curl 127.0.0.1:18765/__mock/requests        # JSON list: time, method, path, credential
    curl -X POST 127.0.0.1:18765/__mock/clear

The redirected requests carry no token: `X-Duo-Credential` says whether one
was sent (`token` / `anonymous`).
"""

from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCENARIOS = ("ok", "exhausted", "canary", "secondary")


class State:
    def __init__(self, scenario: str, reset_in: int) -> None:
        self.lock = threading.Lock()
        self.reset_in = reset_in
        self.requests: list[dict] = []
        self.set(scenario)

    def set(self, scenario: str) -> None:
        with self.lock:
            self.scenario = scenario
            self.reset_at = int(time.time()) + self.reset_in


def make_handler(state: State):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:  # we print our own line
            pass

        def send(self, status: int, body: dict | list, headers: dict[str, str] | None = None) -> None:
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            for key, value in (headers or {}).items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self) -> None:
            if self.path.startswith("/__mock/scenario/"):
                name = self.path.rsplit("/", 1)[-1]
                if name not in SCENARIOS:
                    return self.send(400, {"error": f"unknown scenario {name}", "known": SCENARIOS})
                state.set(name)
                print(f"-- scenario {name}, reset at {time.strftime('%H:%M:%S', time.localtime(state.reset_at))}", flush=True)
                return self.send(200, {"scenario": name, "reset": state.reset_at})
            if self.path == "/__mock/clear":
                with state.lock:
                    state.requests.clear()
                return self.send(200, {"cleared": True})
            self.do_GET()

        def do_GET(self) -> None:
            if self.path == "/__mock/requests":
                with state.lock:
                    return self.send(200, list(state.requests))
            credential = self.headers.get("X-Duo-Credential", "?")
            with state.lock:
                scenario, reset = state.scenario, state.reset_at
                state.requests.append({"time": time.time(), "method": self.command,
                                       "path": self.path, "credential": credential})
            print(f"{time.strftime('%H:%M:%S')} {self.command} {self.path} [{credential}] ({scenario})", flush=True)
            limit = 5000 if credential == "token" else 60
            if self.path.split("?")[0] == "/rate_limit":
                remaining = 0 if scenario == "exhausted" else limit // 2
                core = {"limit": limit, "remaining": remaining, "reset": reset, "used": limit - remaining}
                return self.send(200, {"resources": {"core": core}, "rate": core})
            headers = {"x-ratelimit-limit": str(limit), "x-ratelimit-resource": "core",
                       "x-ratelimit-reset": str(reset)}
            if scenario == "ok":
                headers["x-ratelimit-remaining"] = str(limit // 2)
                return self.send(404, {"message": "Not Found (github_api_mock)"}, headers)
            if scenario == "secondary":
                return self.send(403, {"message": "You have exceeded a secondary rate limit (github_api_mock)."})
            headers["x-ratelimit-remaining"] = "0"
            return self.send(403, {"message": "API rate limit exceeded (github_api_mock)."}, headers)

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--scenario", choices=SCENARIOS, default="exhausted")
    parser.add_argument("--reset-in", type=int, default=300, help="seconds until x-ratelimit-reset")
    args = parser.parse_args()
    state = State(args.scenario, args.reset_in)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(state))
    print(f"github_api_mock on http://127.0.0.1:{args.port}, scenario {args.scenario}, "
          f"reset at {time.strftime('%H:%M:%S', time.localtime(state.reset_at))}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
