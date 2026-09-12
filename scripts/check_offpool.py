#!/usr/bin/env python3
"""Refuse a thread-parking call that runs on Swift concurrency's cooperative pool.

Run by `make test`.

    python3 scripts/check_offpool.py

## What this is for

The cooperative pool is width-capped near the core count and does not overcommit
when one of its threads blocks, so a handful of blocking calls on it stops the
runtime scheduling anything at all. `Support/OffPool.swift` carries the
measurement (#351: three concurrent `SecStaticCodeCheckValidity` calls, all three
cooperative threads parked, 0.00s and 0.01s of CPU burned across sixty seconds,
the process silent for the rest of the job). `offCooperativePool` is the fix, and
`Task.detached` is NOT one — a detached task still runs on that same pool.

Before this check there was no gate at all: `grep offCooperativePool App/Sources
CLI/Sources` answered zero while eleven call paths were blocking on the pool.

## What it checks, and what it cannot

For each blocking call it finds, it walks out through the enclosing braces to the
first scope that decides who the caller's thread belongs to:

  * an `offCooperativePool { … }` closure — fine, that is the hop;
  * an `async func`, a `Task { }` or a `Task.detached { }` — a violation;
  * a plain synchronous `func` — NOT reported.

That last one is the honest limit: `InPlaceSwap.replace` is synchronous and was
reached from two `async` callers for months, which no amount of looking at its
own body can reveal. Answering it needs a call graph. So this gate catches the
shape at the point where it is visible — the blocking call written directly in
async-reachable code — and the rule for everything else stays a rule.

`offpool-lint:allow — <reason>` on a comment line inside the enclosing function
exempts that function's calls. The reason is mandatory, and an exemption that no
longer matches anything fails the build: a dead exemption is a standing pass for
whatever is written there next (`make gallery`'s `mayLookAlike` does the same,
and CLAUDE.md records under #271 what happened to the one gate that skipped it).
"""

import pathlib
import re
import sys

ROOTS = ["DuoUpdaterCore/Sources", "App/Sources", "CLI/Sources"]

# Calls that park the calling thread until something outside this process moves.
# Deliberately a short list of exact spellings rather than a guess at intent:
# every one of them is a documented member of the family in `OffPool.swift`.
BLOCKING = [
    "waitUntilExit()",
    "readDataToEndOfFile()",
    "SecStaticCodeCheckValidity",
]

MARKER = "offpool-lint:allow"
REASON = re.compile(re.escape(MARKER) + r"\s*[—-]\s*(\S.*)")

# The scope kinds a frame can have. `SYNC` is "a synchronous function body",
# which this check deliberately says nothing about.
OFFPOOL, ASYNC, SYNC, PLAIN = "offpool", "async", "sync", "plain"

FUNC = re.compile(r"\bfunc\s+[A-Za-z_<]")
ASYNC_FUNC = re.compile(r"\bfunc\b.*\basync\b")
# `Task {`, `Task.detached {`, `Task(priority:) {` — all of them run on the
# cooperative pool, which is the whole point of naming them here.
TASK = re.compile(r"\bTask\b(?:\.detached)?\s*(?:\([^)]*\))?\s*\{")
OFFPOOL_CALL = re.compile(r"\boffCooperativePool\b")
# A closure that names its own signature, e.g. `{ () -> Info? in` or
# `{ [self] () async -> Int32 in` — the `async` there belongs to the closure.
ASYNC_CLOSURE = re.compile(r"\{[^}]*\basync\b[^}]*\bin\b")

STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def strip_noise(line):
    """Line with string literals and trailing comments blanked out.

    Brace counting is the only thing downstream cares about, and a `}` inside a
    log message or a `//` aside is not a scope. String interpolation braces are
    balanced, so blanking the whole literal keeps the count right.
    """
    line = STRING.sub('""', line)
    cut = line.find("//")
    if cut >= 0:
        line = line[:cut]
    return line


def frame_kind(text, parent):
    """What an opening brace on this line makes the scope inside it."""
    if OFFPOOL_CALL.search(text):
        return OFFPOOL
    if ASYNC_FUNC.search(text) or ASYNC_CLOSURE.search(text):
        return ASYNC
    if FUNC.search(text):
        return SYNC
    if TASK.search(text):
        return ASYNC
    # Any other brace — an `if`, a `for`, a plain closure — does not decide
    # anything, so it inherits and the walk keeps going outward.
    return PLAIN


def deciding_frame(stack):
    for kind, _ in reversed(stack):
        if kind != PLAIN:
            return kind
    return SYNC


