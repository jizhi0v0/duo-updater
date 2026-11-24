"""Validate release-only transitions before carrying a tested product tree forward."""
import base64
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import appcast_edit

REPO = "jizhi0v0/duo-updater"
PROJECT = "App/project.yml"
INFO = "App/Info.plist"
FEED = "appcast.xml"
NOTES = {"CHANGELOG.md", *("changelog/" + locale + ".md" for locale in
                          "de es fr it ja pt-BR ru tr zh-Hans zh-Hant".split())}
SP = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
VERSION = r"[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[1-9][0-9]*)?"


def git(*args):
    return subprocess.check_output(["git", *args]).decode()


def blob(commit, path):
    return git("show", f"{commit}:{path}")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def project(commit):
    text = blob(commit, PROJECT)
    settings = []
    for key, pattern in [("MARKETING_VERSION", VERSION), ("CURRENT_PROJECT_VERSION", r"[1-9][0-9]*")]:
        regex = rf'(?m)^( +{key}: ")({pattern})("$)'
        matches = re.findall(regex, text)
        require(len(matches) == 2 and matches[0][1] == matches[1][1], f"inconsistent {key}")
        settings.append(matches[0][1])
        text = re.sub(regex, r'\g<1>VALUE\3', text)
    return settings[0], settings[1], text


def version_order(version):
    stable, beta, sequence = version.partition("-beta.")
    return tuple(map(int, stable.split("."))) + (not beta, int(sequence or 0))


def validate_metadata(base, head):
    old_version, old_build, old_project = project(base)
    version, build, new_project = project(head)
    if old_project != new_project:
        return False  # Mixed product and version change: require the full suite.
    old_feed = blob(base, FEED)
    require(int(build) > max([int(old_build)] + [int(b) for _, b in appcast_edit.item_versions(old_feed)]),
            "build must advance beyond the project and published builds")
    require(version_order(version) > version_order(old_version) and version not in appcast_edit.short_versions(old_feed),
            "expected a new release version")
    expected_channel = "beta" if "-beta." in version else "stable"
    old_info, new_info = (blob(rev, INFO) for rev in (base, head))
    # Keep every other byte, including types, duplicate keys and substitutions.
    channel_pattern = r"(<key>DuoReleaseChannel</key>\s*<string>)(stable|beta)(</string>)"
    normal, count = re.subn(channel_pattern, rf"\g<1>{expected_channel}\3", old_info)
    if count != 1 or normal != new_info:
        return False
    for path in NOTES:
        old, new = (blob(rev, path) for rev in (base, head))
        intro, marker, history = old.partition("\n## ")
        require(marker and new.startswith(intro + f"\n## {version}\n\n")
                and new.endswith(marker + history), f"release heading or history differs in {path}")
        note = new[len(intro + f"\n## {version}\n\n"):-len(marker + history)]
        if re.search(rf"(?m)^## {VERSION}$", note):
            return False  # Paired stable/beta preparation has multiple new sections.
        require(note.strip() and "\n## " not in note, f"invalid release section in {path}")

    return True


def verify_assets(item, version, build, channel, key):
    release = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPO}/releases/tags/v{version}"], timeout=30))
    require(release["tag_name"] == "v" + version and not release["draft"]
            and release["prerelease"] == (channel == "beta"), "release visibility/channel mismatch")
    assets = {a["name"]: a for a in release["assets"]}
    archive = f"DuoUpdater-{version}-macos.zip"
    links = item.findall("enclosure")
    require(len(links) == 1, "expected one main enclosure")
    deltas = item.findall(SP + "deltas/enclosure")
    expected = {archive} | {name for name in assets if name.endswith(".delta")}
    seen = set()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        # RFC 8410 SubjectPublicKeyInfo for the Ed25519 key used by Sparkle.
        (root / "key").write_bytes(bytes.fromhex("302a300506032b6570032100") + base64.b64decode(key, validate=True))
        for entry in links + deltas:
            source = entry.get(SP + "deltaFrom", "")
            if entry in deltas:
                require(source.isdecimal() and int(source) < int(build), "unexpected delta base")
            name = archive if entry in links else f"DuoUpdater{build}-{source}.delta"
            attrs = {"url", "length", "type", SP + "edSignature"}
            if entry in deltas:
                attrs.update(SP + k for k in ("deltaFrom", "deltaFromSparkleExecutableSize", "deltaFromSparkleLocales"))
            require(not set(entry.attrib) - attrs and entry.get("type") == "application/octet-stream"
                    and not len(entry), "unexpected enclosure attributes")
            asset = assets.get(name)
            url = f"https://github.com/{REPO}/releases/download/v{version}/{name}"
            require(asset and name not in seen and asset["state"] == "uploaded"
                    and asset["browser_download_url"] == entry.get("url") == url
                    and str(asset["size"]) == entry.get("length"), "feed does not match release asset " + name)
            seen.add(name)
            payload = root / "asset"
            subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                            "--proto", "=https", "--max-time", "90", "--output", str(payload), url], check=True)
            require("sha256:" + hashlib.sha256(payload.read_bytes()).hexdigest() == asset["digest"],
                    "download digest mismatch")
            (root / "sig").write_bytes(base64.b64decode(entry.get(SP + "edSignature", ""), validate=True))
            valid = subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                            "-inkey", str(root / "key"), "-sigfile", str(root / "sig"),
                            "-in", str(payload)], check=False)
            require(valid.returncode == 0, "invalid Sparkle signature for " + name)
    require(seen == expected, "incomplete set of release enclosures")


