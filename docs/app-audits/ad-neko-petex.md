# Petex

## 基本信息
- Bundle ID: `ad.neko.petex`
- Team ID: **无** —— 产物 ad-hoc（linker-signed）签名，`TeamIdentifier=not set`
- 观测版本: `1.0.10`（short == build == tag）
- 自更新机制: **无**。包里有 `Squirrel.framework`（Electron 自带），但发布资产里没有
  `latest-mac.yml`，electron-updater 无 feed 可读
- 分发: 只有 GitHub Releases（`iebb/petex`）。无 Sparkle feed、无 Homebrew cask、
  Mac App Store 无上架（README 提到"Mac App Store build"，us 区搜 `Petex`/`Pedex` 0 条）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ad.neko.petex` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。仓库里没有 prerelease、没有 beta tag、没有第二条发布轨道。

## 更新检测
- 源: `iebb/petex` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.0.10` → `1.0.10` == 包的 short 与 build。同构，无陷阱。
- ⚠️ **patch 位是 commit height**：`scripts/version.cjs` 用 `git rev-list --count HEAD`
  覆写 `package.json` 的第三位，`build.yml` 的 release job 在**每次 push 到 master**
  时跑。所以版本号会跟着提交数一格一格涨，而不是按发布节奏涨；这不影响比较
  （仍是单调递增的三段数字），但解释了为什么会看到 1.0.7 → 1.0.9 → 1.0.10 这种密度。
- pattern 两端都锚，而且**锚是唯一的那道闸**。进 `resolve()` 的两条路都只看 GitHub 的
  `prerelease` **标志**（`/releases/latest` 按 GitHub 定义排除，列表兜底走 `stableOnly`），
  而 `scripts/release.cjs` 从不设这个标志——它对每次 push 到 master 的 tag 一律
  `gh release edit <tag> --draft=false --latest`。所以将来若出现 `v1.1.0-rc.1`，
  它会以「正式版」的身份到达；不锚的默认 pattern 会把它读成 `1.1.0`（一个没发布过的
  正式版）并推给所有装机。tag 字符串本身给不出提示：patch 位是 commit height，每个 tag
  看起来都像普通发布。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 feed，不具备 | 无 | 不能 |
| 证据 | 资产里无 `latest-mac.yml` | release 资产只有 dmg/zip/exe + SHA256SUMS | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回，无需 recipe）
- **但厂商不写发布说明**：release 由 `gh release create --generate-notes` 生成，而
  仓库全部是直推 master、没有 PR，于是 GitHub 生成出来的正文只有一行
  `**Full Changelog**: <compare 链接>`。
- 这一行走不出结构化条目：`GitHubMarkdownParser` 的三趟（严格 bullet / 宽松 bullet /
  散文）里，散文那趟对 `**full changelog` 开头的行是显式跳过的，于是 `items` 为空、
  `parse` 返回 nil。**加一条 `.gitHubReleases` 的 ChangelogRecipe 只会得到 0 条目**，
  所以没有加。
- 现状: 版本轨（`releaseHistory`）有版本号和日期。**面板并不会退到嵌入 release 页**
  ——`GitHubReleasesSource` 在 `structured == nil` 时把 body 原样放进 `releaseNotesHTML`，
  而工作台那条 if/else 阶梯先读 `releaseNotesHTML`、后读 `changelogURL`，所以面板渲染的
  是那一行 boilerplate 本身（GitHub 源按 markdown 渲染，出来是加粗的 "Full Changelog:"
  加一个链接）。厂商哪天开始写正文，同一条 inline 解析会自动接上，不需要改 recipe。

## 一键安装
- 状态: **不支持，且不是待办**
- 原因: 产物完全没有 Developer ID 签名。`build.yml` 显式设 `CSC_IDENTITY_AUTO_DISCOVERY: 'false'`，
  electron-builder 因此不签名，留下的是链接器的 ad-hoc 签名。
