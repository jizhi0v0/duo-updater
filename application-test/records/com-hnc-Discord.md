# Discord — channel verification record

Verified 2026-06-04 with `channel-verify` against the **official DMGs of all three
channels**, mounted read-only (not installed). Independent bundle ids (Pattern A),
each with its own VendorProbe recipe.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `com.hnc.Discord`       | `0.0.393`  | stable ✓ | 0.0.393 = dmg, up to date |
| ptb     | `com.hnc.DiscordPTB`    | `0.0.237`  | ptb ✓    | 0.0.237 = dmg, up to date |
| canary  | `com.hnc.DiscordCanary` | `0.0.1136` | canary ✓ | 0.0.1136 = dmg, up to date |

## Notes
- Channel is fully observable from the bundle id suffix (`PTB`/`Canary`); no
  preference reading needed.
- All three VendorProbe recipes answered with the dmg's own version → no phantom
  update. Detection-only (Discord self-updates via its host updater).

## Commands
```
swift run --package-path application-test channel-verify /tmp/discord-stable.dmg --expect stable
swift run --package-path application-test channel-verify /tmp/discord-ptb.dmg    --expect ptb
swift run --package-path application-test channel-verify /tmp/discord-canary.dmg --expect canary
```