def validate_feed(base, head):
    old, new = (blob(rev, FEED) for rev in (base, head))
    version, build, _ = project(head)
    channel = plistlib.loads(blob(head, INFO).encode())["DuoReleaseChannel"]
    old_rss, rss = (ET.fromstring(text) for text in (old, new))
    items = rss.findall("./channel/item")
    old_items = old_rss.findall("./channel/item")
    by_build = {i.findtext(SP + "version"): i for i in old_items}
    added = [i for i in items if i.findtext(SP + "version") not in by_build]
    if len(added) != 1 or int(build) <= max(int(b) for _, b in appcast_edit.item_versions(old)):
        return False  # Reissues, repairs and multi-release feeds retain full CI.
    item = added[0]
    require(item.findtext(SP + "version") == build and item.findtext(SP + "shortVersionString") == version
            and item.findtext(SP + "channel", "stable") == channel, "wrong release item")
    require(next((i for i in items if i.findtext(SP + "channel", "stable") == channel), None) is item,
            "new release must lead its channel")
    project_text = blob(head, PROJECT)
    floor = re.search(r'(?m)^    macOS: "([0-9.]+)"$', project_text)
    arch = re.search(r'(?m)^  ARCHS: (\w+)$', project_text)
    require(floor and arch and item.findtext(SP + "minimumSystemVersion") == floor[1]
            and item.findtext(SP + "hardwareRequirements") == arch[1], "release system requirements differ")
    fields = {"title", "pubDate", "link", "description", "enclosure", SP + "deltas", SP + "channel",
              SP + "minimumSystemVersion", SP + "hardwareRequirements", SP + "shortVersionString", SP + "version"}
    require(not item.attrib and all(child.tag in fields and len(item.findall(child.tag)) == 1 for child in item),
            "unexpected rollout fields")
    for child in item:
        if child.tag == "enclosure":
            continue  # Checked with its asset.
        if child.tag == "description":
            require(child.attrib == {SP + "format": "markdown"}, "unexpected release notes format")
        else:
            require(not child.attrib, "unexpected release field attributes")
        if child.tag == SP + "deltas":
            require(all(e.tag == "enclosure" for e in child), "unexpected delta field")
        else:
            require(not len(child), "unexpected nested item field")
    require(item.findtext("title") == version and item.findtext("link") ==
            f"https://github.com/{REPO}/releases/tag/v{version}", "release title or link differs")
    for doc in (rss, old_rss):
        group = doc.find("channel")
        for entry in group.findall("item"):
            group.remove(entry)
    require(ET.tostring(rss) == ET.tostring(old_rss), "RSS channel outside of items changed")
    old_channel, new_channel = (appcast_edit.channel_feed(doc, channel) for doc in (old, new))
    issues = appcast_edit.check_regenerated(old_channel, new_channel, version, build,
                                             appcast_edit.enclosure_length(new_channel, build), 5)
    require(not issues, str(issues))
    # The generator may remove the previous release's inline notes. Every other
    # retained item, including signed deltas and entries on other channels, stays intact.
    retained = [i for i in items if i is not added[0]]
    for i in retained:
        previous = by_build[i.findtext(SP + "version")]
        if i.findtext(SP + "channel", "stable") == channel:
            # Sparkle regenerates or omits inline Markdown for older archives.
            for entry in (previous, i):
                notes = entry.find("description")
                if notes is not None:
                    entry.remove(notes)
        ET.indent(previous)
        ET.indent(i)
        require(ET.tostring(previous).strip() == ET.tostring(i).strip(), "retained release changed")
    def other_builds(seq):
        return [i.findtext(SP + "version") for i in seq if i.findtext(SP + "channel", "stable") != channel]

    require(other_builds(old_items) == other_builds(items), "other release channel changed")
    verify_assets(added[0], version, build, channel, plistlib.loads(blob(head, INFO).encode())["SUPublicEDKey"])
    return True


def release_transition(base, head):
    # Raw modes (not just paths) exclude deletes, symlinks, renames and executable bits.
    records = git("diff", "--no-renames", "--raw", "-z", base, head).rstrip("\0").split("\0")
    names = set(records[1::2])
    if not names or any(not r.startswith(":100644 100644 ") for r in records[::2]):
        return False
    if names == {FEED}:
        return validate_feed(base, head)
    elif names in (NOTES | {PROJECT}, NOTES | {PROJECT, INFO}):
        return validate_metadata(base, head)
    return False
