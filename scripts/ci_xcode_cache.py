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
import re
import shutil
import subprocess
import sys
import tempfile

import ci_mini_core_cache as mini


CAS_MAX_KIB = 2 * 1024**2


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


def mini_cas_slot():
    # The runner clears _temp between jobs. Keep the store next to it, so
    # changes to the checkout path and DerivedData cannot move the CAS.
    temp = Path(os.environ["RUNNER_TEMP"]).resolve()
    if temp.name != "_temp" or not temp.is_dir():
        raise ValueError(f"Unexpected App runner temporary directory: {temp}")
    slot = temp.parent / ".duo-updater-app-cas"
    if slot.is_symlink() or (slot.exists() and not slot.is_dir()):
        raise ValueError(f"Unexpected App compilation cache path: {slot}")
    return slot


def cas_key(platform):
    return f"xcode-cas-v1-{platform}".encode()


def cas_over_budget(slot):
    return int(mini.command("du", "-sk", str(slot)).split()[0]) > CAS_MAX_KIB


def supports_cas_paths(*paths):
    # Xcode can spell paths under /private/tmp and /private/var two ways.
    # Also keep xcconfig metacharacters out of the paths it reads.
    return all(
        path.parts[:3] not in (("/", "private", "tmp"), ("/", "private", "var"))
        and re.fullmatch(r"/[A-Za-z0-9_./-]+", str(path))
        for path in paths
    )


def prepare_mini_cas(workspace, platform, build_slot):
    slot = mini_cas_slot()
    if not supports_cas_paths(slot):
        return None
    ready = slot / mini.READY
    # Leave room for a full CAS before reaching the regular build-cache floor.
    minimum_free = mini.MIN_FREE_BYTES + CAS_MAX_KIB * 1024
    if slot.is_dir() and (
        shutil.disk_usage(slot.parent).free < minimum_free
        or ready.is_symlink()
        or not ready.is_file()
        or ready.read_bytes() != cas_key(platform)
        or cas_over_budget(slot)
    ):
        shutil.rmtree(slot)
    if (build_slot is None or not supports_cas_paths(workspace, build_slot)
            or shutil.disk_usage(slot.parent).free < minimum_free):
        return None

    slot.mkdir(exist_ok=True)
    ready.unlink(missing_ok=True)
    # Match XCODE_CLONED_SOURCE_PACKAGES in the App job. Swift's explicit
    # module keys otherwise embed the C shims' absolute module map paths.
    packages = build_slot / "build/SourcePackages"
    mappings = f"{workspace}=/^duo-source {packages}=/^duo-packages"
    with tempfile.NamedTemporaryFile(
        mode="w", prefix="duo-app-cas-", suffix=".xcconfig", dir=os.environ["RUNNER_TEMP"], delete=False
    ) as config:
        config.write(
            "COMPILATION_CACHE_ENABLE_CACHING = YES\n"
            f"COMPILATION_CACHE_CAS_PATH = {slot}\n"
            "COMPILATION_CACHE_LIMIT_SIZE = 2G\n"
            "SWIFT_ENABLE_PREFIX_MAPPING = YES\n"
            "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING = YES\n"
            f"SWIFT_OTHER_PREFIX_MAPPINGS = {mappings}\n"
            "CLANG_ENABLE_PREFIX_MAPPING = YES\n"
            "CLANG_ENABLE_PROJECT_PREFIX_MAPPING = YES\n"
            f"CLANG_OTHER_PREFIX_MAPPINGS = {mappings}\n"
        )
        return config.name


def save_mini_cas(platform):
    slot = mini_cas_slot()
    if shutil.disk_usage(slot.parent).free < mini.MIN_FREE_BYTES or cas_over_budget(slot):
        shutil.rmtree(slot)
        print("Discarding App compilation cache to limit disk use")
    else:
        with (slot / mini.READY).open("xb") as ready:
            ready.write(cas_key(platform))
        print("Kept App compilation cache on the mini")


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
    config = None
    try:
        config = prepare_mini_cas(workspace, platform, build_slot=slot if key else None)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::warning::Building without an App compilation cache: {error}")
    with open(os.environ["GITHUB_ENV"], "a") as env:
        print(f"MINI_APP_SCRATCH={slot}", file=env)
        print(f"MINI_APP_CACHE_KEY={key}", file=env)
        if config:
            print(f"DUO_CI_XCODE_CAS_CONFIG={config}", file=env)
            print("App compilation cache enabled on the mini")


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
            if os.environ.get("DUO_CI_XCODE_CAS_CONFIG"):
                try:
                    save_mini_cas(os.environ["MINI_PLATFORM"])
                except (OSError, ValueError, subprocess.CalledProcessError) as error:
                    print(f"::warning::Could not save the App compilation cache: {error}")
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
