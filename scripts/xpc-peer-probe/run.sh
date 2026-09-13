#!/bin/bash
# Two-process experiment behind the helper's XPC peer check (App/Helper/HelperPeerGate.swift).
#
# Answers, on the machine it runs on, the questions a public-API peer check has to
# answer before it may replace the audit-token check in a ROOT daemon:
#   Q1  With NSXPCListener.setConnectionCodeSigningRequirement, is the delegate still
#       consulted for a non-matching peer, and can ANY message from it reach the
#       exported object? (Compared against the per-connection variant.)
#   Q2  Does a rejected peer ever move an IdleExit-shaped open/close counter?
#   exec  Does a burst queued by a non-matching process that then exec()s a matching
#       binary (same PID) get through?
#
# Not part of `make test`: it bootstraps throwaway launchd USER agents
# (gui/<uid>, labels com.duoupdater.zzprobe.<pid>.*), which CI must not do and a
# unit test must not depend on. Every agent is booted out on exit; the plist lives
# in a mktemp dir, so nothing persists even if bootout were skipped. It never
# touches com.duoupdater.helper or the installed app.
#
# Usage: scripts/xpc-peer-probe/run.sh
#   PROBE_DEVID="<codesigning identity SHA-1 or name>" additionally runs the
#   production-shaped requirement (anchor apple generic + identifier + team OU)
#   against a Developer ID–signed peer and an ad-hoc peer FORGING the same
#   identifier. codesign may ask for keychain access.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)" && cd "$ROOT"

