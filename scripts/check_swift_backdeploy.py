#!/usr/bin/env python3
"""Refuse to ship a Mach-O that needs a Swift runtime library macOS 14 lacks.

    scripts/check_swift_backdeploy.py <app-bundle-or-binary> ...

The deployment target is macOS 14. A Swift 6.2+ toolchain back-deploys `Span`
(which swift-subprocess uses) by linking `@rpath/libswiftCompatibilitySpan.dylib`.
The OS carries that library in `/usr/lib/swift` from macOS 26 on (this machine,
macOS 27, loads it from there); an older OS does not, so a binary that links it
launches only if the library is embedded beside it. The Debug `duo` that
`swift build` makes from this branch links it, and on the build machine it runs
fine — every test here runs on the machine that built it, so nothing else would
notice. Reported in the wild for exactly this shape: a helper tool using
Subprocess, built with Xcode 26.3, that failed to load the library on older
macOS (developer.apple.com/forums/thread/817488). Not reproduced here: there is
no macOS 14 machine to launch on.

A load command fails the check when it names

  * a `libswiftCompatibility*` shim that no `@loader_path`/`@executable_path` run
    path resolves to a file inside the thing being shipped — `/usr/lib/swift`
    does not count for these, since the oldest OS this ships to lacks them; or
  * any other `@rpath/libswift*` library that neither such a run path nor a
    `/usr/lib/swift` one (the OS's runtime, how pre-5.1 toolchains linked —
    Sparkle's `BinaryDelta` still does) resolves.

Any other absolute run path does not count: a toolchain directory on the build
machine is not on the user's.

Only dependencies are judged — `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`,
`LC_REEXPORT_DYLIB`, `LC_LAZY_LOAD_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, read from
`otool -l`. Not `otool -L`: for a dylib its first line is the library's OWN
install name (`LC_ID_DYLIB`), and the toolchain's Span shim names itself
`/usr/lib/swift/libswiftCompatibilitySpan.dylib`, so a correctly embedded copy
used to fail the check as "a shim at a fixed path".

`@executable_path` is the directory of the Mach-O itself when it is an
executable (a nested helper, `Updater.app`, an XPC service), and the bundle's
`Contents/MacOS` for a library. Not modelled: a library loaded by a nested
executable rather than the main one, whose `@executable_path` is that
executable's. Nothing shipped here resolves a Swift library that way today.

Not covered, said so rather than implied: a `/usr/lib/swift/` library that
exists on the build machine's OS but not on macOS 14 (dyld would fail the same
way). Nothing produces one today; a table of what each OS ships is the fix if
something does.
"""

import os
import pathlib
import re
import subprocess
import sys

MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",  # thin, little-endian 64/32
    b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",  # fat, fat64
}
OS_RUNTIME = "/usr/lib/swift"
DEPENDENCY_COMMANDS = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
                       "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB"}
COMMAND = re.compile(r"^\s*cmd (LC_\w+)$")
NAME = re.compile(r"^\s+name (.+?) \(offset \d+\)$")
RPATH = re.compile(r"^\s+path (.+?) \(offset \d+\)$")


def is_macho(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(4) in MACHO_MAGICS
    except OSError:
        return False


def binaries(target):
    """Every Mach-O file at or under `target`, symlinks not followed."""
    target = pathlib.Path(target)
    if target.is_file():
        return [target] if is_macho(target) else []
    found = []
    for directory, _, names in os.walk(target):
        for name in names:
            path = pathlib.Path(directory, name)
            if not path.is_symlink() and is_macho(path):
                found.append(path)
    return sorted(found)


def otool(flag, binary):
    return subprocess.run(["otool", flag, str(binary)], capture_output=True,
                          text=True, check=True).stdout


def load_paths(listing):
    """Dependencies from `otool -l` output: the dylib load commands' names, never
    `LC_ID_DYLIB` (the library's own name)."""
    found, command = set(), None
    for line in listing.splitlines():
        if (m := COMMAND.match(line)):
            command = m.group(1)
        elif command in DEPENDENCY_COMMANDS and (m := NAME.match(line)):
            found.add(m.group(1))
    return sorted(found)


def run_paths(listing):
    """LC_RPATH entries from `otool -l` output."""
    found, command = [], None
    for line in listing.splitlines():
        if (m := COMMAND.match(line)):
            command = m.group(1)
        elif command == "LC_RPATH" and (m := RPATH.match(line)):
            found.append(m.group(1))
    return found


def is_executable(header):
    """Whether `otool -hv` output describes an MH_EXECUTE file."""
    return any(" EXECUTE " in f" {line} " for line in header.splitlines()[2:])


def offences(binary, root, loads, rpaths, executable_dir):
    """(dependency, why) for each load command this binary cannot ship with."""
    root = os.path.realpath(root)
    out = []
    for dep in loads:
        name = dep.rsplit("/", 1)[-1]
        shim = name.startswith("libswiftCompatibility")
        if not shim and not (dep.startswith("@rpath/") and name.startswith("libswift")):
            continue
        if not dep.startswith("@rpath/"):
            out.append((dep, "a Swift back-deployment shim at a fixed path, "
                             "absent from macOS before 26"))
            continue
        rest = dep[len("@rpath/"):]
        if not any(embedded(rpath, rest, binary, executable_dir, root) for rpath in rpaths) \
                and (shim or OS_RUNTIME not in (r.rstrip("/") for r in rpaths)):
            out.append((dep, "a Swift back-deployment shim, absent from macOS before 26, "
                             "and not embedded in what ships" if shim
                        else "not embedded in what ships, and no /usr/lib/swift run path"))
    return out


def embedded(rpath, rest, binary, executable_dir, root):
    """Whether `rpath` + `rest` is a file inside `root`."""
    if rpath.startswith("@loader_path"):
        base = str(binary.parent) + rpath[len("@loader_path"):]
    elif rpath.startswith("@executable_path"):
        base = str(executable_dir) + rpath[len("@executable_path"):]
    else:
        return False
    candidate = os.path.realpath(os.path.join(base, rest))
    return os.path.isfile(candidate) and (candidate + os.sep).startswith(root + os.sep)


def check(target):
    target = pathlib.Path(target)
    # A bundle ships with everything inside it; a lone binary ships alone
    # (`build-cli.sh` copies just the file), so nothing beside it is embedded.
    root = target
    main_dir = target / "Contents" / "MacOS" if target.is_dir() else target.parent
    found, checked = [], 0
    for binary in binaries(target):
        checked += 1
        listing = otool("-l", binary)
        executable_dir = binary.parent if is_executable(otool("-hv", binary)) else main_dir
        for dep, why in offences(binary, root, load_paths(listing),
                                 run_paths(listing), executable_dir):
            found.append((binary, dep, why))
    return checked, found


def main(argv):
    if not argv:
        print("usage: check_swift_backdeploy.py <app-bundle-or-binary> ...", file=sys.stderr)
        return 2
    failed = False
    for target in argv:
        if not os.path.exists(target):
            print(f"✗ {target} does not exist", file=sys.stderr)
            return 1
        checked, found = check(target)
        if checked == 0:
            # A path that holds no Mach-O is a wrong path, and a pass for it would
            # be a check that inspected nothing.
            print(f"✗ no Mach-O files under {target}", file=sys.stderr)
            return 1
        for binary, dep, why in found:
            print(f"✗ {binary} links {dep} — {why}.\n"
                  f"  It would fail to launch on macOS 14.", file=sys.stderr)
            failed = True
        if not found:
            print(f"   {checked} Mach-O file(s) under {target}: no Swift runtime "
                  f"library missing from macOS 14")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
