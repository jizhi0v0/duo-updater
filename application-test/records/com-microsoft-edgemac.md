# Microsoft Edge — channel verification record

Verified 2026-06-04 with `channel-verify` against the **official `.pkg` of each
channel**, expanded with `pkgutil --expand-full` and the payload `.app` inspected
(not installed). Independent bundle ids (Pattern A), each with its own VendorProbe
recipe reading the consumer update endpoint.

| Channel | real bundle id | pkg short ver | detect() | VendorProbe latest → verdict |
|---------|----------------|---------------|----------|------------------------------|
| stable  | `com.microsoft.edgemac`     | `144.0.3719.104` | stable ✓ | 148.0.3967.96 → UPDATE (pkg older than consumer) |
| beta    | `com.microsoft.edgemac.Beta`| `149.0.4022.8`   | beta ✓   | 149.0.4022.50 → UPDATE |
| dev     | `com.microsoft.edgemac.Dev` | `150.0.4041.0`   | dev ✓    | 150.0.4055.0 → UPDATE |

## Notes
- **Version-scheme check passed.** Edge's `CFBundleShortVersionString` and the recipe's
  reported version are the SAME 4-segment marketing form (`148.0.3967.96`), not a build
  number — so the `VersionComparator` from→to is apples-to-apples and there is **no
  phantom-build risk** (the Office/OneDrive trap does not apply here).
- The "UPDATE" verdicts are real and benign: the **enterprise** `.pkg` (from
  `edgeupdates.microsoft.com/api/products`) trails the **consumer** channel version the
  recipe reads, so a freshly-downloaded enterprise pkg legitimately has a newer consumer
  build available. Detection + probe both fire correctly.
- **Canary** (`com.microsoft.edgemac.Canary`) has NO recipe by design (README scope is
  stable/beta/dev) and is absent from the enterprise API; not verified, out of scope.
- Detection-only (Edge self-updates via Microsoft AutoUpdate / the one-click install
  path); channel reads cleanly from the `.Beta`/`.Dev` bundle-id suffix.

## Commands
```
# pkg → app, then:
swift run --package-path application-test channel-verify "…/Microsoft Edge.app"      --expect stable
swift run --package-path application-test channel-verify "…/Microsoft Edge Beta.app" --expect beta
swift run --package-path application-test channel-verify "…/Microsoft Edge Dev.app"  --expect dev
```
