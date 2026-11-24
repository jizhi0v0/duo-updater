#!/usr/bin/env python3
"""Keep one SwiftPM scratch directory per Core job on the dedicated runner."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from ci_build_cache import MANIFEST, restore, stamp

READY = "duo-cache-ready"
MAX_CACHE_KIB = 3 * 1024**2
MIN_FREE_BYTES = 10 * 1024**3
PACKAGES = {
    "swift": ("DuoUpdaterCore", "CLI", "application-test"),
    "release": ("DuoUpdaterCore",),
}


def command(*args):
    return subprocess.check_output(args).strip()


def cache_key(job):
    inputs = [
        b"duo-swiftpm-v1",
        os.fsencode(Path.cwd()),
        command("xcodebuild", "-version"),
        command("xcrun", "--find", "swift"),
        command("swift", "--version"),
        command("xcrun", "--sdk", "macosx", "--show-sdk-build-version"),
        command("sw_vers", "-buildVersion"),
    ]
    for package in PACKAGES[job]:
        for name in ("Package.swift", "Package.resolved"):
            inputs.append(hashlib.sha256(Path(package, name).read_bytes()).digest())
    return hashlib.sha256(b"\0".join(inputs)).hexdigest()


def scratch_path(workspace, job):
    if job not in PACKAGES:
        raise ValueError(f"Unexpected Core cache job: {job}")
    # actions/checkout cleans GITHUB_WORKSPACE, and the runner empties RUNNER_TEMP.
    # Keep the cache next to the checkout, inside this runner's own _work tree.
    cache = workspace.resolve().parent / ".duo-core-cache"
    build = cache / job
    if cache.is_symlink() or build.is_symlink():
        raise ValueError(f"Unexpected symlink in Core cache path: {build}")
    return build


def prepare(build, key):
    ready = build / READY
    previous_key = ready.read_bytes() if ready.is_file() else None
    # A cancelled/failed job leaves no ready marker. Only a later successful
    # job can mark those build products safe to use.
    ready.unlink(missing_ok=True)
    if previous_key == key.encode() and (build / MANIFEST).is_file():
        try:
            restored = restore(build, refresh_changed=True)
        except (OSError, ValueError, TypeError, AttributeError, LookupError, OverflowError) as error:
            print(f"::warning::Discarding unreadable SwiftPM cache: {error}")
        else:
            print(f"SwiftPM cache warm: {restored}")
            return

    if build.exists():
        shutil.rmtree(build)
    build.mkdir(parents=True)
    print("SwiftPM cache cold")


def save(build, key):
    size_kib = int(command("du", "-sk", str(build)).split()[0])
    if size_kib > MAX_CACHE_KIB or shutil.disk_usage(build).free < MIN_FREE_BYTES:
        print(f"Discarding SwiftPM cache to limit disk use ({size_kib} KiB)")
        shutil.rmtree(build)
        return
    stamped = stamp(build)
    (build / READY).write_text(key)
    print(f"SwiftPM cache saved ({size_kib} KiB): {stamped}")


def prepare_job(workspace, job):
    build = scratch_path(workspace, job)
    low_disk = shutil.disk_usage(workspace).free < MIN_FREE_BYTES
    # Both slots belong to this single-job runner, so an unfinished sibling
    # slot is abandoned. Reclaim it before the next build can add to disk use.
    for profile in PACKAGES:
        slot = scratch_path(workspace, profile)
        abandoned = profile != job and not (slot / READY).is_file()
        if slot.is_dir() and (low_disk or abandoned):
            shutil.rmtree(slot)
    if low_disk:
        raise OSError("Evicted SwiftPM caches because disk space is low")
    key = cache_key(job)
    prepare(build, key)
    return build, key


def main(action):
    job = os.environ["GITHUB_JOB"]
    workspace = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    if workspace != Path.cwd():
        raise ValueError(f"Expected to run from the CI checkout: {workspace}")
    if action == "prepare":
        try:
            build, key = prepare_job(workspace, job)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"::warning::Using temporary SwiftPM scratch: {error}")
            build = Path(tempfile.mkdtemp(prefix="duo-core-ci.", dir=os.environ["RUNNER_TEMP"]))
            key = ""
        with open(os.environ["GITHUB_ENV"], "a") as env:
            print(f"SWIFTPM_TEST_SCRATCH={build}", file=env)
            print(f"DUO_MINI_CORE_CACHE_KEY={key}", file=env)
    elif key := os.environ["DUO_MINI_CORE_CACHE_KEY"]:
        try:
            save(scratch_path(workspace, job), key)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"::warning::Could not save the SwiftPM cache: {error}")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("prepare", "save"):
        sys.exit("usage: ci_mini_core_cache.py {prepare|save}")
    main(sys.argv[1])
