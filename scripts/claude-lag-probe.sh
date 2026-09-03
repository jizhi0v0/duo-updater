#!/usr/bin/env bash
# Run once; launchd schedules this every 300 seconds.
#
# Records when Claude's GA redirect and rollout endpoint begin advertising a
# release. Keeping this independent of Duo Updater's own decision path lets the
# resulting timeline distinguish an upstream ramp from a late local observation.
#
# A proxy is required on the machine this probe was written for:
# api.anthropic.com returns a regional 403 when reached directly. launchd does
# not inherit shell environment, so the LaunchAgent supplies HTTP_PROXY and
# HTTPS_PROXY. A 403 is recorded as `blocked` and never mutates version state.
set -u

PROBE_DIR="${CLAUDE_LAG_PROBE_DIR:-$HOME/Library/Application Support/claude-lag-probe}"
OUT="$PROBE_DIR/claude-lag.jsonl"
STATE="$PROBE_DIR/.last"
BEAT="$PROBE_DIR/.lastbeat"
DIDFILE="${CLAUDE_LAG_DID_FILE:-$HOME/Library/Application Support/Claude/ant-did}"
CURL="${CLAUDE_LAG_CURL:-/usr/bin/curl}"

mkdir -p "$PROBE_DIR"
append_json() { printf '%s\n' "$1" >> "$OUT"; }

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -r "$DIDFILE" ] || {
  append_json "{\"at\":\"$now\",\"event\":\"error\",\"why\":\"ant-did unreadable\"}"
  exit 0
}
DID=$(base64 -d < "$DIDFILE" 2>/dev/null)
[ -n "$DID" ] || {
  append_json "{\"at\":\"$now\",\"event\":\"error\",\"why\":\"ant-did empty\"}"
  exit 0
}

hdr=$("$CURL" -sS --max-time 25 -o /dev/null -D - -w '\nCODE=%{http_code} IP=%{remote_ip}\n' \
      "https://api.anthropic.com/api/desktop/darwin/universal/zip/latest/redirect" 2>/dev/null)
code=$(printf '%s' "$hdr" | sed -n 's/.*CODE=\([0-9]*\).*/\1/p' | tail -1)
ip=$(printf '%s' "$hdr" | sed -n 's/.*IP=\([0-9a-f.:]*\).*/\1/p' | tail -1)
ga=$(printf '%s' "$hdr" | sed -n 's|.*/universal/\([0-9.]*\)/.*|\1|p' | head -1)

body=$("$CURL" -sS --max-time 25 \
      "https://api.anthropic.com/api/desktop/darwin/universal/squirrel/update?device_id=$DID" 2>/dev/null)
ro=$(printf '%s' "$body" | sed -n 's/.*"currentRelease":"\([^"]*\)".*/\1/p')
pd=$(printf '%s' "$body" | sed -n 's/.*"pub_date":"\([^"]*\)".*/\1/p')

# 403 means the request escaped the proxy and hit the regional block. It is
# evidence about the network path, but never evidence that a version changed.
if [ "${code:-0}" = "403" ]; then
  append_json "{\"at\":\"$now\",\"event\":\"blocked\",\"code\":\"$code\",\"ip\":\"$ip\"}"
  exit 0
fi

# Neither endpoint answered: preserve the established `unreachable` event.
if [ -z "$ga" ] && [ -z "$ro" ]; then
  append_json "{\"at\":\"$now\",\"event\":\"unreachable\",\"code\":\"${code:-?}\",\"ip\":\"${ip:-?}\"}"
  exit 0
fi

# One endpoint answered and one did not. This used to enter the state machine,
# write a half-empty value to .last, and manufacture another change when the
# failed endpoint recovered. Record the partial observation, but keep the last
# complete pair intact so a later real transition retains truthful provenance.
if [ -z "$ga" ] || [ -z "$ro" ]; then
  append_json "{\"at\":\"$now\",\"event\":\"partial\",\"ga\":\"$ga\",\"rollout\":\"$ro\",\"code\":\"${code:-?}\",\"ip\":\"${ip:-?}\"}"
  exit 0
fi

cur="$ga|$ro"
last=$(cat "$STATE" 2>/dev/null || printf '')
if [ "$cur" != "$last" ]; then
  append_json "{\"at\":\"$now\",\"event\":\"change\",\"ga\":\"$ga\",\"rollout\":\"$ro\",\"pub_date\":\"$pd\",\"prev\":\"$last\",\"ip\":\"$ip\"}"
  printf '%s' "$cur" > "$STATE"
else
  lb=$(cat "$BEAT" 2>/dev/null || printf '0')
  if [ $(( $(date +%s) - lb )) -ge 3600 ]; then
    append_json "{\"at\":\"$now\",\"event\":\"beat\",\"ga\":\"$ga\",\"rollout\":\"$ro\",\"ip\":\"$ip\"}"
    date +%s > "$BEAT"
  fi
fi
