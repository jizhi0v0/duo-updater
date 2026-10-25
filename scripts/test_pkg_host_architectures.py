#!/usr/bin/env python3
"""`pkg_host_architectures.py` must not inflate what a remote package names.

The reads are range-bounded (`MAX_MEMBER`), but a few KB of zlib inflate to
gigabytes, and the TOC and each member went through `zlib.decompress` with no
ceiling. The Swift probe stops at 32 MiB (`maxInflatedBytes`); so does this. Run
by `make test-scripts`.

    python3 scripts/test_pkg_host_architectures.py
"""

import pathlib
import struct
import sys
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pkg_host_architectures as pha  # noqa: E402

# `maxInflatedBytes` in CLI/Sources/DuoKit/PackageArchitectureProbe.swift.
LIMIT = 32 << 20


def raw_deflate(data):
    c = zlib.compressobj(wbits=-15)
    return c.compress(data) + c.flush()


class Memory:
    """A `Fetcher` over bytes in memory."""

    def __init__(self, blob):
        self.blob = blob
        self.bytes = 0

    def range(self, url, start, end):
        data = self.blob[start:end + 1]
        self.bytes += len(data)
        return data


def xar(toc_xml, heap=b""):
    toc = zlib.compress(toc_xml)
    header = b"xar!" + struct.pack(">HHQQI", 28, 1, len(toc), len(toc_xml), 1)
    assert len(header) == 28
    return header + toc + heap


def one_file_toc(name, length, style="application/x-gzip"):
    return (f'<xar><toc><file id="1"><name>{name}</name><data><offset>0</offset>'
            f'<length>{length}</length><encoding style="{style}"/></data></file></toc></xar>'
            ).encode()


class BoundedInflate(unittest.TestCase):
    def test_the_limit_is_the_swift_probes(self):
        self.assertEqual(pha.MAX_INFLATED, LIMIT)

    def test_an_ordinary_stream_inflates(self):
        for wbits, make in ((zlib.MAX_WBITS, zlib.compress), (-15, raw_deflate)):
            self.assertEqual(pha._bounded_inflate(make(b"hostArchitectures"), wbits),
                             b"hostArchitectures")

    def test_a_stream_of_exactly_the_limit_is_accepted(self):
        data = b"\0" * LIMIT
        self.assertEqual(len(pha._bounded_inflate(zlib.compress(data), zlib.MAX_WBITS)), LIMIT)

    def test_a_stream_one_byte_over_the_limit_is_refused(self):
        bomb = zlib.compress(b"\0" * (LIMIT + 1))
        self.assertLess(len(bomb), 64 << 10)   # the point: small on the wire
        with self.assertRaises(ValueError):
            pha._bounded_inflate(bomb, zlib.MAX_WBITS)

    def test_a_truncated_stream_is_still_a_zlib_error(self):
        # The raw-deflate fallback in `_inflate` is keyed on this.
        with self.assertRaises(zlib.error):
            pha._bounded_inflate(zlib.compress(b"x" * 1000)[:-8], zlib.MAX_WBITS)

    def test_inflate_refuses_a_bomb_in_either_framing(self):
        data = b"\0" * (LIMIT + 1)
        for raw in (zlib.compress(data), raw_deflate(data)):
            with self.assertRaises(ValueError):
                pha._inflate(raw, "application/x-gzip")

    def test_inflate_still_reads_both_framings_and_leaves_the_rest(self):
        self.assertEqual(pha._inflate(zlib.compress(b"abc"), "application/x-gzip"), b"abc")
        self.assertEqual(pha._inflate(raw_deflate(b"abc"), "application/x-gzip"), b"abc")
        self.assertEqual(pha._inflate(b"plain", ""), b"plain")
        self.assertEqual(pha._inflate(b"not deflate at all", "application/x-gzip"),
                         b"not deflate at all")


class HostArchitectures(unittest.TestCase):
    def test_a_declaration_is_still_found(self):
        body = zlib.compress(b'<installer-gui-script><options hostArchitectures="arm64,x86_64"/>')
        blob = xar(one_file_toc("Distribution", len(body)), body)
        self.assertEqual(pha.host_architectures("u", Memory(blob)),
                         ("arm64,x86_64", "Distribution"))

    def test_a_toc_that_inflates_past_the_limit_is_refused(self):
        toc = zlib.compress(b"\0" * (LIMIT + 1))
        blob = b"xar!" + struct.pack(">HHQQI", 28, 1, len(toc), LIMIT + 1, 1) + toc
        with self.assertRaises(ValueError):
            pha.host_architectures("u", Memory(blob))

    def test_a_member_that_inflates_past_the_limit_is_refused(self):
        body = zlib.compress(b"\0" * (LIMIT + 1))
        blob = xar(one_file_toc("Distribution", len(body)), body)
        with self.assertRaises(ValueError):
            pha.host_architectures("u", Memory(blob))


if __name__ == "__main__":
    unittest.main()
