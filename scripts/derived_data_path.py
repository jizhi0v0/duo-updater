#!/usr/bin/env python3
"""Print a per-checkout derived-data path, and prune the ones left by checkouts
that are gone.

Why per checkout: a fixed path is shared by every worktree open at once, and
this repo routinely has a couple of dozen. Two concurrent xcodebuilds on one
derived-data path collide on its SQLite lock, and the symptom — `database is
locked`, or a build that simply stalls — reads as a real failure. CLAUDE.md
records that trap for `/tmp/duo-loc-check`; this removes it instead of asking
the next person to recognise it.

Why prune: measured 2026-09-04, `/tmp` held 19 GB of these caches at ~450 MB
each, on a volume with 38 GiB free. Handing every checkout its own path without
reclaiming the dead ones trades a confusing failure for a full disk. Each
directory carries an `origin` marker naming the checkout it belongs to; a
directory whose checkout no longer exists is deleted.

Pruning is deliberately fail-closed: it only ever removes a directory that
matches `duo-<name>-<8 hex>` AND carries a readable `origin` marker pointing
somewhere that is gone. The unmarked caches an operator made by hand
(`/tmp/duo-dd-292`, `/tmp/duo-pr240-dd`, …) are never touched.
"""
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys

BASE = pathlib.Path("/tmp")
MARKER = "origin"


def repo_root(argv: list[str]) -> pathlib.Path:
    if len(argv) > 2:
        return pathlib.Path(argv[2]).resolve()
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if out.returncode != 0:
        raise SystemExit("derived_data_path: not inside a git checkout")
    return pathlib.Path(out.stdout.strip()).resolve()


def prune(name: str, keep: pathlib.Path) -> None:
    pattern = re.compile(rf"^duo-{re.escape(name)}-[0-9a-f]{{8}}$")
    for path in BASE.glob(f"duo-{name}-*"):
        if path == keep or not path.is_dir() or not pattern.match(path.name):
            continue
        marker = path / MARKER
        try:
            origin = marker.read_text(encoding="utf-8").strip()
        except OSError:
            # No marker: not ours to reclaim. Leave it.
            continue
        if origin and not pathlib.Path(origin).exists():
            shutil.rmtree(path, ignore_errors=True)


def main() -> int:
    if len(sys.argv) < 2 or not re.fullmatch(r"[a-z0-9-]+", sys.argv[1]):
        raise SystemExit("usage: derived_data_path.py <name> [repo-root]")
    name = sys.argv[1]
    root = repo_root(sys.argv)
    digest = hashlib.sha256(str(root).encode()).hexdigest()[:8]
    path = BASE / f"duo-{name}-{digest}"
    path.mkdir(parents=True, exist_ok=True)
    (path / MARKER).write_text(f"{root}\n", encoding="utf-8")
    prune(name, keep=path)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
