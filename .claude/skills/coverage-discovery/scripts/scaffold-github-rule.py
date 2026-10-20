#!/usr/bin/env python3
"""Draft the files a new GitHub Releases app needs, from its real package.

    scaffold-github-rule.py OWNER/REPO --package <downloaded asset .dmg|.zip>
    scaffold-github-rule.py OWNER/REPO --facts verify-install.json --recipe-id ID

With --package (the asset exactly as GitHub serves it, file name unchanged) it
writes the four hand-written pieces every GitHub onboarding since #606 has
touched — `Recipes/<family>.swift`, its line in `AppRecipeIndex.all`,
`docs/app-audits/<family>.md` and the README row — and prints the golden and
test commands that make the fifth. The drafts carry `TODO(audit)` where only a
person or the audit can answer: whether the app updates itself, helpers, other
release tracks, the real-machine one-click.

With --facts it writes nothing and prints the rule it WOULD derive for an
existing `install-verify` item, from what that job read off the package. That
is how the derivation is checked against the hand-written rules.

It also fetches the previous and the oldest listed stable release (each up to
300 MB) and compares their bundle id, Team and version with the newest, and one
other installer of the same kind and arch in the newest release, if there is
one, for its bundle id.

Scope: one stable rule for one bundle id, a .dmg or .zip asset, a plain dotted
CFBundleShortVersionString. A package that is itself a prerelease, a .pkg or
tarball, an Intel-only asset or bundle, any other version scheme, or a Sparkle
feed in the bundle stops the script with the reason; those take an audit, not a
template. A prerelease that ships an asset of the same name, another installer
in the release with the same bundle id, a system extension or other
component, an updater the bundle carries without SUFeedURL (`app-update.yml`, a
`Sparkle.framework`), or an executable naming its own releases is drafted with a
`TODO(audit)` note instead. The checks
here only fail early; what decides is `make test`, `duo verify`,
`install-verify` and the real-machine one-click, as for a hand-written rule.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True, check=True).stdout.strip()
RECIPES = os.path.join(REPO, "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes")
INDEX = os.path.join(RECIPES, "AppRecipeIndex.swift")
AUD = os.path.join(REPO, "docs/app-audits")
README = os.path.join(AUD, "README.md")

VERSION = r"[0-9]+(?:\.[0-9]+)+"
# `HostArch.assetTokens`, so a sibling build is recognised the way the asset
# selector will classify it.
ARCH_TOKENS = {
    "arm64": ["aarch64", "arm64", "apple-silicon"],
    "x86_64": ["x86_64", "x86-64", "x64", "x86", "amd64", "intel"],
}
RECENT = 10  # stable releases the asset pattern must stay unambiguous on
OLDER_CAP = 300 * 1024 * 1024  # largest older package fetched for the identity comparison


class Stop(Exception):
    pass


def esc(text):
    """Escape for ICU regex. Unlike `re.escape`, leaves `-` and `_` alone, as
    the hand-written patterns do."""
    return re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", text)


def nums(version):
    parts = [int(n) for n in re.findall(r"[0-9]+", version)]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def find_version(text, short, prefer=()):
    """Span of the version in a tag or asset name: a whole dotted number in
    `text` equal to a literal (`prefer`, then `short`) first, then one equal
    to `short` component by component (`26.09.3` is `26.9.3`, `1.5.0` is
    `1.5`). Only whole numbers count, so `1.5` never takes the head of
    `1.5.0` and leaves its `.0` behind as literal pattern text."""
    found = list(re.finditer(VERSION, text))
    for literal in (*prefer, short):
        for m in found:
            if literal and m.group() == literal:
                return m.span()
    for m in found:
        if nums(m.group()) == nums(short):
            return m.span()
    return None


def arch_marks(name):
    """(arch, token, start, end) for each standalone arch marker in `name`,
    with `HostArch.isMarked`'s boundary rule."""
    lower = name.lower()
    found = []
    for arch, tokens in ARCH_TOKENS.items():
        for token in tokens:
            for m in re.finditer(re.escape(token), lower):
                s, e = m.span()
                if (s == 0 or not lower[s - 1].isalnum()) and (e == len(lower) or not lower[e].isalnum()):
                    found.append((arch, name[s:e], s, e))
    # `x86_64` also contains `x86`: keep the longest marker at a position.
    found.sort(key=lambda f: (f[2], -(f[3] - f[2])))
    kept, end = [], -1
    for f in found:
        if f[2] >= end:
            kept.append(f)
            end = f[3]
    return kept


def arch_class(name):
    archs = {a for a, *_ in arch_marks(name)}
    return archs.pop() if len(archs) == 1 else "neutral"


