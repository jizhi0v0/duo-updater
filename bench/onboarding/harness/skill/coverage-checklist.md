### Coverage checklist — the groups of copies to settle first

Past onboardings passed `make test`, detected today's release, and still left
users out. The misses were whole groups of installed copies nobody listed, not
wrong code. List these groups before Phase 0, and carry the list into the
audit doc: each group is either covered by a rule or recorded as a gap with a
reason that holds. "Not checked" is not a recorded gap.

- **Every bundle id a user may still have.** Read the Info.plist of older
  releases, not only the newest two: the id the app shipped under before a
  rename, and other editions or apps built from the same repo, each under its
  own id.
- **Every release track.** Prereleases, betas or nightlies the vendor
  publishes, on their own bundle id or sharing the stable one. Find out how the
  app itself tells them apart (a plist value, the version string, the feed it
  declares) so each copy is served its own track.
- **Every version range.** Older copies may lack the update feed newer ones
  declare (a feed inside new bundles never reaches old copies), or be signed by
  a different team.
- **Our host floor, not the vendor's.** DuoUpdater only runs on the hosts
  `App/project.yml` allows (`ARCHS`, the macOS deployment target). A vendor
  minimum at or below that floor, or a problem only an Intel Mac would have, is
  no reason to hold a rule back.
- **One-click is best-effort.** The install-time gate (seal, bundle id, Team
  ID) refuses copies it can't vouch for. Wire one-click for the copies it
  serves and record which ones it refuses; don't drop it for everyone.
  Ad-hoc signing alone doesn't make an app detection-only: `installTrust:
  .publishedDigestOnly` covers it when the conditions on `InstallTrust` hold.
- **The version pattern must read the next release.** Run it on every
  non-prerelease tag the vendor has published (two-part ones too), on the next
  major version, and on an rc/beta tag the vendor forgets to flag. Anchor it
  (`^…$`) so `v1.3.0-rc.1` isn't read as `1.3.0`, and don't pin the major
  version to keep a sibling product out; filter by asset name instead.

