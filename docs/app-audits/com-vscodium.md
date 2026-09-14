# VSCodium

**这不是审计**：family `com-vscodium`（`Recipes/com-vscodium.swift`）里 stable
`com.vscodium` 的覆盖情况没有审过。同一个 family 的另一个 app——VSCodium Insiders
`com.vscodium.VSCodiumInsiders`——审过，见 [com-vscodium-VSCodiumInsiders.md](com-vscodium-VSCodiumInsiders.md)。

这份文件存在，是因为 recipe 注释里迁出的历史按 family 落地：`Recipes/com-vscodium.swift`
的历史回链必须指向 `docs/app-audits/com-vscodium.md`（`scripts/check_app_audits.py` 按 family
文件名检查），两个 app 的历史都进这里。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-vscodium.swift — VSCodium Insiders GitHubReleaseRule（`detect` 为什么判成 `.preview`）

转引自 recipe 注释，未复测。整段原文；代码里只改了「(confirmed below)」这个指向，见下面的更正。

Detection needs no `ReleaseChannel` change, but not for the reason it
might look like: the bundle id has no `.insiders`/`-insiders` SUFFIX
(it's the single camelCase component "VSCodiumInsiders", no separator
before "Insiders"), so `detect`'s bundle-id-suffix step does not fire.
What actually resolves it to `.preview` is the display name step: the
installed app's CFBundleName/CFBundleDisplayName is "VSCodium -
Insiders" (confirmed below), and "Insiders" is a standalone word there.
`ChannelGuardTests.vscodiumInsidersDisplayNameSignalsPreview` pins our
half of this against `ReleaseChannel.detect`. It cannot pin the VENDOR's
half: the display name is their string, and if VSCodium ever glues it
("VSCodiumInsiders", the shape the bundle id already has) `detect`
returns `.stable`, the channel gate skips this rule, and the app goes
quiet with the test still green. That is the failure to watch for here.

更正 2026-09-14：「confirmed below」指向下一组那段一键核对，而那段记的是 bundle id、两个版本字段、Team 与 spctl，没有记 `CFBundleName` / `CFBundleDisplayName`；那段又已搬到这里。代码里改指 [com-vscodium-VSCodiumInsiders.md](com-vscodium-VSCodiumInsiders.md)，那份审计的第 9 行与第 54 行记着 `VSCodium - Insiders`。

### Recipes/com-vscodium.swift — VSCodium Insiders GitHubReleaseRule（一键 zip 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（arm64 zip 里是 com.vscodium.VSCodiumInsiders、两个版本字段都带 `-insider`、Team VC39D2VNQ7 且装订了公证票据、spctl 接受，checked 2026-08-27），被下载的具体文件名、版本号和命令输出搬到这里。

One-click: verified 2026-08-27 by downloading the real
VSCodium-darwin-arm64-1.126.04518-insider.zip and reading the
extracted app directly — CFBundleIdentifier
com.vscodium.VSCodiumInsiders, CFBundleShortVersionString/
CFBundleVersion both "1.126.04518-insider", `codesign -dv` shows
TeamIdentifier VC39D2VNQ7 (same team as stable) with a stapled
notarization ticket, and `spctl -a --type execute` returns "accepted,
source=Notarized Developer ID" — passes VendorInstaller's same-Team
gate.

### Recipes/com-vscodium.swift — `githubChannelProofs`（Insiders 为什么锚在 tag 段）

转引自 recipe 注释，未复测。整段原文；代码里只把「all 57 of them」换成了「every one of them」。原句没写日期，引入它的提交是 `3d919e36`（2026-08-28）。

Anchored to the tag segment on purpose. A bare `-insider` would be
satisfied by `VSCodium/vscodium-insiders` in the path of EVERY url this
rule can ever resolve, which is the same fact the stable branch of
`crossChannelArtifact(rule:remote:)` in `ChannelArtifactProof.swift` refuses to check on — read
there it prevents a false accusation, read here it would have been a
permanent false acquittal, and the proof could not have failed for any
input. Live releases could not show this: every real tag in that repo
carries `-insider` too, so the loose pattern and the anchored one agree
on all 57 of them and disagree only on the artifact this exists to
catch. Caught in adversarial review of #101, not by measurement.