def gh_releases(owner, repo):
    # A request on its own fails now and then (TLS handshake timeout, EOF); a
    # retry is not a different answer.
    for attempt in range(3):
        p = subprocess.run(["gh", "api", f"repos/{owner}/{repo}/releases?per_page=100"],
                           capture_output=True, text=True)
        if p.returncode == 0 or "HTTP 4" in p.stderr:
            break
        time.sleep(2 * (attempt + 1))
    if p.returncode:
        raise Stop(f"GitHub API: {p.stderr.strip()}")
    return [r for r in json.loads(p.stdout) if not r.get("draft")]


def generalise(text, vspan, vrep, build):
    """`text` as an anchored pattern: the version span becomes `vrep`, and a
    dotless build number standing on its own (Sequel Ace's tag
    `production/6.0.3-20116`, SwiftBar's `SwiftBar.v2.1.1.b597.zip`) becomes
    `[0-9]+` — left literal, it would match this release only."""
    holes = [(vspan[0], vspan[1], vrep)] if vspan else []
    if build.isdigit():
        for m in re.finditer(r"(?<![0-9.])" + build + r"(?![0-9])", text):
            if not (vspan and m.start() < vspan[1] and m.end() > vspan[0]):
                holes.append((m.start(), m.end(), "[0-9]+"))
    out, at = "^", 0
    for s, e, r in sorted(holes):
        out += esc(text[at:s]) + r
        at = e
    return out + esc(text[at:]) + "$"