T="$(mktemp -d)"
UIDN="$(id -u)"
LABELS=()
cleanup() {
  for l in "${LABELS[@]:-}"; do
    [ -n "$l" ] && launchctl bootout "gui/$UIDN/$l" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

echo "workdir: $T"
sw_vers | tr '\n' ' '; echo
swiftc --version 2>&1 | head -1

swiftc -O -swift-version 5 -module-name ProbeListener scripts/xpc-peer-probe/Listener.swift -o "$T/listener"
swiftc -O -swift-version 5 -module-name ProbePeer scripts/xpc-peer-probe/Peer.swift -o "$T/peer"
cp "$T/peer" "$T/peer-good"
cp "$T/peer" "$T/peer-bad"
codesign -f -s - -i com.duoupdater.zzprobe.listener "$T/listener" 2>/dev/null
codesign -f -s - -i com.duoupdater.zzprobe.good "$T/peer-good" 2>/dev/null
codesign -f -s - -i com.duoupdater.zzprobe.bad "$T/peer-bad" 2>/dev/null

REQ_GOOD='identifier "com.duoupdater.zzprobe.good"'

# scenario <name> <mode> <requirement> -- <peer command...>
scenario() {
  local name="$1" mode="$2" req="$3"; shift 4
  local label="com.duoupdater.zzprobe.$$.$name"
  local log="$T/$name.listener.log" plist="$T/$name.plist"
  : > "$log"
  LABELS+=("$label")
  /usr/bin/python3 - "$plist" "$label" "$T/listener" "$log" "$mode" "$req" <<'PY'
import plistlib, sys
plist, label, exe, log, mode, req = sys.argv[1:]
plistlib.dump({
    "Label": label,
    "ProgramArguments": [exe, log, mode, req],
    "EnvironmentVariables": {"PROBE_SERVICE": label},
    "MachServices": {label: True},
}, open(plist, "wb"))
PY
  launchctl bootstrap "gui/$UIDN" "$plist"
  echo
  echo "=== $name  (listener mode=$mode, requirement=${req:-<none>})"
  "$@" "$label" 2>&1 | sed 's/^/  peer| /' || true
  sleep 1
  launchctl bootout "gui/$UIDN/$label" >/dev/null 2>&1 || true
  sed 's/^[0-9.]* /  lsnr| /' "$log"
  printf '  SUMMARY %s: delegate=%s invoked=%s opened=%s closed=%s\n' "$name" \
    "$(grep -c ' DELEGATE ' "$log" || true)" "$(grep -c ' INVOKED ' "$log" || true)" \
    "$(grep -c ' OPENED ' "$log" || true)" "$(grep -c ' CLOSED ' "$log" || true)"
}

# The peer takes the service name LAST from `scenario`, so wrap it.
peer() { local bin="$1" tag="$2" count="$3" svc="$4"; "$bin" "$svc" "$tag" "$count"; }
peer_exec() { local bad="$1" good="$2" count="$3"; local svc="$4"
  "$bad" "$svc" bad "$count" exec "$good" "$svc" good-after-exec 1; }

# The exec race with the ordering FORCED. In plain `listener-exec-race` the listener
# most likely judged the bad connection request before the exec happened, which
# proves nothing about which identity it judged. Here the listener is SIGSTOPped
# first, so the bad process's connection request and burst sit in the kernel while
# it exec()s the matching binary under the same PID; only then is the listener
# resumed. A check that looked the peer up by PID would now find matching code and
# accept the bad request (a DELEGATE line for it, and bad-* INVOKED lines). A check
# bound to the message's audit token (PID + pidversion, which exec bumps) rejects it.
peer_exec_stopped() { local bad="$1" good="$2" count="$3" log="$4"; local svc="$5"
  "$good" "$svc" warmup 1 >/dev/null   # starts the on-demand listener
  local lpid; lpid="$(sed -n 's/.* LISTENING .* pid=\([0-9]*\)$/\1/p' "$log")"
  echo "PROBE stopping listener pid=$lpid"
  kill -STOP "$lpid"
  "$bad" "$svc" bad "$count" exec "$good" "$svc" good-after-exec 1 &
  local ppid=$!
  sleep 2
  echo "PROBE resuming listener pid=$lpid"
  kill -CONT "$lpid"
  wait "$ppid" || true
}

scenario control-none        none         ""          -- peer "$T/peer-bad"  bad  3
scenario listener-good       listener-req "$REQ_GOOD" -- peer "$T/peer-good" good 3
scenario listener-bad        listener-req "$REQ_GOOD" -- peer "$T/peer-bad"  bad  3
scenario listener-bad-burst  listener-req "$REQ_GOOD" -- peer "$T/peer-bad"  bad  200
scenario listener-exec-race  listener-req "$REQ_GOOD" -- peer_exec "$T/peer-bad" "$T/peer-good" 200
scenario listener-exec-stopped listener-req "$REQ_GOOD" -- \
  peer_exec_stopped "$T/peer-bad" "$T/peer-good" 50 "$T/listener-exec-stopped.listener.log"
scenario control-exec-stopped  none         ""          -- \
  peer_exec_stopped "$T/peer-bad" "$T/peer-good" 50 "$T/control-exec-stopped.listener.log"
scenario delegate-reject     delegate-reject ""       -- peer "$T/peer-bad"  bad  3
scenario conn-good           conn-req     "$REQ_GOOD" -- peer "$T/peer-good" good 3
scenario conn-bad            conn-req     "$REQ_GOOD" -- peer "$T/peer-bad"  bad  3
scenario conn-bad-burst      conn-req     "$REQ_GOOD" -- peer "$T/peer-bad"  bad  200
scenario both-good           both-req     "$REQ_GOOD" -- peer "$T/peer-good" good 3

if [ -n "${PROBE_DEVID:-}" ]; then
  cp "$T/peer" "$T/peer-devid"
  cp "$T/peer" "$T/peer-forged"
  codesign -f -o runtime -s "$PROBE_DEVID" -i com.duoupdater.zzprobe.good "$T/peer-devid"
  codesign -f -s - -i com.duoupdater.zzprobe.good "$T/peer-forged" 2>/dev/null
  TEAM="$(codesign -dv "$T/peer-devid" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  REQ_PROD="anchor apple generic and identifier \"com.duoupdater.zzprobe.good\" and certificate leaf[subject.OU] = \"$TEAM\""
  scenario prod-devid   listener-req "$REQ_PROD" -- peer "$T/peer-devid"  devid  3
  scenario prod-forged  listener-req "$REQ_PROD" -- peer "$T/peer-forged" forged 3
fi
