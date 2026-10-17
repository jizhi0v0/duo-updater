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

### stable 改读 releases-list、按 build 比（2026-10-17，#1371）

上面「一键接上 sha256」里 stable 读 `developer.android.com/studio` 下载表那段已被取代：stable recipe 现在和 Canary / Beta 读同一个 `jb.gg/android-studio-releases-list.json`，channel 取 `Release|Patch`，`versionIsBuild`，`entryStartPattern` 选 build 最高的 item，dmg 和 `checksum` 都取自该 item 的 arm64 dmg。

原因（#1371，用户报「2026.2 → 2026.2.1 装完还是 2026.2」）：stable 包的 `CFBundleShortVersionString` 只到 YEAR.MAJOR。本机实测（2026-10-17）：一份官网下载的 2025.2.3，`CFBundleShortVersionString` = `2025.2`，`CFBundleVersion` = `AI-252.28238.7.2523.14688667`，与 feed 里 `2025.2.3.9` 那条的 `build` 逐字相同；`product-info.json` 的 `dataDirectoryName` 是 `AndroidStudio2025.2.3`。旧 recipe 从下载页读出 `2026.2.1` 去比 `2026.2`，于是已经是 2026.2.1 的副本永远被报有更新，重装同一个 build 后 bytes 不变，触发「install applied nothing」。feed 里 2026.2 没有 `.0` stable，第一个就是 `2026.2.1`（Rabbit 1），所以报 `2026.2` 的 stable 就是 2026.2.1（推断，用户机器的 plist 没看到）。

顺带：`Patch`（如 `2026.1.4 Patch 1`，`…-quail4-patch1-mac_arm.dmg`）与它的 Release 同一 marketing version，旧 recipe 看不到；现在按 build 能看到。feed 统计（2026-10-17）：Canary 382 / Beta 102 / RC 82 / Release 67 / Patch 48 / Preview 4；Toolbox 里显示的 `Nightly` 不在这个 feed 里。

真机（2026-10-17，`duo` CLI，一份临时手装、Toolbox 不管的副本）：官方 `2026.1.4 Patch 1` dmg（sha256 与 feed 一致，plist `2026.1` / `AI-261.26222.65.2614.16379836`）→ `duo check` 报 `2026.1 → 2026.2.1 [Vendor, in-place]` → `duo install` 下 1,507,934,811 B、`applied: true` → 盘上 `2026.2` / `AI-262.9437.185.2621.16467767`。改前的 `duo` 对这份盘上状态仍报 `hasUpdate: true, latestVersion 2026.2.1`（即 #1371）；改后报 `up-to-date`，`latestBuild` 与 `installedBuild` 相同。另下载核对了 `2026.2.2 Canary 5` 与 `2026.2.1 RC 2` 的 arm64 dmg：sha256 都等于 feed，plist 都是 `2026.2`，`CFBundleVersion` 都与 feed 的 `build` 逐字相同。RC dmg 里的 app 叫 `Android Studio.app`（Canary 叫 `Android Studio Preview.app`），手装的 RC 按文件名会被认成 stable。