def derive(owner, repo, facts, releases):
    """The rule, from package facts and the repository's releases."""
    notes = []
    asset = facts["asset"]
    short = facts["shortVersion"] or ""
    carrying = [r for r in releases if any(a["name"] == asset for a in r["assets"])]
    if not carrying:
        raise Stop(f"no release among the newest {len(releases)} carries an asset named {asset}")

    def digest_of(r):
        return next(a.get("digest") for a in r["assets"] if a["name"] == asset)

    # Which release the package IS. A name alone does not say when it carries no
    # version: Lapce ships `Lapce-macos.dmg` in every release, and the newest one
    # holding that name is its `nightly` prerelease, not the v0.4.6 package given.
    if facts.get("tag"):
        rel = next((r for r in carrying if r["tag_name"] == facts["tag"]), None)
    elif facts.get("sha256"):
        rel = next((r for r in carrying if digest_of(r) == f"sha256:{facts['sha256']}"), None)
    else:
        rel = None
    if rel is None:
        rel = next((r for r in carrying if not r.get("prerelease") and find_version(r["tag_name"], short)),
                   carrying[0])
    tag = rel["tag_name"]
    if rel.get("prerelease"):
        raise Stop(f"the package is {tag}, a prerelease: a channel rule, which this template does not draft")
    twins = [r["tag_name"] for r in carrying if r.get("prerelease")]
    if twins:
        notes.append(f"prerelease {', '.join(twins[:3])} ships an asset of the same name: TODO(audit) — "
                     "likely another track on the same bundle id; download it, diff its Info.plist "
                     "with this one, and settle it per app-audit's coverage checklist")
    if facts.get("sparkleFeedURL"):
        raise Stop(f"the bundle declares SUFeedURL {facts['sparkleFeedURL']}: "
                   "SparkleAppcastSource covers it with no rule")
    if facts.get("loginItems"):
        notes.append(f"login items {', '.join(facts['loginItems'])}: TODO(audit) — a launcher that "
                     "exits is fine; a resident agent keeps the old code running after the swap "
                     "(loginItemAgentRestarts)")

    for c in facts.get("components", []):
        notes.append(f"{c}: TODO(audit) — runs outside the app; check what a bundle swap does to it")
    if facts.get("exeReferences", []) is None:
        notes.append("`strings` is not installed, so the executable was not searched for its own "
                     "releases: TODO(audit) find out whether it updates itself")
    own = [r for r in facts.get("exeReferences") or [] if f"/{owner}/{repo}/releases".lower() in r.lower()]
    if own:
        notes.append(f"the executable names its own releases ({own[0]}): TODO(audit) — it likely "
                     "updates itself; find out how, and whether it races ours")
    # Neither stops the script: no generic source reads a runtime Sparkle feed or
    # a non-generic electron provider, so a rule may still be the answer. The yml
    # is quoted as written — Hyper's names `zeit/hyper`, the repo's old name.
    electron = facts.get("electronUpdater")
    if electron is not None:
        said = " ".join(f"{k}={v}" for k, v in electron.items()) or "no provider"
        if electron.get("provider", "").lower() == "generic" and electron.get("url"):
            notes.append(f"app-update.yml ({said}): TODO(audit) — electron-updater updates it itself, and "
                         "ElectronManifestSource already reads that manifest with no rule (last in SourceStack, "
                         "so a rule would answer first); find out whether a rule is needed at all")
        else:
            notes.append(f"app-update.yml ({said}): TODO(audit) — electron-updater updates it itself; "
                         "find out whether it races ours")
    for s in facts.get("sparkleFrameworks") or []:
        notes.append(f"{s} with no SUFeedURL: TODO(audit) — Sparkle with its feed set at runtime; find the "
                     "feed (feed-discover, SparkleFeedCatalog) and whether it races ours")

    if not re.fullmatch(VERSION, short):
        raise Stop(f"CFBundleShortVersionString {short!r} is not a plain dotted version: "
                   "the version pattern needs writing by hand")
    span = find_version(tag, short)
    if span is None:
        raise Stop(f"tag {tag} carries no version equal to the bundle's "
                   f"CFBundleShortVersionString {short!r}")
    tag_version = tag[span[0]:span[1]]
    build = facts.get("bundleVersion") or ""
    version_pattern = generalise(tag, span, f"({VERSION})", build)
    stable = [r for r in releases if not r.get("prerelease")]
    read = [r for r in stable if re.search(version_pattern, r["tag_name"])]
    unread = [r["tag_name"] for r in stable if r not in read]
    notes.append(f"versionPattern reads {len(read)} of the {len(stable)} stable tags listed"
                 + (f"; not: {', '.join(unread[:6])}{' …' if len(unread) > 6 else ''}" if unread else ""))

    # Asset pattern: the file name with its version (and a build number
    # embedded beside it) generalised. Its arch marker stays literal: DuoUpdater
    # runs on arm64 only (`ARCHS` in App/project.yml), so an Intel sibling is
    # never the asset it should pick.
    if arch_class(asset) == "x86_64":
        raise Stop(f"{asset} is an Intel build; DuoUpdater is arm64-only — pass the arm64 or universal asset")
    # A name with no arch marker says nothing: Journey's `Journey-darwin-2.14.6.zip`
    # is x86_64 only. `--facts` carries no architectures and skips this.
    archs = facts.get("architectures") or []
    if archs and not any(a.startswith("arm64") for a in archs):
        raise Stop(f"{asset} is an Intel build ({' '.join(archs)}); DuoUpdater is arm64-only — "
                   "pass the arm64 or universal asset")
    # An `arm64e` slice alone is Apple silicon too, and runs on macOS 27.2 with no
    # boot-arg (measured 10-20); before macOS 26 a third party's arm64e reportedly
    # needed `-arm64e_preview_abi`, and DuoUpdater supports 15.
    if archs and "arm64" not in archs:
        notes.append(f"the only Apple silicon slice is {', '.join(a for a in archs if a.startswith('arm64'))}: "
                     "TODO(audit) — check it launches on macOS 15 (DuoUpdater's floor) before offering it")
    names = {a["name"] for a in rel["assets"]}
    asset_pattern = generalise(asset, find_version(asset, short, prefer=(tag_version,)), VERSION, build)
    match_pattern = asset_pattern

    if asset.endswith(".dmg"):
        kind = ".dmg"
    elif asset.endswith(".zip"):
        kind = ".zip"
    else:
        raise Stop(f"{asset}: only .dmg and .zip assets are in this template's scope")

    for r in read[:RECENT]:
        hits = [a["name"] for a in r["assets"] if re.search(asset_pattern, a["name"])]
        per = {}
        for h in hits:
            per.setdefault(arch_class(h), []).append(h)
        crowded = {k: v for k, v in per.items() if len(v) > 1}
        if crowded:
            raise Stop(f"the asset pattern {asset_pattern} picks more than one {', '.join(crowded)} "
                       f"build in {r['tag_name']}: {crowded}")
        if not hits:
            notes.append(f"{r['tag_name']} has no asset the pattern matches (offered as no macOS build)")
    others = sorted(n for n in names - {asset}
                    if re.search(r"\.(dmg|zip|pkg)$", n) and not re.search(asset_pattern, n)
                    and not re.search(r"(?i)windows|win32|win64|linux|\.(msi|exe|deb|rpm|appimage)", n))
    if others:
        notes.append(f"other installers in {tag} the pattern leaves out: {', '.join(others)}")
    # One of the same kind for the same machine may be another product under the
    # same id: ActivityWatch ships `activitywatch-tauri-v0.14.1-macos-arm64.dmg`
    # and `activitywatch-v0.14.1-macos-arm64.dmg`. `same_id_product` reads it.
    # Debug symbols are no product (AltTab's `Sparkle.framework.dSYM.zip`).
    siblings = [{k: a.get(k) for k in ("name", "size", "digest", "browser_download_url")}
                for a in rel["assets"] if a["name"] in others and ".dsym." not in a["name"].lower()
                and a["name"].endswith(kind) and arch_class(a["name"]) == arch_class(asset)]

    digest = next(a.get("digest") for a in rel["assets"] if a["name"] == asset)
    if facts.get("sha256") and digest and digest != f"sha256:{facts['sha256']}":
        raise Stop(f"{asset} hashes to sha256:{facts['sha256']}, GitHub publishes {digest}")

    trust = None
    team = facts.get("teamIdentifier")
    if team and "spctl" in facts and "Notarized" not in facts["spctl"]:
        notes.append(f"spctl says {facts['spctl']!r}, not Notarized Developer ID — "
                     "coverage-discovery's bar for one-click; the install gate itself does not check it")
    if not team:
        missing = []
        if facts.get("sealOK") is not True:
            missing.append("the seal does not pass codesign --verify --deep --strict")
        if facts.get("signedIdentifier") != facts["bundleIdentifier"]:
            missing.append(f"signed identifier {facts.get('signedIdentifier')!r} is not the bundle id")
        if not digest:
            missing.append("GitHub publishes no digest for the asset")
        if missing:
            notes.append("ad-hoc and " + "; ".join(missing) + " — detection-only")
            asset_pattern, kind = None, None
        else:
            trust = ".publishedDigestOnly"

    return {
        "tag": tag, "tagVersion": tag_version, "assetCount": len(rel["assets"]),
        "digest": digest,
        "versionPattern": version_pattern, "installAssetPattern": asset_pattern,
        "installerKind": kind, "installTrust": trust, "notes": notes,
        "matchPattern": match_pattern, "readTags": [r["tag_name"] for r in read],
        "siblings": siblings,
    }


