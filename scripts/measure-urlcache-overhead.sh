#!/usr/bin/env bash
#
# Measure what an in-memory URLCache really costs, against what it says it holds.
#
# `URLSession.updates` gives its cache a memory capacity (`updatesCacheCapacity`;
# 64 MB when this was written), and URLCache keeps `currentMemoryUsage` under that
# number. But the number counts body BYTES, while what sits in memory is the body
# as CFNetwork assembled it: a dispatch_data_t made of the decoder's growing output
# buffers. Measured 2026-10-03 with this script: a cache reporting 63.8 MB was a
# 150 MB footprint on gzip bodies (about 2.3x) and 82 MB on identity ones. The installed app showed this first (2026-10-03: `leaks
# --referenceTree` put 138 MB of dispatch_data under `NSURLSession.updates`'
# NSURLCache after 4.9 days); this reproduces it with nothing but a local server.
#
# Two runs, same 200 KB body, 64 MB cache, distinct URLs so every response is a
# new entry:
#   identity  the body as-is                 (the cheap case)
#   gzip      the body gzip-encoded on wire  (what most feeds and pages send)
#
# Output: CSV per run — requests made, URLCache.currentMemoryUsage, and the
# process's physical footprint (what Activity Monitor shows).
#
# Usage: scripts/measure-urlcache-overhead.sh [capacity-MB] [requests]
set -euo pipefail

cap="${1:-64}"
requests="${2:-1000}"
work="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$work"' EXIT

cat >"$work/server.py" <<'EOF'
import gzip, http.server, random, sys
port, encoding = int(sys.argv[1]), sys.argv[2]
random.seed(1)
words = ["%x" % random.getrandbits(24) for _ in range(400)]
raw = (" ".join(random.choice(words) for _ in range(30000))).encode()[:200 * 1024]
body = gzip.compress(raw) if encoding == "gzip" else raw
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if encoding == "gzip":
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=3600")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
EOF

cat >"$work/client.swift" <<'EOF'
import Foundation

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return Double(info.phys_footprint) / 1_048_576
}

let args = CommandLine.arguments
let capacity = Int(args[1])! * 1_048_576
let requests = Int(args[2])!
let port = args[3]
let label = args[4]

let config = URLSessionConfiguration.default
let cache = URLCache(memoryCapacity: capacity, diskCapacity: 0)
config.urlCache = cache
let session = URLSession(configuration: config)

func row(_ n: Int) {
    let used = Double(cache.currentMemoryUsage) / 1_048_576
    print("\(label),\(n),\(String(format: "%.1f", used)),\(String(format: "%.1f", footprintMB()))")
}

row(0)
for i in 1...requests {
    _ = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/r\(i)")!)
    if i % 100 == 0 {
        // Let CFNetwork finish handing the response to the cache.
        try await Task.sleep(for: .milliseconds(300))
        row(i)
    }
}
EOF

swiftc -O "$work/client.swift" -o "$work/client"

echo "encoding,requests,urlcache_reported_mb,footprint_mb"
port=18800
for encoding in identity gzip; do
    port=$((port + 1))
    python3 "$work/server.py" "$port" "$encoding" &
    server=$!
    for _ in $(seq 1 50); do
        curl -s -o /dev/null "http://127.0.0.1:$port/ready" && break
        sleep 0.1
    done
    "$work/client" "$cap" "$requests" "$port" "$encoding"
    kill "$server"
    wait "$server" 2>/dev/null || true
done
