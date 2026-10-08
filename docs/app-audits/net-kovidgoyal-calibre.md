# Calibre

审计 2026-10-08（重审；2026-06-04 那版只核对了下载包的 Team 与版本，没在新旧两个包上跑生产检测，没确认哪个源应答，没看 changelog 面板，没查 preview 轨，也没准备一键）。

## 基本信息
- Bundle ID: `net.kovidgoyal.calibre`（stable 与 preview 构建共用）
- Team ID: `NTY7FVCEKP` — Developer ID Application: Kovid Goyal（9.14.0、9.15.0、preview 9.15.101 三个真包相同，
  均 `Notarized Developer ID`，`Notarization Ticket=stapled`）
- 观测版本: stable `9.15.0`（`CFBundleShortVersionString` = `CFBundleVersion` = `9.15.0`），上一版 `9.14.0`；
  preview `9.15.101`。三个包都是 universal（`lipo -archs` = `x86_64 arm64`），`LSMinimumSystemVersion` `14.0.0`
- 自更新机制: **无**。只有启动后的「有新版本」提示：读 `https://code.calibre-ebook.com/latest`（失败退到
  `https://calibre-ebook.com/latest-version`），只在 `major.minor` 变大时提示，点了去官网下载页，不下载也不替换
  （settled from source: `src/calibre/gui2/update.py` on `master`）
- 开源: `kovidgoyal/calibre`
- Homebrew: cask `calibre`，`auto_updates` 未声明（= false），URL `https://download.calibre-ebook.com/<v>/calibre-<v>.dmg`；
  按 macOS 版本钉旧版（Ventura → 9.6.0，Big Sur / Monterey → 6.29.0，Sonoma 起跟最新）（2026-10-08 API）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（仅 brew 装的拷贝） | — | ○ | ○ |
| **preview**  | —       | —（没有 preview cask） | — | — | ○（目录列表，见下） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew**（`HomebrewCaskSource`），**只对 Caskroom 里有
`calibre` 的拷贝**。从官网 dmg 直接装的拷贝没有任何源应答：`channel-verify` 实测 `status unknown (no source answered)`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.kovidgoyal.calibre` | 共享 | — | Homebrew cask | ✓（brew）/ ○（直装） |
| preview | `net.kovidgoyal.calibre` | 共享 | 版本第三段 ≥ 100（`9.15.101`）——**推断**，见下 | 独立下载目录，无应用内开关 | 未接（`detect()` 报 stable） |

**preview 轨（实测 + 源码）:**

- `https://download.calibre-ebook.com/preview/` 是公开目录（2026-10-08）：`README.txt` 说这是自上个正式版以来的改动的
  预览构建，「typically released every Friday」；当时只有一组文件，`calibre-9.15.101.dmg`（351,217,329 B，
  28-Sep-2026）及 msi / txz / exe。
- 另有 `https://download.calibre-ebook.com/betas/`，当时只有一组 `calibre-9.9.105.*`（21-Jun-2026，介于 9.9 与 9.10 之间）。
  这个目录在 9.10 发布后没有清空，像是更早的、没再更新的入口（推断）。
- preview 真包: bundle id、Team、`LSMinimumSystemVersion` 与 stable 相同，版本 `9.15.101`；Info.plist 键集合与 stable 完全一样，
  没有任何渠道标记。`channel-verify` 报 `inferred stable`。
- 版本号规则来自源码：`master` 上 `src/calibre/constants.py` 是 `numeric_version = (9, 15, 101)`，即两次正式版之间 master
  的版本就是 `<上个正式版>.1NN`。「第三段 ≥ 100 = preview/beta」是从这一处源码和两个目录样本（`9.9.105`、`9.15.101`）
  得出的**推断**，没有找到厂商写明的规则。正式版的补丁号目前最大是 1（`9.3.1`、`9.2.1`）。
- 没有 Homebrew cask（2026-10-08 全量 cask 目录里只有 `calibre`），没有应用内切换。
- 未查: preview 目录是否保留旧构建（两次观测都只有一组文件）；preview 有没有自己的更新提示（源码里提示逻辑与 stable
  共用一份，只比 `major.minor`，**推断** preview 用户只会在下一个正式 minor 出来时被提示）。

