"""Where the recipe families are, for the checkers that read them.

Imported by `check_recipe_json5.py`, `check_recipe_snapshots.py`,
`check_app_audits.py` and `check_engine_notes.py`, so the four agree on what a
family file is instead of each carrying its own glob.

A family is either
  * a `.swift` file directly under `RECIPES`, except the two infrastructure files
    `AppRecipeIndexTests.infrastructure` names, or
  * a file under `RECIPE_DATA` named `<slug>.json5` (`RecipeFamilyFile`).

`RECIPE_DATA` may hold nothing else. `.copy` ships the whole directory, and the
loader traps on any other entry, so an entry that is not a family is refused here
too rather than skipped: a `Foo.JSON5`, `foo.json` or `sub/foo.json5` would be
shipped, never loaded, and its golden deleted by the next re-record.

`reconcile` is what gives the family counts meaning. A floor of "at least one data
file" says nothing once most families are data. The goldens under `GOLDENS` are
written by Swift from `AppRecipeIndex.all`, one per family, and `RecipeGoldenTests`
holds the two sets equal, so the number of goldens is an independent count of the
families the binary actually loads. A checker whose own count differs from it is
reading the wrong set. (The goldens retire at the end of step 3, S9; this needs a
new witness then.)
"""

import os
import pathlib
import re

RECIPES = "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes"
RECIPE_DATA = "DuoUpdaterCore/Sources/DuoUpdaterCore/Resources/Recipes"
GOLDENS = "DuoUpdaterCore/Tests/RecipeGoldens"
INFRASTRUCTURE = {"AppRecipeSet.swift", "AppRecipeIndex.swift"}
# `AppRecipeIndexTests.familySlugsAreUniqueAndWellFormed`'s slug, plus the
# extension, exactly (case included). Must match `RecipeFamilyFile.isFamilyFileName`.
DATA_FILE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*\.json5")


def swift_family_files(root):
    base = pathlib.Path(root) / RECIPES
    return sorted(p for p in base.glob("*.swift") if p.name not in INFRASTRUCTURE)


def data_entries(root):
    """(path, problem or None) for every entry of RECIPE_DATA, hidden ones included."""
    return directory_entries(pathlib.Path(root) / RECIPE_DATA)


def directory_entries(base):
    """(path, problem or None) for every entry of a recipe directory — the checkout's,
    or the copy inside a built resource bundle."""
    base = pathlib.Path(base)
    out = []
    for entry in sorted(os.scandir(base), key=lambda e: e.name):
        path = base / entry.name
        if entry.is_symlink():
            problem = "is a symbolic link"
        elif not entry.is_file(follow_symlinks=False):
            problem = "is not a regular file"
        elif not DATA_FILE.fullmatch(entry.name):
            problem = "is not named <slug>.json5"
        else:
            problem = None
        out.append((path, problem))
    return out


def data_family_files(root):
    return [p for p, problem in data_entries(root) if problem is None]


def golden_count(root):
    base = pathlib.Path(root) / GOLDENS
    if not base.is_dir():
        return None
    return sum(1 for p in base.iterdir() if not p.name.startswith(".") and p.suffix == ".txt")


def reconcile(root, counted, what):
    """None when `counted` equals the number of goldens, else the message."""
    goldens = golden_count(root)
    if goldens is None:
        return f"{GOLDENS} is not under {root}, so the family count cannot be reconciled"
    if counted != goldens:
        return (f"{what}: {counted}, but {GOLDENS} holds {goldens} goldens (one per family "
                "AppRecipeIndex.all loads) — a family file is being missed, or is not loaded")
    return None
