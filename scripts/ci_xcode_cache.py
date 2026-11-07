#!/usr/bin/env python3
"""Name a compatible Xcode cache; source edits remain incremental build inputs.

The cached build embeds absolute paths, so the checkout path and hosted image
are part of its identity. Changes to project settings, dependency pins, build
scripts or the set of input paths start cold. The last rule also prevents old
.stringsdata for a removed source from surviving a localization check.

File CONTENT changes are deliberately left to Xcode, after ci_build_cache.py
restores mtimes only for unchanged tracked files. No test or build is skipped.
"""

import hashlib
import json
import os
from pathlib import Path
import subprocess


CONFIG = (
    ".github/workflows/ci.yml",
    "Makefile",
    "App/project.yml",
    "App/Package.resolved",
    "DuoUpdaterCore/Package.swift",
    "DuoUpdaterCore/Package.resolved",
    "CLI/Package.swift",
    "scripts/app-tests.sh",
    "scripts/unsigned-release-build.sh",
    "scripts/check_localizable_keys.py",
    "scripts/ci_build_cache.py",
    "scripts/ci_xcode_cache.py",
    "scripts/pinned-xcodegen.sh",
)


def cache_key(root, toolchain):
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--", "App", "CLI", "DuoUpdaterCore"]
    ).split(b"\0")
    digest = hashlib.sha256()
    digest.update(json.dumps([str(root.resolve()), toolchain], sort_keys=True).encode())
    for path in sorted(filter(None, paths)):
        digest.update(b"\0path\0" + path)
    for name in CONFIG:
        path = root / name
        digest.update(b"\0config\0" + name.encode() + b"\0")
        digest.update(path.read_bytes() if path.is_file() else b"<absent>")
    return "xcode-v1-" + digest.hexdigest()[:24]


def main():
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    commands = (["xcodebuild", "-version"], ["swift", "--version"],
                ["xcrun", "--sdk", "macosx", "--show-sdk-version"],
                ["sw_vers", "-buildVersion"], ["uname", "-m"])
    toolchain = [subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT).strip()
                 for cmd in commands]
    toolchain.append(os.environ.get("ImageVersion", ""))
    print("key=" + cache_key(root, toolchain))


if __name__ == "__main__":
    main()