**duo 今天对 preview 拷贝的行为（实测，Caskroom 注入，见「如何复验」）:** 一份 brew 装的 calibre 被 preview 覆盖后，
`HomebrewCaskSource` 报 `latest 9.15.0`、`up to date`（`9.15.101` > `9.15.0`），下一个正式版出来时会推正式版。也就是
「preview → 下一个 stable」，不会推下一个 preview，也不会降级，方向是对的。直装的 preview 拷贝同 stable 直装：unknown。

## 更新检测
- 源: `HomebrewCaskSource`（仅 brew 装的拷贝）
- 端点: formulae.brew.sh 的 `calibre` cask。厂商自己的版本端点（应用内提示读的）:
  - `https://code.calibre-ebook.com/latest`: 用系统 CA 验证 TLS 失败（`curl: (60) … unable to get local issuer certificate`），
    calibre 用自带的证书链去取（`get_https_resource_securely`），duo 不能直接用
  - `https://calibre-ebook.com/latest-version`: `200`，正文就是 `9.15.0`（6 字节，2026-10-08）
- 版本方案: 包里 `CFBundleShortVersionString` = `CFBundleVersion` = `9.15.0`；cask 版本 `9.15.0`；whats-new 页写 `9.15`
  （`.0` 省掉），`VersionComparator.compare("9.15", "9.15.0")` = 0（实测）
- GitHub Releases: `kovidgoyal/calibre` 的 release 只有最新一个带 dmg（`v9.15.0` 带 `calibre-9.15.0.dmg`，
  GitHub `digest` 为 `sha256:1b3a7451…6019`，与 cask 相同；`v9.14.0` 及更早 0 个资产）。官网 `https://calibre-ebook.com/dist/osx`
  302 到这个 GitHub 资产
- 直装拷贝要接检测，两条路都可行（未实现，见建议）：GitHub rule（`kovidgoyal/calibre`，dmg 带 digest）或 VendorProbe
  （`latest-version` 纯文本 + `download.calibre-ebook.com/{v}/calibre-{v}.dmg`）。两者都排在 `HomebrewCaskSource` 之后，
  brew 装的拷贝仍由 brew 应答

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 包里没有 `Sparkle.framework`；`update.py` 只提示、只开下载页 | 版本端点只回一个版本号；下载目录每版只有完整 dmg | — |

- 格式: —
- 阻塞项: —

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 请求带 `CALIBRE-VERSION` / `CALIBRE-OS` / `CALIBRE-INSTALL-UUID` / `CALIBRE-ICON-THEME` 头，服务端**能**按安装分桶；客户端只认一个版本号 | `code.calibre-ebook.com/latest` 没测（TLS 只认 calibre 自带的证书链）；退路 `latest-version` 无参数、只回一个版本 | 不需要（cask 与官网下载对所有人相同） |
| 按架构 / 按 OS 分轨 | 架构: 否（universal 单包）；OS: 包内 `LSMinimumSystemVersion` 14.0.0（9.14.0 / 9.15.0 / 9.15.101） | OS: 是，但只在 cask 里——cask 给 Ventura 钉 9.6.0、Big Sur / Monterey 钉 6.29.0；厂商端点不分 | `HomebrewCaskSource` 按本机 macOS 选 cask 分支 |
| 自更新器会不会和我们抢 | 否：只提示 | — | — |

## Changelog
- 来源: `ChangelogRecipe`（`https://calibre-ebook.com/whats-new`，服务端渲染，全部历史一页）
- 结构化: `channel-verify` 原文（9.14.0、9.15.0、preview 9.15.101 三个包相同）:
  `changelog pane  recipe changelog:net.kovidgoyal.calibre:-: 40 entries; newest 9.15: 19 items, headings []; first items ["A "Create your own adventure" writing ga", "E-book viewer: Highlights panel: Allow s", "Cover grid: Allow choosing which corner "]`
