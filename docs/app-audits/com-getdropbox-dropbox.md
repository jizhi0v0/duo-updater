# Dropbox

> 首次成文 2026-09-14，起因是一键安装在 Apple silicon 上拿到的是 x86_64-only 的 dmg。
> **范围只到版本检测与一键安装**：changelog、beta 轨（`dropbox@beta`）没有审，见「未审」。

## 基本信息
- Bundle ID: `com.getdropbox.dropbox`
- Team ID: `G7HH3F8CAK`（Developer ID Application: Dropbox, Inc.）
- 观测版本（2026-09-14 两个 dmg 挂载核对）: short `268.4.4124`，build `268.4.4124`（三段式，同构）
- 自更新机制: 自带（bundle 里没有 `SUFeedURL`、没有 `Contents/Resources/app-update.yml`，是 Electron 壳）；
  Homebrew cask 标 `auto_updates true`
- 架构: **按架构分包**，没有 universal 包——见下「一键安装」
- `LSMinimumSystemVersion`: `10.13`（两个包相同）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不作答  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | — | ✗（auto_updates）| 未查 | — | ✓ 一键 |

当前生效源: **VendorProbe**（`Recipes/com-getdropbox-dropbox.swift`）。

## 更新检测
- 端点: `https://www.dropbox.com/download?plat=mac&full=1&arch=arm64`，不跟随重定向，读 302 的 `Location`
  文件名（`.redirectFilename`）。
- 2026-09-14 no-follow HEAD：
  - 带 `&arch=arm64` → `…/dbx-releng/client/Dropbox%20268.4.4124.arm64.dmg`（387,752,941 B）
  - 不带 → `…/dbx-releng/client/Dropbox%20268.4.4124.dmg`（398,329,648 B）
- 版本 pattern **要求** `.arm64.dmg` 结尾：Dropbox 哪天不再认 `arch=arm64`、退回 Intel 文件名时，
  检测直接 `versionPatternNoMatch`，夜间扫描会报出来，而不是给出一个装不上的更新。

## 一键安装
- **状态: ✓（2026-09-14 修复）。修复前在 Apple silicon 上是坏的，且 `duo verify` 看不见。**
- 修复前 install 源是不带 `arch` 的同一个链接，拿到的 `Dropbox%20<ver>.dmg` 是 **x86_64-only**。
  2026-09-14 两个包都下载、只读挂载核对：

  | | `Dropbox%20268.4.4124.dmg` | `Dropbox%20268.4.4124.arm64.dmg` |
  |---|---|---|
  | sha256 | `6ae7f7efce0b1d163ab73f93739c4ff878ae04ba7387189e94ace9235d238851` | `c07371457ba5c23a72b9a6bf101286886ef7db876d34c81daedc5be8688eafaa` |
  | Homebrew cask 里的标注 | `intel:` | `arm:` |
  | `lipo -archs Contents/MacOS/Dropbox` | **`x86_64`** | **`arm64`** |
  | `CFBundleIdentifier` / 版本 | `com.getdropbox.dropbox` / 268.4.4124 | 同左 |
  | `codesign` TeamIdentifier | `G7HH3F8CAK` | 同左 |
  | `spctl -a -vv --type execute` | accepted, Notarized Developer ID | 同左 |
  | 卷名 | `Dropbox Offline Installer` | 同左 |

  卷名叫 "Offline Installer"，里面装的是真正的 `Dropbox.app`，不是 stub 安装器。
- **生产闸门在真包上跑过**（临时测试，跑完即删，未提交），`SignatureVerifier.verifyInstallArtifact`，
  arm64 宿主、`HostArch.canRunIntelBuilds == true`：
  ```
  archs intel=[16777223] arm=[16777228]
  OLD (x86 dmg over arm64 copy): REFUSED architectureDowngrade(installed: "arm64", downloaded: "x86_64")
  OLD, no Rosetta:               REFUSED unrunnableArchitecture(built: "x86_64", host: "arm64")
  NEW (arm64 dmg over x86 copy): PASS
  ```
  "已装副本"用的是另一个包里的 bundle，不是自己比自己，所以 Team / bundle id 闸是真的比对过的。
- 修复前各情形（读 `SignatureVerifier.verifyInstallArtifact` 得出，前两行上面实测过）：
  - 已装 arm64（或 universal）+ 有 Rosetta → 闸 5b `architectureDowngrade`，**下载完才拒**；
  - 没有 Rosetta（未安装，或 macOS 28 起）→ 闸 5 `unrunnableArchitecture`；
  - 已装的是 x86_64-only 副本 + 有 Rosetta → **不拒**，装上 Intel 版继续转译运行。
- 修复：probe 与 install 两个 URL 都加 `&arch=arm64`（DuoUpdater 本身 arm64-only，`App/project.yml`
  `ARCHS: arm64`），两者是同一个 URL——安装器不校验下载到的版本是否等于检测到的版本，所以检测读的必须
  就是要下载的那个文件。
- 为什么以前没被抓到：`duo verify` 只对 install URL 做可达性 HEAD，不看它是什么架构；
  `vendorDownloadPassesSignatureGate` 只跑候选名单里的 app、默认关闭，且只到闸 3，不含 Dropbox。
- 回归测试: `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/DropboxProbeRecipeTests.swift`，从
  `VendorProbeRegistry` 读这条 recipe：两个 URL 相同且带 `arch=arm64`；pattern 读得出 arm64 文件名、
  读不出 Intel 文件名（fixture 是上面 2026-09-14 的两个真实 `Location`）。

## 未审
- Changelog（`https://www.dropbox.com/release_notes`，recipe 只挂了链接）。
- beta 轨：Homebrew 有 `dropbox@beta` cask（2026-09-14：`270.3.3261`，url 带 `arch=arm64`），
  没查它的 bundle id 是否独立、我们是否需要接。
- Mac App Store 是否有同 bundle id 的副本。

## 如何复验
```
# 两个 no-follow HEAD，比对 Location 文件名：
curl -sI 'https://www.dropbox.com/download?plat=mac&full=1&arch=arm64' | grep -i '^location'
curl -sI 'https://www.dropbox.com/download?plat=mac&full=1' | grep -i '^location'
# Homebrew：formulae.brew.sh/api/cask/dropbox.json 的 url（arm）与 variations.*.url（intel）+ sha256
# 下载两个 dmg，shasum -a 256 比对 cask；hdiutil attach -readonly 后：
#   lipo -archs Dropbox.app/Contents/MacOS/Dropbox → x86_64 / arm64
#   codesign -dvv → TeamIdentifier=G7HH3F8CAK；spctl -a -vv --type execute → Notarized Developer ID
# swift test --package-path DuoUpdaterCore --filter DropboxProbeRecipeTests
# duo verify --only dropbox
```

## 历史与实测

### Recipes/com-getdropbox-dropbox.swift — stable
转引自 recipe 注释，未复测。（2026-09-14 下载的是 268.4.4124，结论见上「一键安装」；这段说的 264.4.3385
当时装的是哪个架构的包，注释里没有记录。）

One-click verified 2026-08-09 on 264.4.3385: the image is labelled
"Dropbox Offline Installer" but holds the real `Dropbox.app` —
com.getdropbox.dropbox, Team G7HH3F8CAK, spctl "Notarized Developer ID",
version matching the redirect filename. (Worth stating, since the sibling
1Password download turned out to be a stub installer, not the app.)
