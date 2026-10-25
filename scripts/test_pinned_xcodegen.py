#!/usr/bin/env python3
"""XcodeGen must come from `scripts/pinned-xcodegen.sh`, never from PATH or brew.

The .xcodeproj XcodeGen writes is a build input, and the scripts that run it
(`notarize.sh`, `publish-release.sh`, `install.sh`, `build-cli.sh`) do so with a
Developer ID identity, and for `publish-release.sh` the Sparkle EdDSA key, in
reach. A replaced `xcodegen` on PATH (or a `brew` formula that moved) therefore
reaches the signed product. Run by `make test-scripts`.

    python3 scripts/test_pinned_xcodegen.py

Nothing here touches the network: the download tests point the script at a
`file://` zip through its test-only override and run it with a throwaway HOME.
"""

import hashlib
import http.server
import os
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
import threading
import unittest
import zipfile

SCRIPTS = pathlib.Path(__file__).resolve().parent
REPO = SCRIPTS.parent
PINNED = SCRIPTS / "pinned-xcodegen.sh"
WORKFLOWS = sorted((REPO / ".github" / "workflows").glob("*.yml"))
# Scripts that generate the project and then sign it (or hold the signing key).
SIGNING_SCRIPTS = ["notarize.sh", "publish-release.sh", "install.sh", "build-cli.sh"]


def code_lines(path):
    """The file's lines minus whole-line comments (shell and YAML both use `#`)."""
    return [ln for ln in path.read_text().splitlines()
            if not ln.lstrip().startswith("#")]


class NoPathOrBrewXcodegen(unittest.TestCase):
    def test_no_workflow_brew_installs_xcodegen(self):
        self.assertTrue(WORKFLOWS, "no workflows found")
        for wf in WORKFLOWS:
            for ln in code_lines(wf):
                self.assertNotRegex(
                    ln, r"brew\s+install\b.*\bxcodegen\b",
                    f"{wf.name}: brew resolves whatever the formula is today; "
                    "use scripts/pinned-xcodegen.sh")

    def test_every_workflow_that_installs_xcodegen_uses_the_pinned_script(self):
        installing = [wf for wf in WORKFLOWS
                      if re.search(r"name:\s*Install XcodeGen", wf.read_text())]
        # The three that existed when this was written; a new one is covered
        # automatically, a deleted one should be a deliberate edit here.
        self.assertEqual({wf.name for wf in installing},
                         {"ci.yml", "recipe-autofix.yml", "release-build.yml"})
        for wf in installing:
            self.assertIn("scripts/pinned-xcodegen.sh", wf.read_text(), wf.name)

    def test_version_and_hash_are_defined_only_in_the_script(self):
        for wf in WORKFLOWS:
            text = wf.read_text()
            self.assertNotRegex(text, r"XCODEGEN_(VERSION|SHA256)", wf.name)
            self.assertNotIn("yonaskolb/XcodeGen/releases", text, wf.name)
        text = PINNED.read_text()
        self.assertRegex(text, r'(?m)^XCODEGEN_VERSION="\d+\.\d+\.\d+"$')
        self.assertRegex(text, r'(?m)^XCODEGEN_SHA256="[0-9a-f]{64}"$')

    def test_signing_scripts_never_use_xcodegen_from_path(self):
        for name in SIGNING_SCRIPTS:
            path = SCRIPTS / name
            for ln in code_lines(path):
                self.assertNotRegex(ln, r"command\s+-v\s+xcodegen", f"{name}: {ln!r}")
                self.assertNotRegex(
                    ln, r"(?<![\w./\"$-])xcodegen\s+generate", f"{name}: {ln!r}")
            self.assertIn("pinned-xcodegen.sh", path.read_text(), name)


def make_zip(path, version="2.46.0", payload=None):
    """A zip shaped like XcodeGen's release asset, with a stub `xcodegen`."""
    body = payload or f'#!/bin/sh\necho "Version: {version}"\n'
    with zipfile.ZipFile(path, "w") as z:
        info = zipfile.ZipInfo("xcodegen/bin/xcodegen")
        info.external_attr = (stat.S_IFREG | 0o755) << 16
        z.writestr(info, body)
        z.writestr("xcodegen/share/xcodegen/note.txt", "resource\n")
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