def same_id_product(facts, d):
    """Read one of `d["siblings"]` and say whether it is this bundle id. Two
    products under one id (ActivityWatch's Tauri and classic builds, both
    `net.activitywatch.ActivityWatch` 0.14.1, Team XM9GC3SUL2) are one rule to
    DuoUpdater, which then installs this asset over the other's copies."""
    if not d["siblings"]:
        return []
    a = d["siblings"][0]
    if a["size"] > OLDER_CAP:
        return [f"{a['name']} is {a['size'] // 2**20} MB, not fetched — TODO(audit) compare its Info.plist "
                "with this one by hand"]
    tmp = tempfile.mkdtemp(prefix="scaffold-sibling.")
    try:
        dest = os.path.join(tmp, a["name"])
        if subprocess.run(["curl", "-sSfL", "--connect-timeout", "20", "--max-time", "900",
                           "-o", dest, a["browser_download_url"]]).returncode:
            return [f"{a['name']}: download failed — TODO(audit) compare its Info.plist with this one by hand"]
        o = package_facts(dest)
    except Stop as e:
        if "no .app at the top" in str(e):
            return [f"{a['name']} holds no .app at its top: not compared"]
        return [f"{a['name']}: {e} — TODO(audit) compare it by hand"]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if a.get("digest") and a["digest"] != f"sha256:{o['sha256']}":
        return [f"{a['name']}: the download does not hash to GitHub's digest — retry before trusting it"]
    if o["bundleIdentifier"] != facts["bundleIdentifier"]:
        return []
    return [f"{a['name']} in {d['tag']} is the same bundle id (version {o['shortVersion']}, Team "
            f"{o['teamIdentifier'] or 'none'}): TODO(audit) — another product or build under the same id; "
            "the rule would replace its users' copy with this one"]


