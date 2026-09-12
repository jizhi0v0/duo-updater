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

Two consequences of that limit, both real and both already paid for here:

  * `BoundedBlockingWork.run` is a synchronous function, so `.run(key:` is
    reported where it is WRITTEN (inside sync readers, i.e. never) and not where
    it is reached from. `TestFlightInventory()` is an initializer whose body is
    that call; a `Task.detached { TestFlightInventory() }` is a five-second park
    on the cooperative pool and this gate cannot see it. Eleven of those were
    found by reading, not by running this.
  * The same goes for any wrapper: a blocking call one function call away from
    an `async` body is invisible here. Adding the token spellings is cheap;
    adding a call graph is not, and a gate that claims to have one when it does
    not is worse than this one.

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
#
# `.run(key:` is `BoundedBlockingWork.run`, which is the one entry here that does
# not block forever — it gives up after its timeout. It is still a
# `DispatchSemaphore.wait` on the calling thread for up to five seconds, and five
# seconds of a pool as wide as the core count is the thing this file is about.
BLOCKING = [
    "waitUntilExit()",
    "readDataToEndOfFile()",
    "SecStaticCodeCheckValidity",
    ".wait()",
    ".wait(timeout:",
    ".run(key:",
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
# An `async` computed accessor: `var x: T { get async { … } }`. Without this the
# accessor body reads as an ordinary brace and inherits from the enclosing type,
# i.e. from nothing.
GET_ASYNC = re.compile(r"\bget\s+async\b")
# Closures that do NOT run on the cooperative pool, so blocking inside them is
# the fix rather than the bug: a GCD queue's `async`/`asyncAfter`, a
# `DispatchWorkItem`, a `Thread`. Written against `.async`/`.asyncAfter` on any
# receiver because the queue is as often a stored property (`errQueue.async {`)
# as it is `DispatchQueue.global()`.
#
# ⚠️ `.sync { }` is deliberately NOT here. It runs the block on the CALLING
# thread, so blocking inside it parks exactly the thread this check is protecting
# — treating it as a hop would hide the violation rather than find it.
GCD = re.compile(
    r"\.(?:async|asyncAfter)\s*(?:\([^{]*\))?\s*\{"
    r"|\bDispatchWorkItem\s*\{"
    r"|\bThread\s*(?:\{|\(\s*block:)")
# An `await` in front of the call means it is an async wait, not a parked thread
# (`AsyncSemaphore.wait()`, and every other `await x.wait()` shape). This is the
# one place a blocking token is dismissed on the line's own evidence.
AWAIT = re.compile(r"\bawait\b")

EXTENDED_STRING_OPEN = re.compile(r'(#+)"')


def strip_noise(line, in_block=False, in_multiline=False):
    """(code on this line, still in a block comment, still in a `\"\"\"` literal).

    Brace counting is the only thing downstream cares about, and a `}` inside a
    log message, a regex, or a comment is not a scope. Walked character by
    character rather than run through a pile of regexes in some order, because
    every order is wrong for something: this repo has `/*` inside a `//` comment
    (`AppRuntime.swift:252`), `#\"…\"#` regexes full of quotes, and multi-line SQL.
    """
    if in_multiline:
        return "", in_block, ('"""' not in line)
    out, index, length = [], 0, len(line)
    while index < length:
        if in_block:
            if line.startswith("*/", index):
                in_block = False
                index += 2
            else:
                index += 1
            continue
        if line.startswith('"""', index):
            return "".join(out), in_block, True
        if line.startswith("//", index):
            break
        if line.startswith("/*", index):
            in_block = True
            index += 2
            continue
        extended = EXTENDED_STRING_OPEN.match(line, index)
        if extended:
            closing = '"' + extended.group(1)
            end = line.find(closing, extended.end())
            out.append('""')
            index = length if end < 0 else end + len(closing)
            continue
        if line[index] == '"':
            index += 1
            while index < length and line[index] != '"':
                index += 2 if line[index] == "\\" else 1
            out.append('""')
            index += 1
            continue
        out.append(line[index])
        index += 1
    return "".join(out), in_block, False


def frame_kind(text, parent):
    """What an opening brace on this line makes the scope inside it."""
    if OFFPOOL_CALL.search(text):
        return OFFPOOL
    if GCD.search(text):
        return SYNC
    if ASYNC_FUNC.search(text) or ASYNC_CLOSURE.search(text) or GET_ASYNC.search(text):
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
    pending = []          # (line number, text) of comments since the last statement
    # A signature wrapped across lines, kept so the `{` that opens the body is
    # still judged against the whole declaration. Without it every `async`
    # function whose parameters do not fit on one line reads as synchronous —
    # which is most of the interesting ones. `VendorProbeSource`'s
    # `zipEntryPlistValue` is the case that caught it.
    declaration = ""
    in_block = in_multiline = False
    out = []
    for number, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        stripped = raw.strip()
        was_in_block, was_in_multiline = in_block, in_multiline
        text, in_block, in_multiline = strip_noise(raw, in_block, in_multiline)
        if (was_in_block or was_in_multiline) and not text.strip():
            continue
        if stripped.startswith("//") and not was_in_block:
            pending.append((number, re.sub(r"^/{2,3}\s?", "", stripped)))
            continue
        braces = "{" in text or "}" in text
        judged = (declaration + " " + text).strip() if declaration else text
        if not braces and declaration:
            declaration = judged
        elif not braces and FUNC.search(text):
            declaration = text
        elif braces and declaration and text.count("{") == text.count("}") \
                and not text.rstrip().endswith("{"):
            # The signature is still open: this line's braces balance and none of
            # them opened a body, so they belong to a default argument
            # (`onDone: () -> Void = { }`) or a literal inside the parameter list.
            # Resetting here loses the `async` that is still three lines up.
            declaration = judged
        else:
            declaration = ""
        hits = sorted(
            (text.index(call), call) for call in BLOCKING if call in text)
        # `await x.wait()` is an async wait, not a parked thread. Dismissed on the
        # line's own evidence because the alternative — leaving `.wait()` out of
        # BLOCKING — loses the semaphore and group waits CLAUDE.md names.
        if AWAIT.search(text):
            hits = [hit for hit in hits if not hit[1].startswith(".wait")]
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
            # Which marker LINES did work, identified by line number. Comparing
            # marker text by containment let a live `…allow — network retry
            # budget` cover a stale `…allow — network` elsewhere in the file:
            # the stale one then never came up for review again, which is the
            # single thing this half exists to prevent.
            used = set()
            for number, call, verdict, comments in scan(path):
                calls += 1
                marker = next(((n, c) for n, c in comments if MARKER in c), None)
                if verdict != ASYNC:
                    continue
                if marker is None:
                    offences.append((rel, number, "blocking", call))
                elif not REASON.search(marker[1]):
                    offences.append((rel, number, "no-reason", call))
                else:
                    used.add(marker[0])
            for line_number, _ in markers:
                if line_number not in used:
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