def scan(path):
    """(line number, call, verdict, comments in scope) per blocking call.

    Braces are walked in the order they appear ON the line, not counted: a line
    can both open and close a scope (`} else {`, `func f() { 5 }`), and counting
    gets the nesting wrong in opposite directions for those two.
    """
    stack = []            # [(kind, comments attached to that scope)]
    pending = []          # comment lines since the last statement
    # A signature wrapped across lines, kept so the `{` that opens the body is
    # still judged against the whole declaration. Without it every `async`
    # function whose parameters do not fit on one line reads as synchronous —
    # which is most of the interesting ones. `VendorProbeSource`'s
    # `zipEntryPlistValue` is the case that caught it.
    declaration = ""
    out = []
    for number, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        stripped = raw.strip()
        if stripped.startswith("//"):
            pending.append(re.sub(r"^/{2,3}\s?", "", stripped))
            continue
        text = strip_noise(raw)
        braces = "{" in text or "}" in text
        judged = (declaration + " " + text).strip() if declaration else text
        if braces:
            declaration = ""
        elif declaration:
            declaration += " " + text
        elif FUNC.search(text):
            declaration = text
        hits = sorted(
            (text.index(call), call) for call in BLOCKING if call in text)
        if not braces:
            for _, call in hits:
                comments = [c for _, scope in stack for c in scope] + pending
                out.append((number, call, deciding_frame(stack), comments))
            pending = []
            continue
        opened_on_line = False
        for column, character in enumerate(text):
            while hits and hits[0][0] <= column:
                _, call = hits.pop(0)
                comments = [c for _, scope in stack for c in scope] + pending
                out.append((number, call, deciding_frame(stack), comments))
            if character == "{":
                kind = PLAIN if opened_on_line else frame_kind(judged, stack)
                opened_on_line = True
                stack.append((kind, list(pending)))
            elif character == "}" and stack:
                stack.pop()
        for _, call in hits:
            comments = [c for _, scope in stack for c in scope] + pending
            out.append((number, call, deciding_frame(stack), comments))
        pending = []
    return out


def review(root, roots=ROOTS):
    missing = [r for r in roots if not (root / r).is_dir()]
    scanned, calls, offences, dead = 0, 0, [], []
    for r in roots:
        base = root / r
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            if ".build" in path.parts:
                continue
            rel = path.relative_to(root)
            scanned += 1
            text = path.read_text(errors="replace")
            markers = [
                (i + 1, line.strip())
                for i, line in enumerate(text.splitlines())
                if MARKER in line
            ]
            used = set()
            for number, call, verdict, comments in scan(path):
                calls += 1
                marker = next((c for c in comments if MARKER in c), None)
                if verdict != ASYNC:
                    continue
                if marker is None:
                    offences.append((rel, number, "blocking", call))
                elif not REASON.search(marker):
                    offences.append((rel, number, "no-reason", call))
                else:
                    used.add(marker.strip())
            for line_number, line in markers:
                if not any(u in line or line.endswith(u) for u in used):
                    dead.append((rel, line_number))
    return {"missing": missing, "scanned": scanned, "calls": calls,
            "offences": offences, "dead": dead}


def main(root=None, roots=ROOTS, minimum=200, minimum_calls=20):
    root = root or pathlib.Path(__file__).resolve().parent.parent
    found = review(root, roots=roots)

    if found["missing"]:
        print(f"✗ these source roots are not under {root}: "
              f"{', '.join(found['missing'])}\n"
              "  Fix the paths rather than dropping them.", file=sys.stderr)
        return 1
    # Two floors, for the two ways this becomes a check that inspects nothing:
    # the roots moving, and the call spellings going out of date (a rename of
    # `waitUntilExit` would leave every root in place and every file scanned).
    if found["scanned"] < minimum:
        print(f"✗ only {found['scanned']} Swift files scanned across "
              f"{len(roots)} roots — too few to be a real run.", file=sys.stderr)
        return 1
    if found["calls"] < minimum_calls:
        print(f"✗ only {found['calls']} blocking calls found; this repository "
              f"has far more.\n  Check the spellings in BLOCKING before "
              f"believing a green run.", file=sys.stderr)
        return 1

    offences, dead = found["offences"], found["dead"]
    if not offences and not dead:
        print(f"✓ no blocking calls left on the cooperative pool — "
              f"{found['calls']} call(s) in {found['scanned']} files")
        return 0

    for rel, line, kind, call in offences:
        if kind == "no-reason":
            print(f"✗ {rel}:{line}: `{call}` is exempted by a bare `{MARKER}` "
                  f"— the reason is not optional, write `{MARKER} — <why>`",
                  file=sys.stderr)
        else:
            print(f"✗ {rel}:{line}: `{call}` parks a cooperative thread — it is "
                  f"inside an async function or a Task, not inside an "
                  f"`offCooperativePool` hop", file=sys.stderr)
    for rel, line in dead:
        print(f"✗ {rel}:{line}: `{MARKER}` here no longer exempts anything — "
              "delete it, or it silently exempts whatever is written next",
              file=sys.stderr)
    print(f"\n{len(offences)} blocking call(s), {len(dead)} stale "
          "exemption(s).\nWrap the whole contiguous blocking sequence in one\n"
          "    try await offCooperativePool { … }\n"
          f"or, if it genuinely cannot block, add `{MARKER} — <why>` to the "
          "enclosing function's comment.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