def older_identities(owner, repo, releases, facts, d):
    """Read the previous and the oldest listed stable release the way the newest
    was read, and say where they differ: app-audit's coverage checklist wants
    every bundle id and Team a user may still have, and the newest package
    alone hid both of TaskExplorer's (2.x shipped as
    `com.objective-see.TaskExplorer`) and Lapce's `0.10.0-dev` early builds."""
    # Every stable release, not only the ones `versionPattern` reads: a copy from
    # under an older tag scheme is a copy users may still have, and is compared too.
    stable = [r for r in releases if not r.get("prerelease")]
    tags = [r["tag_name"] for r in stable]
    picks = []
    if d["tag"] in tags and tags.index(d["tag"]) + 1 < len(stable):
        picks.append(stable[tags.index(d["tag"]) + 1])
    if stable and stable[-1]["tag_name"] != d["tag"] and stable[-1] not in picks:
        picks.append(stable[-1])
    lines = []
    for r in picks:
        tag = r["tag_name"]
        a = next((a for a in r["assets"]
                  if re.search(d["matchPattern"], a["name"]) and arch_class(a["name"]) != "x86_64"), None)
        if a is None:
            lines.append(f"{tag}: no asset the pattern matches — TODO(audit) read an older package by hand")
            continue
        if a["size"] > OLDER_CAP:
            lines.append(f"{tag}: {a['name']} is {a['size'] // 2**20} MB, not fetched — TODO(audit) compare it by hand")
            continue
        tmp = tempfile.mkdtemp(prefix="scaffold-older.")
        try:
            dest = os.path.join(tmp, a["name"])
            if subprocess.run(["curl", "-sSfL", "--connect-timeout", "20", "--max-time", "900",
                               "-o", dest, a["browser_download_url"]]).returncode:
                lines.append(f"{tag}: download failed — TODO(audit) compare it by hand")
                continue
            o = package_facts(dest)
        except Stop as e:
            lines.append(f"{tag}: {e}")
            continue
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if a.get("digest") and a["digest"] != f"sha256:{o['sha256']}":
            lines.append(f"{tag}: the download does not hash to GitHub's digest — retry before trusting it")
            continue
        same, said = [], len(lines)
        if o["bundleIdentifier"] == facts["bundleIdentifier"]:
            same.append("bundle id")
        elif (o["bundleIdentifier"] or "").lower() == facts["bundleIdentifier"].lower():
            lines.append(f"{tag}: bundle id `{o['bundleIdentifier']}` differs only in case — TODO(audit) "
                         "a BundleIDMigration entry, or those copies match no rule")
        else:
            lines.append(f"{tag}: bundle id `{o['bundleIdentifier']}` — TODO(audit) the same app under an "
                         "older id (BundleIDMigration) or another product")
        if o["teamIdentifier"] == facts["teamIdentifier"]:
            same.append("Team")
        else:
            lines.append(f"{tag}: Team {o['teamIdentifier'] or 'none (ad-hoc)'} — TODO(audit) the install gate "
                         "refuses copies signed by another Team")
        # An installed copy is compared against `/releases/latest` whatever its own
        # tag looked like (UTM's pre-v2.1.0 tags, GitHubReleasesSource) — which
        # reaches it only while its version numbers below the newest. An older
        # scheme that numbers higher (a year-based 2019.1 before a 1.0) never is.
        # Compared only when both are plain dotted numbers. `VersionComparator`
        # ranks text (`2.0.0-rc` below `2.0.0`), and re-implementing it here would
        # be a second copy of production logic to drift; a version with text gets
        # a line that claims neither way.
        older = o["shortVersion"] or ""
        if not re.fullmatch(VERSION, older):
            lines.append(f"{tag}: the bundle says {older!r}, not a plain dotted version — not compared "
                         f"with {facts['shortVersion']!r} here; VersionComparator decides whether its copies "
                         "are offered the update")
        elif nums(older) >= nums(facts["shortVersion"] or ""):
            lines.append(f"{tag}: the bundle says {older!r}, not below the newest "
                         f"{facts['shortVersion']!r} — TODO(audit) copies of it are never offered the update")
        elif tag not in d["readTags"]:
            lines.append(f"{tag}: versionPattern does not read this tag (an older tag scheme) — its copies "
                         f"({o['shortVersion']}) are still offered the newest release; its notes get no history entry")
        if find_version(tag, o["shortVersion"] or "") is None:
            lines.append(f"{tag}: the bundle says {o['shortVersion']!r} — TODO(audit) copies of that build "
                         "never compare with the tags")
        else:
            same.append("version = tag")
        if len(same) == 3 and len(lines) == said:
            lines.append(f"{tag} ({a['name']}): same bundle id and Team, version matches its tag")
    return lines


# MARK: - Package facts

