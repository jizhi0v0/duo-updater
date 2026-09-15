#!/usr/bin/env python3
"""Print the recipe digest of a recipe directory, or fail.

    python3 scripts/recipe_digest.py <Recipes directory>

`scripts/build-cli.sh` passes the checkout's digest to the `duo-cli` build, where it
lands in the binary's embedded Info.plist under `DuoRecipeDigest`, and checks the
built and installed bundles against it. At runtime `RecipeFamilyFile.loadAll`
computes the same digest over the bytes it decodes and refuses a mismatch; see
"The recipe digest" on `RecipeFamilyFile`.

Two implementations of one hash is the drift this repository keeps warning about
(`SourceStamp` asks the binary instead, which is impossible here: the digest has
to exist before the binary does). So both are held to one known answer:
`test_recipe_digest.py` and `AppRecipeIndexTests.theRecipeDigestHasOneKnownAnswer`
build the same two-file fixture and expect the same hex.

The framing: SHA-256 over each file in name order of `"<name>\\n<byte count>\\n"`
then its bytes. A directory with anything but regular `<slug>.json5` files in it,
or with none, is refused (exit 1) — the loader would trap on it anyway, and a
digest over a directory the binary cannot load is not worth recording.
"""

import hashlib
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import recipe_families  # noqa: E402


def digest(directory):
    """(hex digest, None) or (None, problem)."""
    directory = pathlib.Path(directory)
    if not directory.is_dir():
        return None, f"{directory} is not a directory"
    entries = recipe_families.directory_entries(directory)
    refused = [f"{p.name} ({problem})" for p, problem in entries if problem]
    if refused:
        return None, f"{directory} holds entries that are not family files: {', '.join(refused)}"
    if not entries:
        return None, f"{directory} holds no family files"
    hasher = hashlib.sha256()
    for path, _ in sorted(entries, key=lambda e: e[0].name):
        data = path.read_bytes()
        hasher.update(f"{path.name}\n{len(data)}\n".encode())
        hasher.update(data)
    return hasher.hexdigest(), None


def main(argv):
    if len(argv) != 1:
        print("usage: recipe_digest.py <Recipes directory>", file=sys.stderr)
        return 2
    value, problem = digest(argv[0])
    if problem:
        print(f"✗ {problem}", file=sys.stderr)
        return 1
    print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
