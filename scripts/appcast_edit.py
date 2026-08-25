"""Edits to a Sparkle appcast that `publish-release.sh` makes before handing the
file to `generate_appcast`.

A separate importable file rather than a heredoc, because this is parsing code
that has already failed silently twice and this repository's rule is that a
fixed parsing bug gets a regression test. See `test_appcast_edit.py`.
"""

import re

# `<item[\s>]`, not `<item>`: an item carrying any attribute — a namespace
# declaration, anything a future Sparkle emits — is still an item. Matching the
# bare tag made `strip_item` a silent no-op on such a feed, and a no-op strip
# does not fail, it produces a duplicate entry for the version being published.
_ITEM = re.compile(r"<item[\s>].*?</item>\s*", re.S)
_CDATA = re.compile(r"<!\[CDATA\[.*?\]\]>", re.S)
_CHANNEL = re.compile(r"<channel[\s>]")


def _mask_cdata(text):
    """Blank out CDATA payloads, preserving every offset.

    The item regex is lazy, so a literal `</item>` inside embedded release notes
    ends the match early and tears the item in half. Our own release notes are
    prose lifted from CHANGELOG.md and could contain anything, so the payloads
    are masked to same-length filler before matching and the spans are applied
    back to the untouched original.
    """
    return _CDATA.sub(lambda m: "\x00" * (m.end() - m.start()), text)


def channel_count(text):
    """How many `<channel>` elements the feed has.

    `strip_item` runs over the whole document, so on a multi-channel feed it
    would delete the matching item from *every* channel while `generate_appcast`
    regenerates only one — losing the other channel's entry with nothing to
    show for it. The feed is single-channel today; callers use this to refuse
    rather than to guess at scoping that has never been needed.
    """
    return len(_CHANNEL.findall(_mask_cdata(text)))


def strip_item(text, build, version):
    """Remove the item for `build`/`version` so `generate_appcast` writes a fresh
    one rather than a duplicate.

    Whole items are split out FIRST. The obvious single regex --
    `<item>.*?(<sparkle:version>BUILD</sparkle:version>|...).*?</item>` with
    DOTALL -- is wrong in a way that only shows up when you republish something
    that is not the newest entry: the lazy prefix starts at the FIRST item in
    the file and swallows every item before the match. Republishing the newest
    costs one extra entry, which is how 0.3.50 vanished from the feed on
    2026-08-22; republishing an older one empties the appcast completely.
    """
    target = re.compile(
        r"<sparkle:version>\s*%s\s*</sparkle:version>"
        r"|<sparkle:shortVersionString>\s*%s\s*</sparkle:shortVersionString>"
        % (re.escape(build), re.escape(version))
    )
    masked = _mask_cdata(text)
    out = []
    cursor = 0
    for match in _ITEM.finditer(masked):
        if not target.search(match.group()):
            continue
        out.append(text[cursor:match.start()])
        cursor = match.end()
    out.append(text[cursor:])
    return "".join(out)


def short_versions(text):
    """The marketing version of every item, newest first, as the feed orders them."""
    return [short for short, _ in item_versions(text)]


