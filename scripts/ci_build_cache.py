#!/usr/bin/env python3
"""Make a restored SwiftPM `.build` count as warm on a fresh checkout.

    python3 scripts/ci_build_cache.py stamp   DuoUpdaterCore/.build   # after building
    python3 scripts/ci_build_cache.py restore DuoUpdaterCore/.build   # after restoring it

ci.yml caches `DuoUpdaterCore/.build` on GitHub-hosted runners, which otherwise
compile everything from nothing on every run. The directory alone is not enough:
SwiftPM decides what to recompile from modification times, and a fresh checkout
gives every tracked file the time of the checkout, which is later than anything
in the cached build. Every file looks edited, and the build is as cold as before.

So `stamp` writes, next to the build products, the blob and mtime of every
tracked file as the build saw them, and `restore` puts each mtime back on the
files whose blob is still the same. A file that changed keeps its checkout time,
later than the build, and is recompiled; one that did not looks exactly as the
build left it. The comparison is by content, so it does not depend on which
commit the cache came from, nor on history (checkout's default depth is 1).

A file with uncommitted changes when `stamp` runs is left out: its blob in the
index is not what the build compiled.
"""

import json
import os
import pathlib
import subprocess
import sys

MANIFEST = "ci-mtimes.json"


def tracked():
    """{path: blob} for every tracked file whose worktree copy matches the index."""
    out = subprocess.run(["git", "ls-files", "-s", "-z"], check=True,
                         capture_output=True).stdout.decode()
    blobs = {}
    for entry in filter(None, out.split("\0")):
        meta, path = entry.split("\t", 1)
        mode, blob, _stage = meta.split()
        if mode != "160000":  # a submodule is not a file
            blobs[path] = blob
    dirty = subprocess.run(["git", "ls-files", "-m", "-z"], check=True,
                           capture_output=True).stdout.decode()
    for path in filter(None, dirty.split("\0")):
        blobs.pop(path, None)
    return blobs


def stamp(build):
    manifest = {}
    for path, blob in tracked().items():
        try:
            manifest[path] = [blob, os.lstat(path).st_mtime_ns]
        except FileNotFoundError:
            pass
    build.mkdir(parents=True, exist_ok=True)
    (build / MANIFEST).write_text(json.dumps(manifest))
    return f"stamped {len(manifest)} files"


def restore(build):
    try:
        manifest = json.loads((build / MANIFEST).read_text())
    except FileNotFoundError:
        return "no manifest: nothing restored, the build starts cold"
    same = changed = 0
    for path, blob in tracked().items():
        recorded = manifest.get(path)
        if recorded and recorded[0] == blob:
            os.utime(path, ns=(recorded[1], recorded[1]), follow_symlinks=False)
            same += 1
        else:
            changed += 1
    return f"restored {same} mtimes; {changed} files new or changed since the cache"


def main(argv):
    if len(argv) != 3 or argv[1] not in ("stamp", "restore"):
        sys.exit(__doc__.split("\n\n")[1])
    action = stamp if argv[1] == "stamp" else restore
    print(action(pathlib.Path(argv[2])))


if __name__ == "__main__":
    main(sys.argv)