- 观测版本的条目都在: 前六条 `9.15, 9.14, 9.13, 9.12, 9.11, 9.10`（实测）；页上共 61 个 release 标题，recipe 取默认上限 40
- `headings []`: 页面每个版本分 `New features` / `Bug fixes` / `Improved news sources` / `New news sources` 四类（`<h3 class="category">`），
  recipe 只取 `<span class="title">`，所以两类正文合成一串、没有小标题，news sources 两类（裸 `<li>`）按设计丢掉。
  标题不在 items 里，不是「压平进正文」，是没取
- preview 没有条目（whats-new 只列正式版），preview 拷贝看到的是最新正式版的说明
- 跟随 channel: 否
- Recipe 状态: 已有，可用；可改进（加 `headingPattern`，见建议，**未验证**是否会留下空标题）

## 一键安装
- 状态: 仅 brew 装的拷贝（brew 路线，duo 跑 `brew install --cask --force calibre`）；直装拷贝没有检测，也就没有一键
- 端到端: **未跑**（本次审计不安装；由协调会话串行跑）。生产判断已在真包上实测（Caskroom 注入）：9.14.0 → `UPDATE → 9.15.0`，
  下载地址 `https://download.calibre-ebook.com/9.15.0/calibre-9.15.0.dmg`，`requiresManualInstaller false`
- 格式: dmg（universal）
- 校验: brew 自己校验 cask 的 sha256；duo 的 brew 路线不过 Team 闸（`InstallCoordinator` 的 `.homebrew` 分支直接交给 brew）。
  实测 9.15.0 dmg SHA-256 `1b3a7451…6019` = cask = GitHub `digest`；9.14.0 dmg `a2f82513…e3d4` = homebrew-cask `calibre 9.14.0`
  提交里的 sha256
- **读的是**: 人人可手动下载的 GA（cask 版本 = 官网下载 = `latest-version`，无分桶）
- Team: 9.14.0 / 9.15.0 / 9.15.101 同为 `NTY7FVCEKP`，`codesign --verify --deep --strict` 均通过，`spctl` `accepted`
- 嵌套: `Contents/ebook-viewer.app`（`com.calibre-ebook.ebook-viewer`）、其内 `Contents/ebook-edit.app`（`com.calibre-ebook.ebook-edit`）
  都是普通 app（无 `LSUIElement` / `LSBackgroundOnly`），用户可以单独开电子书阅读器 / 编辑器；`Contents/utils.app`
  （`com.calibre-ebook.utils`，`pdftohtml`）`LSBackgroundOnly`，转换时临时跑。没有 LoginItems / LaunchAgent。
  duo 的 brew 路线在启动 brew 前先拒绝「嵌套 app 还在跑」（`refuseWhileNestedAppRuns`），阅读器开着时应被拒（**推断**，没跑）
- cask 还把 `calibre-server`、`calibredb` 等 20 个命令行工具链进 brew 的 `bin`；`calibre-server` 可能被用户长期跑着，
  替换后它继续跑旧代码（推断）
- 阻塞: 直装拷贝无检测

## 已知问题
- 直装（官网 dmg / GitHub 资产）的拷贝 unknown：今天只有 brew 装的拷贝能检测
- preview 拷贝报 stable（无渠道标记，只有版本形状）
- changelog 没有分类小标题

## 建议下一步
1. 直装检测：`/fragile-recipe Calibre`，二选一——GitHub rule（`kovidgoyal/calibre`，资产 `calibre-{v}.dmg`，带 digest，
   只有最新 release 有资产）或 VendorProbe（`https://calibre-ebook.com/latest-version`，正文 `(\d+\.\d+\.\d+)`，
   install `https://download.calibre-ebook.com/{v}/calibre-{v}.dmg`）。注意 cask 的 OS 钉版：Sonoma 以下的 Mac 不能装
   9.7 起的包，rule/recipe 要带 `hostRequirement`（下限 14.0，由 `LSMinimumSystemVersion` 证）
2. preview 轨：如果要接，信号只有版本第三段 ≥ 100，先找到厂商对这条规则的明文说明再写进 `detect()`；端点是目录列表
   `download.calibre-ebook.com/preview/`。不接的话在 `CHANNEL_COVERAGE_TODO.md` 记为「同 id、版本形状可辨、未接」