def package_facts(path):
    p = subprocess.run([os.path.join(HERE, "check-bundle.sh"), path], capture_output=True, text=True)
    out = p.stdout
    if "no .app at the top" in out or "attach failed" in out or "not a .dmg or .zip" in out:
        raise Stop(out.strip())

    def val(key):
        m = re.search(rf"^  {re.escape(key)}=(.*)$", out, re.M)
        v = m.group(1).strip() if m else None
        return None if v in (None, "", "<none>") else v

    nested = re.findall(r"^  nested (\S.*?) id=", out, re.M)
    components = re.findall(r"^  component (.*)$", out, re.M)
    references = re.findall(r"^  exe-references (?!unavailable)(.*)$", out, re.M)
    if re.search(r"^  exe-references unavailable", out, re.M):
        references = None
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    spctl = re.search(r"^  spctl source=(.*)$", out, re.M)
    # An empty value is dropped, as `ElectronUpdateConfig.parse` does (QQ's `url: ''`).
    electron = re.search(r"^  updater electron-updater(.*)$", out, re.M)
    if electron:
        electron = {k: v for k, _, v in (kv.partition("=") for kv in electron.group(1).split()) if v}
    return {
        "asset": os.path.basename(path),
        "bundleIdentifier": val("CFBundleIdentifier"),
        "name": val("CFBundleName"),
        "shortVersion": val("CFBundleShortVersionString"),
        "bundleVersion": val("CFBundleVersion"),
        "minimumSystemVersion": val("LSMinimumSystemVersion"),
        "sparkleFeedURL": val("SUFeedURL"),
        "architectures": (val("archs") or "").split(),
        "teamIdentifier": val("TeamIdentifier") if val("TeamIdentifier") != "not set" else None,
        "signedIdentifier": val("Identifier"),
        "sealOK": val("codesign-verify-exit") == "0",
        "spctl": spctl.group(1).strip() if spctl else "rejected",
        "nested": nested,
        "loginItems": [n for n in nested if "Library/LoginItems/" in n],
        "components": components,
        "exeReferences": references,
        "electronUpdater": electron,
        "sparkleFrameworks": re.findall(r"^  updater sparkle-framework (.*)$", out, re.M),
        "sha256": sha,
    }


def verify_install_facts(path, recipe_id):
    report = json.load(open(path))
    item = next((i for i in report["items"] if i["recipeID"] == recipe_id), None)
    if item is None or not item.get("identity") or not item.get("url"):
        raise Stop(f"{recipe_id}: no downloaded identity in {path}")
    parts = urllib.parse.urlparse(item["url"]).path.split("/")
    if "download" not in parts:
        raise Stop(f"{recipe_id}: {item['url']} is not a release asset URL")
    i = parts.index("download")
    ident = item["identity"]
    return {
        "asset": urllib.parse.unquote(parts[-1]), "tag": urllib.parse.unquote("/".join(parts[i + 1:-1])),
        "bundleIdentifier": ident.get("bundleIdentifier"), "shortVersion": ident.get("shortVersion"),
        "bundleVersion": ident.get("bundleVersion"), "sparkleFeedURL": ident.get("sparkleFeedURL"),
        "teamIdentifier": ident.get("teamIdentifier"), "signedIdentifier": ident.get("signedIdentifier"),
        # install-verify only gets to an identity once the seal has verified.
        "sealOK": item["status"] != "failed",
    }


# MARK: - Drafts

def swift_raw(pattern):
    if '"#' in pattern:
        raise Stop(f"{pattern} would end a #\"…\"# literal early")
    return f'#"{pattern}"#'


def family_file(family, enum, owner, repo, f, d):
    team = f"Team {f['teamIdentifier']}" if f["teamIdentifier"] else "ad-hoc signed (no Team ID)"
    lines = []
    if d["installTrust"]:
        lines.append("// Shared rationale for digest-only: Recipes/org-alacritty.swift.")
        lines.append("")
    elif not d["installAssetPattern"]:
        lines.append("// Shared rationale for Detection-only: Recipes/org-alacritty.swift.")
        lines.append("")
    lines += [
        f"// {f.get('name') or repo} — TODO(audit): what the app is, whether it updates",
        "// itself (Sparkle, electron-updater, its own, none) and how, and any",
        "// helper that keeps running across a bundle swap.",
        "//",
        f"// Tags read `{d['tag']}`; the bundle says {f['shortVersion']}"
        + (f" (build {f['bundleVersion']})." if f.get("bundleVersion") not in (None, f["shortVersion"]) else "."),
        f"// `{f['asset']}`, "
        + ("the only asset" if d["assetCount"] == 1 else f"one of {d['assetCount']} assets")
        + f" in {d['tag']}, is",
        f"// {f['bundleIdentifier']}, {team}" + (", notarized." if "Notarized" in f.get("spctl", "") else "."),
    ]
    args = [f'bundleID: "{f["bundleIdentifier"]}"', f'owner: "{owner}", repo: "{repo}"',
            f"versionPattern: {swift_raw(d['versionPattern'])}"]
    if d["installAssetPattern"]:
        args += [f"installAssetPattern: {swift_raw(d['installAssetPattern'])}",
                 f"installerKind: {d['installerKind']}"]
    if d["installTrust"]:
        args.append(f"installTrust: {d['installTrust']}")
    body = "\n".join(("        " + l).rstrip() for l in lines)
    call = ",\n".join("            " + a for a in args)
    return (f"import Foundation\n\nenum {enum} {{\n    static let set = AppRecipeSet(\n"
            f'        family: "{family}",\n        githubRules: [\n{body}\n'
            f"        GitHubReleaseRule(\n{call}),\n        ])\n}}\n")


