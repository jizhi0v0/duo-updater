"""Future-input probe driver.

Builds the probe input from every finished run's stable rule (scores.json) plus
the reference rule (ref/out), runs ZZPatternProbe in the reference build, and
classifies each run:

  NEXT-MISS   the plain next release's tag or asset is not read  -> detection or
              one-click breaks on the very next release (a real bug)
  SUFFIX-AS-STABLE  an rc/beta tag is read as the bare version -> a phantom
              update if the vendor forgets the prerelease flag (latent risk)
  ok

Usage: python3 probe.py   (after score.py has written scores.json)
"""
import json, os, subprocess

B = os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench")
H = os.path.dirname(os.path.abspath(__file__))

# Two-part next tags, for vendors whose history HAS two-part tags (gh api, 2026-10-13):
# Search shipped v1.0; AirCard shipped v1.0, v1.1, v1.2. Others never have.
SHORT = {"search": "v1.1", "aircard": "v1.3"}
# Next major versions: MeetingBar has v5.0.0 tagged (prerelease); others are the plain next major.
SHORT.update({"meetingbar": "v5.0.0", "openinterminal": "v3.0.0", "secretive": "v5.0.0"})

# Per case: (plain next tag, suffixed tags, next asset, suffixed assets)
SYN = {
    "rustgis": ("v0.3.0", ["v0.3.0-rc.1", "v0.3.0-beta.2"],
                "RustGIS-0.3.0-macos-aarch64.dmg", ["RustGIS-0.3.0-rc.1-macos-aarch64.dmg"]),
    "plexo": ("v1.0.0-rc.16", ["v1.1.0-beta.1"],
              "plexo-1.0.0-rc.16-arm64.dmg", ["plexo-1.1.0-beta.1-arm64.dmg"]),
    "pulse": ("v0.1.13", ["v0.2.0-rc.1"],
              "Pulse.0.1.13.arm64.dmg", ["Pulse.0.2.0-rc.1.arm64.dmg"]),
    "search": ("v1.0.5", ["v1.1.0-beta.1"], "Search.dmg", []),
    "herdr": ("v20261014.1", ["v20261014.1-rc.1"],
              "Herdr-20261014.1-universal-apple-darwin.dmg", []),
    "reviu": ("v1.7.0", ["v1.7.0-rc.1"],
              "Reviu-1.7.0-macos-aarch64.dmg", ["Reviu-1.7.0-rc.1-macos-aarch64.dmg"]),
    "aircard": ("v1.2.7", ["v1.3.0-beta.1"], "AirCard.dmg", []),
    # v0.2.8 is real (published 2026-10-13T09:53Z, after the runs were graded)
    "astrlink": ("v0.2.8", ["v0.3.0-rc.1"],
                 "AstrLink_0.2.8_aarch64.dmg", ["AstrLink_0.3.0-rc.1_aarch64.dmg"]),
    "yomado": ("v0.3.4", ["v0.4.0-beta.1"],
               "Yomado-v0.3.4.zip", ["Yomado-v0.4.0-beta.1.zip"]),
    # round 3 (tag shapes from each vendor's real recent releases, 2026-10-13)
    "macdown": ("v3000.0.8", ["v3000.0.8-rc.2"], "MacDown-3000.0.8.dmg", ["MacDown-3000.0.8-rc.2.dmg"]),
    "secretive": ("v4.0.1", ["v4.1.0-beta.1"], "Secretive.zip", []),
    "neovide": ("0.16.3", ["nightly", "0.17.0-rc.1"], "Neovide-aarch64-apple-darwin.dmg", []),
    "meetingbar": ("v4.11.7", ["v5.0.0-rc2"], "MeetingBar.dmg", []),
    "crystalfetch": ("v2.2.1", ["v2.3.0-beta.1"], "CrystalFetch.dmg", []),
    "cryptomator": ("1.19.4", ["1.20.0-rc1", "1.19.0-rc1.1"], "Cryptomator-1.19.4-arm64.dmg", ["Cryptomator-1.20.0-rc1-arm64.dmg"]),
    "finicky": ("v4.2.3", ["v4.4.0-alpha", "v4.2.1-beta"], "Finicky.dmg", []),
    "openinterminal": ("v2.3.10", [], "OpenInTerminal.zip", []),
    "obelisk": ("v0.2.6", ["v0.3.0-beta.1"], "Obelisk-0.2.6-mac-arm64.dmg", []),
    "diri": ("v0.9.8", ["v1.0.0-rc.1"], "diri-0.9.8-universal.zip", ["diri-1.0.0-rc.1-universal.zip"]),
    "magpie": ("v0.1.1227", ["v0.2.0-beta.1"], "magpie-darwin-arm64.zip", []),
    "designcraft": ("v0.7.2", ["v0.7.2-beta.1"], "designcraft-0.7.2-macos-universal.dmg", ["designcraft-0.7.2-beta.1-macos-universal.dmg"]),
    "effectcraft": ("v0.9.3", ["v0.9.3-beta.1"], "effectcraft-0.9.3-macos-universal.dmg", ["effectcraft-0.9.3-beta.1-macos-universal.dmg"]),
    "filmcraft": ("v0.7.3", ["v0.7.3-beta.1"], "filmcraft-0.7.3-macos-universal.dmg", ["filmcraft-0.7.3-beta.1-macos-universal.dmg"]),
    "lightcraft": ("v0.7.2", ["v0.7.2-beta.1"], "lightcraft-0.7.2-macos-universal.dmg", ["lightcraft-0.7.2-beta.1-macos-universal.dmg"]),
    "photocraft": ("v0.8.3", ["v0.8.3-beta.1"], "photocraft-0.8.3-macos-universal.dmg", ["photocraft-0.8.3-beta.1-macos-universal.dmg"]),
    "vectorcraft": ("v0.10.1", ["v0.10.1-beta.1"], "vectorcraft-0.10.1-macos-universal.dmg", ["vectorcraft-0.10.1-beta.1-macos-universal.dmg"]),
    "lokii": ("v0.1.2", ["v0.2.0-beta.1"], "Lokii-arm64.dmg", []),
    "cindy": ("v0.1.106", ["v0.1.105-beta"], "cindy-0.1.106-darwin-arm64-global.dmg", ["cindy-0.1.105-beta-darwin-arm64-global.dmg"]),
    "spotifast": ("v0.12.1", ["v0.13.0-rc.1"], "spotifast-v0.12.1-macos-universal.dmg", ["spotifast-v0.13.0-rc.1-macos-universal.dmg"]),
    "disktree": ("v0.11.1", ["v0.12.0-rc.1"], "disktree-0.11.1-aarch64-macos.zip", ["disktree-0.12.0-rc.1-aarch64-macos.zip"]),
    # trap set (2026-10-17; tag shapes from each vendor's real releases). Loop's dev build is
    # the one rolling `prerelease` tag; Picard's betas are `release-3.0.0rc4`-style. Cork,
    # Krita and Snipaste are not read from GitHub, so they have no entry here.
    "loop": ("1.4.3", ["prerelease", "1.5.0-beta.1"], "Loop.zip", []),
    "switchhosts": ("v5.0.3", ["v5.0.3-beta.4"], "SwitchHosts-5.0.3-mac-universal.dmg", ["SwitchHosts-5.0.3-beta.4-mac-universal.dmg"]),
    "picard": ("release-3.0.3", ["release-3.1.0rc1", "release-3.1.0b1"], "MusicBrainz-Picard-3.0.3-macOS-13.0-arm64.dmg", ["MusicBrainz-Picard-3.1.0rc1-macOS-13.0-arm64.dmg"]),
    "zettlr": ("v4.8.1", ["v4.9.0-beta.1"], "Zettlr-4.8.1-arm64.dmg", ["Zettlr-4.9.0-beta.1-arm64.dmg"]),
}