- 包验（2026-09-16，v1.0.10 arm64 dmg 挂载）：
  - `codesign -dv`: `Identifier=Electron`、`Signature=adhoc`、`TeamIdentifier=not set`、
    `Sealed Resources=none`、`flags=0x20002(adhoc,linker-signed)`
  - `codesign --verify --deep --strict`: 退 1，`code has no resources but signature
    indicates they must be present`
  - `spctl -a -t exec`: 退 1
- 对应到闸：`SignatureVerifier` 的 gate 2（deep/strict 有效性）和 gate 3（Team ID 与
  被替换的拷贝相同）各自单独就会拒。挂 `installAssetPattern` 只能造出一个必定失败的
  Update 按钮，所以留 nil，行为退到"给版本号 + 指向 releases 页"。

## 已知问题
- **资产名改过**：1.0.10 起是 `Petex-<v>-mac-<arch>.<ext>`，1.0.9 及更早是 `Pedex-…`
  （app 改名）。这对当前接入没有影响——没有 `installAssetPattern`，资产名不参与任何
  判断——但将来厂商若开始签名、要补一键时，pattern 不能跨过这条边界。
- `userData` 目录仍叫 `Pedex`（README 自述），与 bundle id 无关，不影响检测。

## 如何复验

```sh
# 版本与 tag 形状
gh api repos/iebb/petex/releases -q '.[] | "\(.tag_name)\t\(.name)\t\(.prerelease)"'
# 发布说明正文（当前每条都只有一行 Full Changelog）
gh api repos/iebb/petex/releases -q '.[] | .body'
# 签名：下 arm64 dmg，挂载后跑
codesign -dv --verbose=4 <mount>/Petex.app
codesign --verify --deep --strict <mount>/Petex.app; echo $?
spctl -a -t exec <mount>/Petex.app; echo $?
# 端到端
duo verify --only ad.neko.petex
```

## 历史与实测

### 2026-09-16 —— 接入（检测-only）

- releases 三条：`v1.0.10`（`Petex 1.0.10`）、`v1.0.9`、`v1.0.7`，全部
  `prerelease: false` / `draft: false`。仓库当时共 10 个提交，与 1.0.10 的 patch 位
  （commit height）一致。
- 下载 `Petex-1.0.10-mac-arm64.dmg`（125891514 字节），sha256
  `22b0b8b476b4add1cd513495340f1085c78f71cfaedd1bdd6fef8329194c6a1d`，与同一 release
  的 `SHA256SUMS.txt` 逐字相符。挂载后读 `Info.plist`：`CFBundleIdentifier=ad.neko.petex`、
  `CFBundleShortVersionString=1.0.10`、`CFBundleVersion=1.0.10`、
  `LSMinimumSystemVersion=13.0`；`lipo -archs` 为 `arm64`。
- 签名三条实测见「一键安装」一节（ad-hoc / 无 Team ID / `--deep --strict` 与 `spctl`
  各退 1）。主 app 和 `Contents/Frameworks/Petex Helper.app` 都是 `Signature=adhoc`、
  `TeamIdentifier=not set`。
- Homebrew：`formulae.brew.sh/api/{cask,formula}/{petex,pedex}.json` 四个都是 404。
- Mac App Store：`itunes.apple.com/search`（`entity=macSoftware`, `country=us`）搜
  `Petex` 0 条，搜 `Pedex` 8 条全是无关的包裹追踪 app。README 里那句"The Mac App Store
  build supports only user-selected pet files and folders"当时对应不上任何上架条目。
- 发布说明：三条 release 的 `body` 分别只有
  `**Full Changelog**: https://github.com/iebb/petex/compare/v1.0.9...v1.0.10`、
  `…/compare/v1.0.7...v1.0.9`、`…/commits/v1.0.7`。`v1.0.9...v1.0.10` 的 compare 只含
  一个提交，message 是 `Rename the app to Petex and preserve existing libraries`。