def insert_index_line(family, enum):
    slugs = sorted((f[:-6] for f in os.listdir(RECIPES)
                    if f.endswith(".swift") and f not in ("AppRecipeIndex.swift", "AppRecipeSet.swift")),
                   key=str.lower)
    before = [s for s in slugs if s.lower() < family.lower()]
    src = open(INDEX).read()
    line = f"        {enum}.set,\n"
    if before:
        prev = re.search(r"^enum (\w+)", open(os.path.join(RECIPES, before[-1] + ".swift")).read(), re.M).group(1)
        anchor = f"        {prev}.set,\n"
        assert src.count(anchor) == 1, anchor
        src = src.replace(anchor, anchor + line)
    else:
        anchor = "    public static let all: [AppRecipeSet] = [\n"
        assert src.count(anchor) == 1
        src = src.replace(anchor, anchor + line)
    open(INDEX, "w").write(src)


def audit_doc(family, owner, repo, f, d, today):
    team = f"`{f['teamIdentifier']}`" if f["teamIdentifier"] else "**无（ad-hoc 签名）**"
    if d["installTrust"]:
        oneclick = "支持（**digest-only**：用户在设置里允许、且 GitHub 发布了 digest 时才给）"
    elif d["installAssetPattern"]:
        oneclick = "支持"
    else:
        oneclick = "仅检测（" + next((n for n in d["notes"] if n.startswith("ad-hoc")), "") + "）"
    notes = "\n".join(f"- {n}" for n in d["notes"]) or "- —"
    older = "\n".join(f"  - {n}" for n in d.get("older", [])) or "  - （列表里没有更早的稳定版）"
    parts = f.get("nested", []) + f.get("components", [])
    unpack = (f"ditto -x -k {f['asset']} x && " if f["asset"].endswith(".zip") else "")
    target = "x/*.app" if f["asset"].endswith(".zip") else f["asset"]
    return f"""# {f.get('name') or repo}

## 基本信息
- Bundle ID: `{f['bundleIdentifier']}`
- 仓库: `{owner}/{repo}`
- Team ID: {team}；`codesign --verify --deep --strict` {'通过' if f['sealOK'] else '未通过'}；spctl: {f.get('spctl')}
- 观测版本: {f['shortVersion']}（tag `{d['tag']}`，资产 `{f['asset']}`）；观测日期: {today}
- 自更新机制: TODO(audit)
- 分发: TODO(audit)（GitHub Releases 之外：Homebrew cask、MAS、官网）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | TODO    | TODO     | TODO | ✓     | —           |

当前生效源: **GitHub**（TODO(audit): channel-verify 实测）

## 覆盖清单
- 各版本的 bundle id / Team（脚本读了最新、上一版和列表里最老的稳定版）:
  - {d['tag']}: `{f['bundleIdentifier']}`，Team {f['teamIdentifier'] or '无'}
{older}
- 其他轨: TODO(audit)
- 主机下限: TODO(audit)（`App/project.yml` 的 ARCHS / deployment target）

## Channel 详情

TODO(audit): 有没有 prerelease / beta / nightly，各自什么 bundle id（release 列表、源码）。

## 更新检测
- 源: `{owner}/{repo}` GitHub Releases，`/releases/latest`
- 版本方案: tag `{d['tag']}` → `CFBundleShortVersionString` `{f['shortVersion']}`、`CFBundleVersion` `{f.get('bundleVersion')}`
- `versionPattern` `{d['versionPattern']}`
- install pattern `{d['installAssetPattern']}`
{notes}

## 按架构 / 按 OS 分轨
- 架构: {' '.join(f.get('architectures') or []) or '没查'}；`LSMinimumSystemVersion`: {f.get('minimumSystemVersion') or '无'}

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 没查 | 没查 |
| 证据 | | | |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 没查 | 没查 | 没查 |

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: TODO(audit)（channel-verify 的 `changelog pane` 行）

## 一键安装
- 状态: {oneclick}
- 端到端: 未跑（TODO(audit): 真机从上一版装到最新版）
- 格式: {d['installerKind'] or '—'}
- 嵌套 / 常驻组件: {', '.join(parts) if parts else '无'}
- 校验: GitHub digest {('`' + d['digest'] + '`，与下载的包一致') if d['digest'] else '未发布'}
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

## 已知问题
- TODO(audit)

## 如何复验
```bash
gh release download {d['tag']} --repo {owner}/{repo} --pattern '{f['asset']}'
.claude/skills/coverage-discovery/scripts/check-bundle.sh {f['asset']}
{unpack}swift run --package-path application-test channel-verify {target} --expect stable
```
"""