def item_versions(text):
    """`(shortVersionString, sparkle:version)` for every item, in feed order.

    Both, because the marketing string alone is not an identity: a feed can carry
    one marketing version under two build numbers, and keying the loss check on
    the string alone made one of them vanishing invisible.
    """
    out = []
    for item in _ITEM.finditer(_mask_cdata(text)):
        body = text[item.start():item.end()]
        short = re.search(
            r"<sparkle:shortVersionString>\s*([^<\s]+)\s*</sparkle:shortVersionString>", body)
        build = re.search(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", body)
        if short or build:
            out.append((short.group(1) if short else None,
                        build.group(1) if build else None))
    return out


def system_versions(text):
    """Every distinct `minimumSystemVersion` in the feed.

    `generate_appcast --maximum-versions` caps entries **per branch point**, and a
    differing minimum OS requirement is what makes a branch point. The entry-count
    rule below models a single whole-feed window, so more than one of these means
    the model no longer describes the tool's behaviour.
    """
    return sorted(set(re.findall(
        r"<sparkle:minimumSystemVersion>\s*([^<\s]+)\s*</sparkle:minimumSystemVersion>",
        _mask_cdata(text))))


def items_for_build(text, build):
    """Every item whose `sparkle:version` is `build` — more than one means the
    strip did not fire and the feed now offers the same build twice."""
    pattern = re.compile(r"<sparkle:version>\s*%s\s*</sparkle:version>" % re.escape(build))
    return [m.group() for m in _ITEM.finditer(_mask_cdata(text)) if pattern.search(m.group())]


def enclosure_length(text, build):
    """The byte count the feed advertises for `build`'s download, or None.

    Compared against the artifact actually uploaded. This is a proxy for "was
    this item regenerated", not a signature check: a surviving stale item usually
    advertises the previous binary's length, but two builds can coincide in size
    and this would not notice. The duplicate-item check is the stronger signal;
    this one catches the case where the size does differ, which is most of them.
    """
    for item in items_for_build(text, build):
        match = re.search(r'<enclosure[^>]*\slength="(\d+)"', item)
        if match:
            return int(match.group(1))
    return None


_DELTAS = re.compile(r"<sparkle:deltas[\s>].*?</sparkle:deltas>", re.S)


def archive_signatures(text):
    """`(short, build)` -> the EdDSA signature of each item's own archive.

    Only the item's release enclosure. The ones nested in `<sparkle:deltas>` sign
    a different file each — patches appearing, changing, or rolling off is the
    normal result of publishing with history present, and comparing those would
    flag every ordinary release.

    Exists because feeding past archives to `generate_appcast` (so it can cut
    patches) makes it rewrite every item it can see, not just the new one. That
    is safe only while those archives are byte-identical to what was published;
    see `check_regenerated`.
    """
    out = {}
    masked = _mask_cdata(text)
    for item in _ITEM.finditer(masked):
        body = text[item.start():item.end()]
        short = re.search(
            r"<sparkle:shortVersionString>\s*([^<\s]+)\s*</sparkle:shortVersionString>", body)
        build = re.search(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", body)
        # Drop the nested patch enclosures before looking for the archive's.
        release_only = _DELTAS.sub("", body)
        signature = re.search(r'<enclosure[^>]*\ssparkle:edSignature="([^"]+)"', release_only)
        if (short or build) and signature:
            out[(short.group(1) if short else None,
                 build.group(1) if build else None)] = signature.group(1)
    return out


def archive_urls(text):
    """`(short, build)` -> the URL of each item's own full archive.

    `generate_appcast --download-url-prefix` applies the NEW release's prefix to
    every archive present in its input directory, including historical ones. It
    therefore rewrites (for example) 0.3.61's enclosure from the v0.3.61 release
    to a nonexistent asset under v0.3.62. Patch URLs may legitimately move to the
    release that generated and uploads them; only the top-level archive is stable.
    """
    out = {}
    masked = _mask_cdata(text)
    for match in _ITEM.finditer(masked):
        body = text[match.start():match.end()]
        masked_body = masked[match.start():match.end()]
        identity = _item_identity(masked_body)
        enclosure = _archive_enclosure(masked_body)
        if identity is not None and enclosure is not None:
            out[identity] = body[enclosure.start(1):enclosure.end(1)]
    return out


def restore_archive_urls(old_text, new_text):
    """Put retained items' already-published archive URLs back after generation.

    The new item has no entry in `old_text` and is left alone. Existing items keep
    their original release URL while retaining newly generated delta enclosures.
    Spans come from same-length masks, so CDATA or a nested patch enclosure cannot
    make a replacement land on release notes or on a delta URL.
    """
    old = archive_urls(old_text)
    masked = _mask_cdata(new_text)
    out = []
    cursor = 0
    for match in _ITEM.finditer(masked):
        masked_body = masked[match.start():match.end()]
        identity = _item_identity(masked_body)
        enclosure = _archive_enclosure(masked_body)
        wanted = old.get(identity)
        if wanted is None or enclosure is None:
            continue
        start = match.start() + enclosure.start(1)
        end = match.start() + enclosure.end(1)
        out.append(new_text[cursor:start])
        out.append(wanted)
        cursor = end
    out.append(new_text[cursor:])
    return "".join(out)


def _item_identity(item):
    short = re.search(
        r"<sparkle:shortVersionString>\s*([^<\s]+)\s*</sparkle:shortVersionString>", item)
    build = re.search(r"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>", item)
    if not (short or build):
        return None
    return (short.group(1) if short else None, build.group(1) if build else None)


def _archive_enclosure(masked_item):
    # Preserve offsets while hiding patch enclosures carrying the same tag name.
    release_only = _DELTAS.sub(
        lambda match: "\x00" * (match.end() - match.start()), masked_item)
    return re.search(r'<enclosure\b[^>]*\surl="([^"]+)"', release_only)


def check_archive_urls_unchanged(old_text, new_text):
    """Complaints about retained entries whose full-download URL moved."""
    old = archive_urls(old_text)
    new = archive_urls(new_text)
    problems = []
    for entry, was in old.items():
        now = new.get(entry)
        if now is not None and now != was:
            short, build = entry
            problems.append(
                f"the regenerated appcast moved the archive URL of {short or '?'}"
                f" ({build or '?'}) from {was} to {now} — historical archives live"
                " under their own release tags, so the rewritten URL would be a 404")
    return problems


def check_signatures_unchanged(old_text, new_text):
    """Complaints about already-published items whose archive signature moved.

    A regenerated item that keeps its version but changes its signature means the
    archive on disk is not the archive users already have. Publishing that hands
    every existing user a feed whose proof does not match the bytes the release
    serves, and their update fails verification — a failure that lands on versions
    nobody touched in this release.

    Only entries present in BOTH feeds are compared: a new item has nothing to
    differ from, and one that rolled off the window is gone either way.
    """
    old = archive_signatures(old_text)
    new = archive_signatures(new_text)
    problems = []
    for entry, was in old.items():
        now = new.get(entry)
        if now is not None and now != was:
            short, build = entry
            problems.append(
                f"the regenerated appcast changed the archive signature of {short or '?'}"
                f" ({build or '?'}), which is already published — the local archive is not"
                " the one users download, and republishing this would break their update")
    return problems


def check_regenerated(old_text, new_text, want, build, asset_size, cap):
    """What the regenerated feed has to look like. Returns a list of complaints;
    empty means it is publishable.

    The rule is an exact entry count, not "did anything vanish". Counting losses
    alone waved 0.3.49 off the feed (one rolls off as one is added, so the count
    holds), and "at most one lost and it must be the oldest" is trivially true of
    a one-entry feed that lost its only entry. Knowing the cap makes it exact:
    the new feed holds everything the old one had plus this version, clipped to
    the window, and nothing else is acceptable.

    Entries are identified by `(shortVersionString, sparkle:version)`. The
    marketing string alone is not an identity — one marketing version can ship
    under two builds, and then losing one of them is invisible.
    """
    old = item_versions(old_text)
    new = item_versions(new_text)
    problems = []

    if not any(short == want for short, _ in new):
        return [f"the regenerated appcast does not contain {want} — it would publish nothing"]

    # `--maximum-versions` is documented as a cap "for each branch point (e.g.
    # with a different minimum OS requirement)", so the single-window arithmetic
    # below only describes the tool while every item shares one requirement. It
    # has, for as long as this feed has existed. If that changes, stop rather
    # than refuse a legitimate feed with a misleading message.
    branch_points = system_versions(new_text)
    if len(branch_points) > 1:
        problems.append(
            f"the regenerated appcast has {len(branch_points)} minimum-OS branch points"
            f" ({', '.join(branch_points)}); --maximum-versions caps each one separately,"
            " so the entry-count rule here no longer describes what generate_appcast does")

    # A strip that did not fire does not fail; it leaves the old item in place
    # and `generate_appcast` adds a second one. Two items for one build means the
    # feed offers the same version twice — and on a reissue the surviving old
    # item still carries the PREVIOUS binary's length and EdDSA signature while
    # the release now serves different bytes.
    duplicates = items_for_build(new_text, build)
    if len(duplicates) != 1:
        problems.append(
            f"the regenerated appcast has {len(duplicates)} items for build {build}, expected 1")
    else:
        advertised = enclosure_length(new_text, build)
        if advertised != asset_size:
            problems.append(
                f"the feed advertises {advertised} bytes for build {build} but the artifact"
                f" is {asset_size} — the item was not regenerated, so its enclosure and"
                " signature describe different bytes")

    problems.extend(check_signatures_unchanged(old_text, new_text))
    problems.extend(check_archive_urls_unchanged(old_text, new_text))

    expected = min(len(dict.fromkeys(old + [(want, build)])), cap)
    lost = [entry for entry in old if entry not in new]
    if len(new) != expected:
        detail = (f"lost {_render(lost)}" if lost
                  else "no entry is missing, so something else changed")
        problems.append(
            f"the regenerated appcast has {len(new)} entries, expected {expected} ({detail})")
    if lost and lost != old[len(old) - len(lost):]:
        problems.append(
            f"the regenerated appcast lost {_render(lost)} from the middle of the feed")
    return problems


def _render(entries):
    return ", ".join(f"{short or '?'} ({build or '?'})" for short, build in entries)
