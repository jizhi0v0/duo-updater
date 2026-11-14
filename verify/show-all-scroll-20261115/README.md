# Show all blank list regression — 2026-11-15

Product change: `66d98a2d` on base `1fab50e0`. Only `MenuContentView.swift` changes: switching Show all gives the scroll reader a new identity, resetting its scroll position and lazy row placement. The filter, search text, app results and failed-check scroll target remain owned by the outer view/model.

## Before

On the installed app, source grouping was active. Show all was off, the header counted 10 pending apps, but the app list contained no rows. Its scroll bar read `0.2978723404255319`.

- Scrolling to the top changed the scroll bar to 0 but did not restore the rows.
- Toggling Show all on and off at the top restored the 10 rows.
- Turning it on, scrolling down 4 pages, then turning it off reproduced the empty list; scroll bar read 1 and the accessibility list had no row children.
- [Before screenshot](before.png): native popover, 370 × 605 points, captured as seen with no occluding windows.

## After

`make install` exit 0; signed Release app installed and relaunched. The tested `MenuContentView.swift` exactly matches product commit `66d98a2d` (SHA-256 `0ed7907c310d1a7e0d551bd269e08ed5106883ea46f606dc3564a677c085f9d4`). Existing unrelated GitHub quota/settings changes in the user's main checkout were retained in that local build and are excluded from this PR.

Same app inventory, source grouping and live data:

| Show all scroll | Expanded scroll position | After turning it off |
|---|---|---|
| 1 page | `0.0203110802287669` | 10 app rows; scroll position 0 |
| 4 pages | `0.05223726716612825` | 10 app rows; scroll position 0 |
| 12 pages | `0.1508884550478144` | 10 app rows; scroll position 0 |

Each restored list began with Muse, AirCard and Rambox. No refresh or reopen was needed between toggles.

- Clicking the live failed-check banner enabled Show all and brought Waku's failed row into view; turning Show all off again restored all 10 pending rows.
- Searching for Rambox produced one app. The result and query survived toggling Show all both ways. Clearing the query restored the 10 pending apps at the top.
- [After screenshot](after.png): same 370 × 605-point native popover, Show all off, pending rows visible. Captured isolated because the computer-use pointer overlay occluded the as-seen capture; this verifies content, not glass material.
- `make test-app` exit 0: 365/365 declared tests executed; all 1,428 localization keys reachable. [Output](test-app.txt).
- `git diff --check` passed. No implementation-mirroring unit test added; the regression lives in SwiftUI's realized scroll layout and was verified in the running app.
- duo CLI: no changes; this is popover view state only.

Apple documents identity/state reset on [`View.id(_:)`](https://developer.apple.com/documentation/swiftui/view/id(_:)). The blank-list behavior and its recovery above are local observations, not a claim about all SwiftUI versions.
