#!/usr/bin/env bash
#
# Sample a running DuoUpdater's memory and CPU over time, as CSV.
#
# Why this exists: a single footprint number says nothing about whether memory
# is growing (a leak) or has reached a ceiling (a cache filling up). Only a time
# series across many check rounds tells those apart. The first measurement
# (2026-10-03) needed exactly that: a 4.9-day-old process at 256 MB turned out to
# be a cache at its ceiling, not a leak, and a fresh process grew by about 3 MB
# an hour until windows were opened.
#
# Every column comes from a tool that ships with macOS — no Instruments, no
# debug build, no entitlement. `heap` and `vmmap` read a Developer ID build from
# the same user without get-task-allow; they suspend the target for the length
# of the read (~2 s for `heap` at ~370k allocations), which is why `heap` runs
# only every Nth sample.
#
#   ts             ISO-8601 local time of the sample
#   uptime_s       seconds since the process started
#   footprint_mb   physical footprint (what Activity Monitor's "Memory" shows)
#   peak_mb        lifetime peak footprint
#   rss_mb         resident size — lower than footprint once pages are compressed
#   cpu_s          cumulative user+system CPU seconds
#   threads        thread count
#   fds            open file descriptors
#   dd_count       dispatch_data_t objects  ┐ heap samples only; empty otherwise.
#   dd_mb          dispatch_data_t bytes    │ dispatch_data is what URLCache holds
#   cached_resp    __CFCachedURLResponse    │ response bodies in, so these three
#   malloc_mb      all malloc zones         ┘ track the cache directly
#
# Usage:
#   scripts/measure-runtime.sh [--pid N] [--interval S] [--duration S] [--heap-every N] [--out FILE]
#
# Defaults: the running DuoUpdater, a sample every 60 s for an hour, `heap` on
# every 5th sample, CSV to stdout. Ctrl-C stops early; the CSV stays valid.
set -uo pipefail

pid=""
interval=60
duration=3600
heap_every=5
out=""

while (( $# )); do
    case "$1" in
        --pid) pid="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        --duration) duration="$2"; shift 2 ;;
        --heap-every) heap_every="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$pid" ]]; then
    # The app's own executable, not the CLI or a test host that happens to share
    # the name.
    pid="$(pgrep -f '/DuoUpdater.app/Contents/MacOS/DuoUpdater$' | head -1)"
fi
if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    echo "no running DuoUpdater (pass --pid)" >&2
    exit 1
fi

[[ -n "$out" ]] && exec >"$out"

# `vmmap --summary` prints e.g. "Physical footprint:         256.5M"; the unit
# can be K, M or G.
to_mb() {
    awk -v v="$1" 'BEGIN {
        n = v + 0; u = substr(v, length(v))
        if (u == "K") n /= 1024; else if (u == "G") n *= 1024
        printf "%.1f", n }'
}

# `ps -o time` is [[dd-]hh:]mm:ss.cc.
cpu_seconds() {
    ps -o time= -p "$pid" | awk '{
        t = $1; d = 0
        if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
        n = split(t, p, ":"); s = 0
        for (i = 1; i <= n; i++) s = s * 60 + p[i]
        printf "%.2f", s + d * 86400 }'
}

echo "ts,uptime_s,footprint_mb,peak_mb,rss_mb,cpu_s,threads,fds,dd_count,dd_mb,cached_resp,malloc_mb"

start=$(date +%s)
n=0
while kill -0 "$pid" 2>/dev/null; do
    summary="$(vmmap --summary "$pid" 2>/dev/null)"
    fp="$(awk '/^Physical footprint:/ {print $3}' <<<"$summary")"
    peak="$(awk '/^Physical footprint \(peak\):/ {print $4}' <<<"$summary")"
    rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
    etime="$(ps -o etime= -p "$pid" | awk '{
        t = $1; d = 0
        if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
        n = split(t, p, ":"); s = 0
        for (i = 1; i <= n; i++) s = s * 60 + p[i]
        print s + d * 86400 }')"
    threads="$(( $(ps -M -p "$pid" | wc -l) - 1 ))"
    fds="$(lsof -p "$pid" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"

    dd_count="" dd_mb="" cached="" malloc_mb=""
    if (( n % heap_every == 0 )); then
        h="$(heap -s "$pid" 2>/dev/null)"
        dd_count="$(awk '$4 == "dispatch_data_t" {print $1; exit}' <<<"$h")"
        dd_mb="$(awk '$4 == "dispatch_data_t" {printf "%.1f", $2 / 1048576; exit}' <<<"$h")"
        cached="$(awk '$4 == "__CFCachedURLResponse" {print $1; exit}' <<<"$h")"
        malloc_mb="$(awk '/^All zones: .* nodes \(/ {
            gsub(/[()]/, "", $5); printf "%.1f", $5 / 1048576; exit }' <<<"$h")"
    fi

    echo "$(date '+%Y-%m-%dT%H:%M:%S'),$etime,$(to_mb "$fp"),$(to_mb "$peak"),$(awk -v k="$rss_kb" 'BEGIN{printf "%.1f", k/1024}'),$(cpu_seconds),$threads,$fds,$dd_count,$dd_mb,$cached,$malloc_mb"

    n=$((n + 1))
    (( $(date +%s) - start + interval > duration )) && break
    sleep "$interval"
done