class PinnedScript(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="duo-pinned-xcodegen-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.good = self.tmp / "good.zip"
        self.good_sha = make_zip(self.good)

    def script_with_hash(self, sha):
        """A copy of the real script whose pinned hash is `sha`.

        Only for the paths that need a zip that PASSES; the rejection tests run
        the real, unmodified script against the real hash.
        """
        copy = self.tmp / "pinned-copy.sh"
        text = PINNED.read_text()
        new, n = re.subn(r'(?m)^XCODEGEN_SHA256="[0-9a-f]{64}"$',
                         f'XCODEGEN_SHA256="{sha}"', text)
        self.assertEqual(n, 1)
        copy.write_text(new)
        copy.chmod(0o755)
        return copy

    def run_script(self, script, url, **extra):
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home),
               "DUO_XCODEGEN_TEST_URL": url, **extra}
        return subprocess.run(["bash", str(script)], env=env,
                              capture_output=True, text=True)

    @property
    def cache(self):
        return self.home / "Library" / "Caches" / "duo-updater"

    # Mutation: drop the hash comparison and any zip is unpacked and its
    # `xcodegen` handed to a signing script.
    def test_a_zip_with_the_wrong_hash_is_refused(self):
        run = self.run_script(PINNED, self.good.as_uri())
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertEqual(run.stdout, "", "printed a path for an unverified binary")
        self.assertIn("SHA-256", run.stderr)
        leftovers = [p for p in self.cache.rglob("*")
                     if p.name.endswith(".zip") or p.name == "xcodegen"]
        self.assertEqual(leftovers, [], "unverified bytes were kept in the cache")

    # Mutation: drop `-f` from curl and the 404 page is saved as the zip, so the
    # failure becomes a hash mismatch; delete `|| fail "could not download"` and
    # the script dies on curl's own status with no message. Either turns this red.
    # A loopback server, not a missing file:// path: curl exits non-zero on that
    # with or without `-f`, so it would not reach either branch.
    def test_a_failed_download_is_an_error_not_an_empty_path(self):
        class NotFound(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = b"<html><body>Not Found</body></html>"
                self.send_response(404)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), NotFound)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        run = self.run_script(PINNED, f"http://127.0.0.1:{server.server_port}/xcodegen.zip")
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(run.stdout, "")
        self.assertIn("could not download", run.stderr)
        self.assertNotIn("SHA-256", run.stderr)
        self.assertEqual(list(self.cache.rglob("*.zip")), [], "an error page was kept as the zip")

    def test_a_good_zip_yields_a_working_binary_path(self):
        script = self.script_with_hash(self.good_sha)
        run = self.run_script(script, self.good.as_uri())
        self.assertEqual(run.returncode, 0, run.stderr)
        path = pathlib.Path(run.stdout.strip())
        self.assertTrue(path.is_file() and os.access(path, os.X_OK), run.stdout)
        self.assertTrue(str(path).startswith(str(self.cache)), path)
        out = subprocess.run([str(path), "--version"], capture_output=True, text=True)
        self.assertIn("2.46.0", out.stdout)

    def test_the_second_run_uses_the_cache_without_downloading(self):
        script = self.script_with_hash(self.good_sha)
        first = self.run_script(script, self.good.as_uri())
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.run_script(script, (self.tmp / "gone.zip").as_uri())
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, first.stdout)

    # Mutation: trust the cached zip without re-hashing it.
    def test_a_tampered_cached_zip_is_not_trusted(self):
        script = self.script_with_hash(self.good_sha)
        self.assertEqual(self.run_script(script, self.good.as_uri()).returncode, 0)
        (cached,) = self.cache.rglob("*.zip")
        cached.write_bytes(cached.read_bytes() + b"x")
        # No download available: must refuse, not run the tampered zip.
        refused = self.run_script(script, (self.tmp / "gone.zip").as_uri())
        self.assertNotEqual(refused.returncode, 0, refused.stdout)
        self.assertEqual(refused.stdout, "")
        self.assertIn("does not match the pinned SHA-256", refused.stderr)
        # Download available: replaced by the verified one.
        healed = self.run_script(script, self.good.as_uri())
        self.assertEqual(healed.returncode, 0, healed.stderr)
        self.assertEqual(hashlib.sha256(cached.read_bytes()).hexdigest(), self.good_sha)

    # Mutation: reuse the already-unpacked binary after only checking it exists.
    def test_a_tampered_unpacked_binary_is_replaced_from_the_verified_zip(self):
        script = self.script_with_hash(self.good_sha)
        first = self.run_script(script, self.good.as_uri())
        binary = pathlib.Path(first.stdout.strip())
        binary.write_text("#!/bin/sh\necho FAKE\n")
        second = self.run_script(script, (self.tmp / "gone.zip").as_uri())
        self.assertEqual(second.returncode, 0, second.stderr)
        out = subprocess.run([second.stdout.strip(), "--version"],
                             capture_output=True, text=True)
        self.assertIn("2.46.0", out.stdout)
        self.assertNotIn("FAKE", out.stdout)

    # Mutation: drop the symlink check and a planted link redirects the cache.
    def test_a_symlinked_cache_directory_is_refused(self):
        target = self.tmp / "elsewhere"
        target.mkdir()
        self.cache.parent.mkdir(parents=True)
        self.cache.symlink_to(target)
        script = self.script_with_hash(self.good_sha)
        run = self.run_script(script, self.good.as_uri())
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertIn("is a symlink", run.stderr)
        self.assertEqual(list(target.iterdir()), [], "wrote through the symlink")

    # Mutation: drop the ownership check and a directory someone else made (and
    # so can write to whatever its mode says) is trusted. Another owner cannot be
    # created without root, so `stat` is shadowed to report one for `%u` only.
    def test_a_cache_directory_owned_by_someone_else_is_refused(self):
        bindir = self.tmp / "bin"
        bindir.mkdir()
        fake = bindir / "stat"
        fake.write_text('#!/bin/sh\n'
                        'case "$*" in *%u*) echo $(( $(id -u) + 1 )); exit 0;; esac\n'
                        'exec /usr/bin/stat "$@"\n')
        fake.chmod(0o755)
        script = self.script_with_hash(self.good_sha)
        run = self.run_script(script, self.good.as_uri(),
                              PATH=f"{bindir}:/usr/bin:/bin")
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertIn("not owned by you", run.stderr)

    # Mutation: drop the write-bit check and another local user can swap the zip.
    def test_a_group_writable_cache_directory_is_refused(self):
        self.cache.mkdir(parents=True)
        self.cache.chmod(0o770)
        script = self.script_with_hash(self.good_sha)
        run = self.run_script(script, self.good.as_uri())
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertIn("writable by group or others", run.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