def stable_rule(rules, bundle=None):
    for r in rules or []:
        if r["channel"] == "stable" and (bundle is None or r["bundleID"] == bundle):
            return r
    return None


items, meta = [], {}
rows = json.load(open(B + "/scores.json"))
for r in rows:
    case = r["case"]
    rule = stable_rule(r["rules"])
    key = "%s-%s" % (case, r["model"])
    meta[key] = (case, rule)
for case in SYN:
    p = B + "/ref/out/%s.json" % case
    if os.path.exists(p):
        meta["%s-REF" % case] = (case, stable_rule(json.load(open(p))["rules"]))

for key, (case, rule) in meta.items():
    if rule is None or case not in SYN:
        continue
    nt, st, na, sa = SYN[case]
    ap = rule["installAssetPattern"]
    items.append(dict(run=key, versionPattern=rule["versionPattern"],
                      installAssetPattern=None if ap == "<nil>" else ap,
                      tags=[nt] + st + ([SHORT[case]] if case in SHORT else []), assets=[na] + sa))

inp, outp = B + "/probe-in.json", B + "/probe-out.json"
json.dump(items, open(inp, "w"), indent=1)
ref = B + "/ref/main/DuoUpdaterCore"
probe_src = H + "/ZZPatternProbe.swift"
dst = ref + "/Tests/DuoUpdaterCoreTests/ZZPatternProbe.swift"
subprocess.run(["cp", probe_src, dst], check=True)
env = dict(os.environ, BENCH_PROBE_IN=inp, BENCH_PROBE_OUT=outp)
res = subprocess.run(["swift", "test", "--filter", "ZZPatternProbe"], cwd=ref, env=env,
                     capture_output=True, text=True)
if res.returncode != 0:
    print(res.stdout[-3000:], res.stderr[-2000:])
    raise SystemExit("probe build/run failed")

result = {o["run"]: o for o in json.load(open(outp))}
for key in sorted(result):
    case = meta[key][0]
    nt, st, na, sa = SYN[case]
    o = result[key]
    flags = []
    if o["tags"].get(nt) in (None, "<no match>"):
        flags.append("NEXT-MISS tag %s" % nt)
    if o["assets"] and o["assets"].get(na) == "rejected":
        flags.append("NEXT-MISS asset %s" % na)
    if case in SHORT and o["tags"].get(SHORT[case]) in (None, "<no match>"):
        flags.append("NEXT-MISS two-part tag %s (vendor has shipped this shape)" % SHORT[case])
    for t in st:
        v = o["tags"].get(t)
        if v not in (None, "<no match>") and "-" not in v:
            flags.append("SUFFIX-AS-STABLE %s→%s" % (t, v))
    print("%-16s %s" % (key, "; ".join(flags) or "ok"),
          "| tags", o["tags"], "| assets", o["assets"])