def insert_readme_row(family, f, d, today):
    kind = (d["installerKind"] or "").lstrip(".")
    if d["installTrust"]:
        what = f"G (**digest-only**，ad-hoc 签名，{kind})"
    elif d["installAssetPattern"]:
        what = f"G (one-click {kind})"
    else:
        what = "G (detection-only)"
    row = (f"- [ ] [**{f.get('name') or family}**]({family}.md) · `{f['bundleIdentifier']}` — {what}"
           f" · 真包 {f['shortVersion']} 核对 ✓ · 一键端到端未跑 · changelog 未核 · {today}\n")
    lines = open(README, encoding="utf-8").readlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("## Single-channel — GitHub Releases"))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("## "))
    last = max(i for i in range(start, end) if lines[i].strip())
    lines.insert(last + 1, row)
    open(README, "w", encoding="utf-8").writelines(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("repo", help="OWNER/REPO")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--package", help="the downloaded release asset, file name as GitHub serves it")
    src.add_argument("--facts", help="an install-verify run's verify-install.json")
    ap.add_argument("--recipe-id", help="with --facts: the item to derive, e.g. github:owner/repo:stable")
    a = ap.parse_args()
    owner, _, repo = a.repo.partition("/")
    today = datetime.date.today().isoformat()
    try:
        if a.facts:
            if not a.recipe_id:
                ap.error("--facts needs --recipe-id")
            facts = verify_install_facts(a.facts, a.recipe_id)
            print(json.dumps({"recipeID": a.recipe_id, **derive(owner, repo, facts, gh_releases(owner, repo))},
                             ensure_ascii=False))
            return 0

        facts = package_facts(a.package)
        bid = facts["bundleIdentifier"]
        if not bid:
            raise Stop("the package's Info.plist has no CFBundleIdentifier")
        family = bid.replace(".", "-")
        enum = re.sub(r"[^A-Za-z0-9_]", "_", family)
        path = os.path.join(RECIPES, family + ".swift")
        if os.path.exists(path):
            raise Stop(f"{os.path.relpath(path, REPO)} already exists")
        taken = subprocess.run(["grep", "-rlF", f'"{bid}"', RECIPES], capture_output=True, text=True).stdout.split()
        if taken:
            raise Stop(f"{bid} is already named in {', '.join(os.path.relpath(t, REPO) for t in taken)}")
        releases = gh_releases(owner, repo)
        d = derive(owner, repo, facts, releases)
        d["notes"] += same_id_product(facts, d)
        d["older"] = older_identities(owner, repo, releases, facts, d)
        d["notes"] += [n for n in d["older"] if "TODO(audit)" in n or "retry" in n]

        open(path, "w").write(family_file(family, enum, owner, repo, facts, d))
        insert_index_line(family, enum)
        doc = os.path.join(AUD, family + ".md")
        if not os.path.exists(doc):
            open(doc, "w", encoding="utf-8").write(audit_doc(family, owner, repo, facts, d, today))
        insert_readme_row(family, facts, d, today)
    except Stop as e:
        print(f"stop: {e}", file=sys.stderr)
        return 1

    print(f"drafted {family} ({bid}) from {owner}/{repo} {d['tag']}")
    for n in d["notes"]:
        print(f"  note: {n}")
    if facts["nested"]:
        print(f"  note: nested apps: {', '.join(facts['nested'])}")
    print(f"""
written:
  {os.path.relpath(path, REPO)}
  {os.path.relpath(INDEX, REPO)} (one line)
  {os.path.relpath(doc, REPO)}
  {os.path.relpath(README, REPO)} (one row)
next:
  - resolve every TODO(audit) in the two drafts (app-audit's coverage checklist)
  - DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests
  - make test""")
    if d["installTrust"]:
        print("  - digest-only also names the app in DigestOnlyRecipeTests, the Settings text in\n"
              "    App/Sources/Settings/GeneralSettingsPage.swift and every translation of it")
    print("  - real-machine one-click from the previous release, then the README row's [ ] and 一键端到端")
    return 0


if __name__ == "__main__":
    sys.exit(main())
