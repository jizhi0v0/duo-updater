#!/usr/bin/env python3
"""Tests for homebrew_tap.bump, the cask rewrite publish-release.sh relies on."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from homebrew_tap import bump  # noqa: E402

OLD_SHA = "d7d9545ffab0a0658bc6b8dac7c14a183de99cb75cde7c30c615d092b8fd1195"
NEW_SHA = "0" * 63 + "1"

CASK = f'''cask "duoupdater" do
  version "0.5.5"
  sha256 "{OLD_SHA}"

  url "https://github.com/jizhi0v0/duo-updater/releases/download/v#{{version}}/DuoUpdater-#{{version}}-macos.zip"
  name "DuoUpdater"

  livecheck do
    url "https://updates.duoupdater.app/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :sequoia

  app "DuoUpdater.app"
end
'''


class Bump(unittest.TestCase):
    def test_rewrites_version_and_sha_and_nothing_else(self):
        out = bump(CASK, "0.5.6", NEW_SHA)
        self.assertIn('  version "0.5.6"\n', out)
        self.assertIn(f'  sha256 "{NEW_SHA}"\n', out)
        self.assertNotIn(OLD_SHA, out)
        self.assertEqual(
            out.replace("0.5.6", "0.5.5").replace(NEW_SHA, OLD_SHA), CASK)

    def test_same_release_is_a_no_op(self):
        self.assertEqual(bump(CASK, "0.5.5", OLD_SHA), CASK)

    def test_the_url_template_is_left_alone(self):
        out = bump(CASK, "0.5.6", NEW_SHA)
        self.assertIn("download/v#{version}/DuoUpdater-#{version}-macos.zip", out)

    def test_rejects_a_tag_or_a_bad_digest(self):
        with self.assertRaises(ValueError):
            bump(CASK, "v0.5.6", NEW_SHA)
        with self.assertRaises(ValueError):
            bump(CASK, "0.5.6", "sha256:" + NEW_SHA)

    def test_refuses_a_cask_it_cannot_read_unambiguously(self):
        with self.assertRaises(ValueError):
            bump(CASK.replace('  version "0.5.5"\n', ""), "0.5.6", NEW_SHA)
        doubled = CASK.replace('  sha256 "', f'  sha256 "{OLD_SHA}"\n  sha256 "', 1)
        with self.assertRaises(ValueError):
            bump(doubled, "0.5.6", NEW_SHA)


if __name__ == "__main__":
    unittest.main(verbosity=2)
