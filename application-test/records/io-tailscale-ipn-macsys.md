# Tailscale — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/Tailscale.app`). Single **stable** channel via VendorProbe.

| Channel | real bundle id | real short ver (build) | detect() | VendorProbe → verdict |
|---------|----------------|------------------------|----------|------------------------|
| stable  | `io.tailscale.ipn.macsys` | `1.98.5` (`101.98.5`) | stable ✓ | 1.98.5 = installed, up to date |

## Notes
- The `macsys` bundle id is the standalone (non-MAS) build; VendorProbe answered with
  1.98.5 = installed → no phantom update.
- `unstable` track is not covered (no recipe); out of scope for this verification.

## Command
```
swift run --package-path application-test channel-verify --scan io.tailscale.ipn.macsys --expect stable
```