3. changelog：试 `headingPattern: <h3 class="category">(.*?)</h3>`，先确认 news sources 两类不会留下空标题
4. 一键端到端（brew 路线）由协调会话跑

## 如何复验

2026-10-08。包从厂商目录直接下载，每个包放各自的空目录；`hdiutil attach -nobrowse -readonly` 挂载检查，不安装、不启动。

```bash
curl -sS -A "Mozilla/5.0" https://calibre-ebook.com/latest-version            # 9.15.0
curl -sS -A "Mozilla/5.0" https://download.calibre-ebook.com/preview/         # calibre-9.15.101.dmg 351217329
curl -sS -A "Mozilla/5.0" https://download.calibre-ebook.com/preview/README.txt
curl -fL --retry 5 -C - -o calibre-9.15.0.dmg  https://download.calibre-ebook.com/9.15.0/calibre-9.15.0.dmg
curl -fL --retry 5 -C - -o calibre-9.14.0.dmg  https://download.calibre-ebook.com/9.14.0/calibre-9.14.0.dmg
curl -fL --retry 5 -C - -o calibre-9.15.101.dmg https://download.calibre-ebook.com/preview/calibre-9.15.101.dmg
shasum -a 256 calibre-*.dmg
swift run --package-path application-test channel-verify calibre-9.14.0.dmg
```

| 包 | 大小 | SHA-256 | 对照 |
|---|---|---|---|
| `calibre-9.15.0.dmg` | 350,293,492 | `1b3a7451175b73ae2baa28fe1bc1c53ee34d65b489881e7ec02c20f9e0ff6019` | = cask = GitHub `digest` |
| `calibre-9.14.0.dmg` | 344,439,358 | `a2f825138645ea29d9f77a78c177216c0db855fa0c7b993a16ace230c04fe3d4` | = homebrew-cask `calibre 9.14.0` 提交 |
| `calibre-9.15.101.dmg`（preview） | 351,217,329 | `12c8e9255cbb3453478fe4f4c070168ab5d1f30206e72b1f07a857d2d4b664f4` | 大小 = 目录列表；厂商不发摘要 |

`channel-verify`（三个包结果相同，只有版本不同）:

```
  bundle id       net.kovidgoyal.calibre
  short version   9.14.0            (9.15.0 / 9.15.101)
  inferred        stable
  detected channel  → stable
    SUFeedURL       <none>
    winning source  <none>
    status          unknown (no source answered)
```

`channel-verify` 读的是真实 Caskroom，没有 `calibre` 时 Homebrew 不应答，所以上面是「直装拷贝」的结果。brew 装的拷贝
用一个临时测试量（跑完删掉）：真包 `AppScanner.readApp` → `HomebrewCaskSource(inventory: BrewLocalInventory(installedTokens: …))`
→ `UpdateChecker.check`，cask 目录是线上 formulae.brew.sh：

| 包 | 注入的 Caskroom | 应答源 | latest | 结论 |
|---|---|---|---|---|
| 9.14.0 | `calibre` | Homebrew（`calibre`） | 9.15.0 | `UPDATE → 9.15.0` |
| 9.15.0 | `calibre` | Homebrew | 9.15.0 | `up to date` |
| preview 9.15.101 | `calibre` | Homebrew | 9.15.0 | `up to date` |
| 9.14.0 | 只有别的 cask | 无 | — | `unknown` |

签名（三个包相同）: `Authority=Developer ID Application: Kovid Goyal (NTY7FVCEKP)`，`codesign --verify --deep --strict` OK，
`spctl -a -vv` → `accepted` / `source=Notarized Developer ID`。

## 审计记录
- 2026-06-04: 首版，只从 cask 下载包读了 Team `NTY7FVCEKP` 与版本 9.9.0。
- 2026-10-08: 重审。旧版写的「direct installs without Sparkle remain out of scope」不是厂商限制，是没接：GitHub 与
  `latest-version` 两条路都现成；旧版没提 preview 轨（`CHANNEL_COVERAGE_TODO.md` 也把 Calibre 列在「只有 stable」里，
  不对）；旧版「一键 Homebrew-managed only」没说明 brew 路线不过 Team 闸、也没看嵌套的阅读器 / 编辑器。
