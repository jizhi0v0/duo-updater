#!/usr/bin/env python3
"""Read `hostArchitectures` out of remote flat `.pkg` installers, without
downloading them.

This is the second witness for `duo verify`'s `pkgarch` sweep (CLAUDE.md:
"凡是正确性落在一条规则上的,把规则移植到 Python 打真实响应体"). The Swift
implementation in `CLI/Sources/DuoKit/PackageArchitectureProbe.swift` reads the
same bytes; this one exists so the two can be diffed against the real registry
rather than against each other's assumptions.

Why range reads: a flat package is a xar archive — a 28-byte header, then a
zlib-compressed table of contents, then the heap. The TOC carries every file's
offset and length inside the heap, so `Distribution` / `PackageInfo` come out in
two small Range requests. Expanding the payload instead (`pkgutil --expand-full`)
is what #400 rejected as unaffordable: the Office packages are GB-scale, and this
path reads all of them for a couple of hundred kilobytes.

    scripts/pkg_host_architectures.py < urls.tsv        # bundleID<TAB>channel<TAB>version<TAB>url
    duo verify --pkgarch --report r.json                # the same check, in Swift

Output is TSV: bundleID, channel, version, value, where-it-was-found.
`value` is the declaration verbatim, or `ABSENT` (no declaration in either file
— the common case, 7 of 22 measured 2026-09-07), or `NOT-XAR` (the URL did not
serve a flat package: a DMG-wrapped pkg, or a vendor serving HTML).

⚠️ The declaration is the VENDOR'S CLAIM, not the payload's real slices. It is
not a substitute for Gate 5, which reads the actual Mach-O — see
`PackageInstaller`'s architecture-limitation comment. Measured 2026-09-07, every
one of the 15 declarations in this registry is universal, and the only packages
that are architecture-specific (WeChat DevTools, `..._darwin_arm64.pkg`) declare
nothing at all. So this reads drift, not installability.
"""
import argparse, re, struct, sys, urllib.error, urllib.request, zlib
import xml.etree.ElementTree as ET

XAR_MAGIC = b"xar!"
UA = "duo-updater pkg_host_architectures (+https://github.com/jizhi0v0/duo-updater)"
# Enough for any Distribution seen in this registry; Edge's is 716 bytes. Caps a
# hostile or broken endpoint rather than streaming whatever it offers.
MAX_MEMBER = 4 << 20


class Fetcher:
    """Range reader that keeps a byte total, so the cost of a sweep is a number
    rather than an impression."""

    def __init__(self, timeout=90):
        self.timeout = timeout
        self.bytes = 0

    def range(self, url, start, end):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        req.add_header("Range", f"bytes={start}-{end}")
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            # A server that ignores Range answers 200 with the whole file. Reading
            # only what was asked for keeps an Office package from arriving here.
            data = r.read(end - start + 1)
        self.bytes += len(data)
        return data


def _inflate(raw, style):
    if not style or ("gzip" not in style and "zlib" not in style and "bzip2" not in style):
        return raw
    try:
        return zlib.decompress(raw)
    except zlib.error:
        try:
            return zlib.decompressobj(-15).decompress(raw)   # raw deflate
        except zlib.error:
            return raw                                        # leave it; regex just misses


def host_architectures(url, fetch):
    """(value, where) for one package URL. Never raises for a vendor-side
    problem — the caller files that as data, not as a crash."""
    head = fetch.range(url, 0, 27)
    if head[:4] != XAR_MAGIC:
        return "NOT-XAR", f"magic={head[:4]!r}"
    header_size = struct.unpack(">H", head[4:6])[0]
    toc_compressed = struct.unpack(">Q", head[8:16])[0]
    if toc_compressed <= 0 or toc_compressed > MAX_MEMBER:
        return "NOT-XAR", f"toc={toc_compressed}"
    toc = zlib.decompress(fetch.range(url, header_size, header_size + toc_compressed - 1))
    root = ET.fromstring(toc)
    heap = header_size + toc_compressed

    members = {}
    for f in root.iter("file"):
        name = f.findtext("name") or ""
        if name not in ("Distribution", "PackageInfo") or name in members:
            continue
        data = f.find("data")
        if data is None:
            continue
        enc = data.find("encoding")
        members[name] = (int(data.findtext("offset")), int(data.findtext("length")),
                         enc.get("style") if enc is not None else "")

    # Distribution first: on a product archive it is the file that carries the
    # declaration, and a component PackageInfo beside it may not repeat it.
    for name in ("Distribution", "PackageInfo"):
        if name not in members:
            continue
        offset, length, style = members[name]
        if length > MAX_MEMBER:
            continue
        body = _inflate(fetch.range(url, heap + offset, heap + offset + length - 1), style)
        found = re.search(rb'hostArchitectures\s*=\s*"([^"]*)"', body)
        if found:
            return found.group(1).decode("utf-8", "replace"), name
    return "ABSENT", "+".join(sorted(members)) or "no Distribution/PackageInfo"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timeout", type=float, default=90)
    args = ap.parse_args()

    fetch = Fetcher(timeout=args.timeout)
    rows = 0
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            print(f"✗ expected 4 tab-separated fields, got {len(parts)}: {line[:80]}",
                  file=sys.stderr)
            return 2
        bundle_id, channel, version, url = parts
        try:
            value, where = host_architectures(url, fetch)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError,
                zlib.error, ET.ParseError, struct.error, ValueError) as exc:
            value, where = "ERROR", f"{type(exc).__name__}: {exc}"[:70]
        print(f"{bundle_id}\t{channel}\t{version}\t{value}\t{where}", flush=True)
        rows += 1
    print(f"# {rows} package(s), {fetch.bytes / 1024:.1f} KB fetched", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
