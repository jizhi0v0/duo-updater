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
import shutil
import subprocess
import sys
import tempfile

import ci_mini_core_cache as mini


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
    "scripts/ci_mini_core_cache.py",
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


def mini_slot(workspace):
    slot = workspace.parent / ".duo-app-cache"
    if slot.is_symlink():
        raise ValueError(f"Unexpected symlink in App cache path: {slot}")
    return slot


def prepare_mini(workspace, platform):
    try:
        slot = mini_slot(workspace)
        if shutil.disk_usage(workspace).free < mini.MIN_FREE_BYTES:
            if slot.is_dir():
                shutil.rmtree(slot)
            raise OSError("insufficient disk space for a persistent App cache")
        key = cache_key(workspace, platform)
        mini.prepare(slot, key, "Xcode")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::warning::Using temporary Xcode build directories: {error}")
        slot = Path(tempfile.mkdtemp(prefix="duo-app-ci.", dir=os.environ["RUNNER_TEMP"]))
        key = ""
    with open(os.environ["GITHUB_ENV"], "a") as env:
        print(f"MINI_APP_SCRATCH={slot}", file=env)
        print(f"MINI_APP_CACHE_KEY={key}", file=env)


def save_mini(workspace, key):
    if not key:
        return
    try:
        slot = mini_slot(workspace)
        # CI's failure upload uses globs, so old test reports must not survive.
        # Keep Xcode's build state together, including the SDK stat cache.
        for name in ("build", "localizable"):
            directory = slot / name
            if directory.is_symlink():
                raise ValueError(f"Unexpected DerivedData symlink: {directory}")
            for pattern in ("Logs", "Index.noindex", "ci-xcresult", "app-tests-*.log", "app-tests-*.xcresult"):
                for entry in directory.glob(pattern):
                    if entry.is_symlink() or not entry.is_dir():
                        entry.unlink()
                    else:
                        shutil.rmtree(entry)
        mini.save(slot, key, "Xcode", max_kib=8 * 1024**2)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::warning::Could not save the Xcode cache: {error}")


def main():
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    if len(sys.argv) > 1:
        if root.resolve() != Path(os.environ["GITHUB_WORKSPACE"]).resolve() or os.environ["GITHUB_JOB"] != "app":
            sys.exit("Expected the App runner checkout")
        if sys.argv[1:] == ["prepare-mini"]:
            prepare_mini(root.resolve(), os.environ["MINI_PLATFORM"])
        elif sys.argv[1:] == ["save-mini"]:
            save_mini(root.resolve(), os.environ["MINI_APP_CACHE_KEY"])
        else:
            sys.exit("usage: ci_xcode_cache.py [prepare-mini|save-mini]")
        return
    commands = (["xcodebuild", "-version"], ["swift", "--version"],
                ["xcrun", "--sdk", "macosx", "--show-sdk-version"],
                ["sw_vers", "-buildVersion"], ["uname", "-m"])
    toolchain = [subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT).strip()
                 for cmd in commands]
    toolchain.append(os.environ.get("ImageVersion", ""))
    print("key=" + cache_key(root, toolchain))


if __name__ == "__main__":
    main()
