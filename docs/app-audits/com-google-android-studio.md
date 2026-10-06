# Android Studio

**这不是审计**：family `com-google-android-studio`（`Recipes/com-google-android-studio.swift`）里 Android Studio `com.google.android.studio`（stable 与 Canary/Beta 预览共用这个 bundle id）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-android-studio.swift — Canary / Beta VendorProbe（releases-list JSON）

转引自 recipe 注释，未复测。

With two feature trains open at once, a newer
train's Canary can publish AFTER an older train's RC — 2026-08-27 had
`2026.1.4 RC 2` at item [0] and `2026.2.1 Canary 2`, the actually-newer
build, at item [1] — so plain first-match on the channel set landed on
the older train's RC.

### Recipes/com-google-android-studio.swift — `channelProofs`（Canary / Beta 的 artifact marker）

转引自 recipe 注释，未复测。这句写 2026-08-26，上一组那句写 2026-08-27，两处原文照录。两句都由提交 `57e9b6ef`（2026-08-27 11:09 +0800）引入，它的提交信息写的是「on 2026-08-27 2026.1.4 RC 2 (older 261 train) sat …」，与第一组的日期一致；这一组的 2026-08-26 是从它替换掉的旧 `ChannelArtifactProof.swift` 注释里沿用下来的（`7e7fe6fc`，2026-08-26，原话「exactly what the feed served on 2026-08-26」）。所以 08-27 是那次提交时的观测，08-26 是前一天那条旧注释的观测；两天的 feed 是否一样没有记录。

(It is NOT
legitimate merely because the RC was the most recently PUBLISHED item —
the feed is ordered by publish date, not by version, which is what made
the canary recipe land on `2026.1.4 RC 2` over the already-published,
already-newer `2026.2.1 Canary 2` on 2026-08-26; see issue #76 and
`VendorProbeRecipe.entryStartPattern`, which now resolves that correctly.)

### Recipes/com-google-android-studio.swift — 一键接上 sha256（2026-10-07）

三个 recipe（stable / Canary / Beta）的一键下载都先对官方公布的 SHA-256（hex）核对，再走 Team-ID 闸。下载的都是 `mac_arm.dmg`，摘要也只取 arm64 那份。

- stable：`developer.android.com/studio` 的下载表（表头 `Android Studio package / Size / SHA-256 checksum`）里 `mac_arm.dmg` 那一行。表格只写文件名、不写 URL，所以是按「同一页唯一的 arm64 dmg」配对；不能用反向引用把两个文件名绑死，因为引擎会把所有捕获组用 `.` 拼进摘要（试过，`expectedSHA256` 变成 `<hex>.android-studio-rabbit1-mac_arm.dmg`）。
- Canary / Beta：`jb.gg/android-studio-releases-list.json` 每个 item 的 `download` 列六个平台的文件，各带 `checksum`。`entryStartPattern` 选出的那个 item 里，取 `link` 是第一个 arm64 dmg 的对象的 `checksum`，与键顺序无关；该对象没有 `checksum` 时匹配不到，不会拿 Intel `-mac.dmg` 或别的 item 的。

实测（2026-10-07）：stable 页是 2026.2.1（`install/2026.2.1.8/android-studio-rabbit1-mac_arm.dmg`），表里 arm64 行 `16d4a0f8…ef54`，与 feed 里同一文件的 `checksum` 相同；Canary 选中 `2026.2.2 Canary 3`（`…canary3-mac_arm.dmg`，`67a98376…73c1`），Beta 选中 `2026.2.1 RC 2`（`…rc2-mac_arm.dmg`，`8fb71c27…76ca`）。三个 dmg（1,507,934,811 / 1,496,596,693 / 1,507,994,090 B）下载后 `shasum -a 256` 都等于各自摘要；临时 Swift 测试经生产 `VendorProbeSource` 跑 recipe，`expectedSHA256` 即上述值，`VendorInstaller.verifySHA256` 对真文件通过、翻转一个字节后抛 `checksumMismatch`。没有跑 `duo install`。
