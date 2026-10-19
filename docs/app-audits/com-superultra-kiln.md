# Kiln

## 基本信息
- Bundle ID: `com.superultra.kiln`
- Team ID: `XDP69BYUP9`（Developer ID Application: SuperUltra, Inc.），`spctl` 为 Notarized Developer ID，hardened runtime
- 观测版本: 0.4.3（`CFBundleShortVersionString` = `CFBundleVersion` = 0.4.3），取自 `https://kiln-builds.superwhisper.com/latest/Kiln-mac.zip`（2026-10-18，6005307 字节，`last-modified: Sun, 18 Oct 2026 05:49:40 GMT`）
- 自更新机制: 无
- 架构 / OS: universal（x86_64 + arm64）；`LSMinimumSystemVersion` 11.0
- 产品: Superwhisper 团队做的 ISO 写 U 盘工具（产品页 `https://superwhisper.com/kiln`）。不开源：GitHub 搜不到仓库

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（`Recipes/com-superultra-kiln.swift`）。

- Sparkle —：包里只有一个 Rust 可执行文件，没有 `Frameworks/`，没有 `SUFeedURL`。
- Homebrew —：`brew search --cask kiln` 无结果（2026-10-18）。
- MAS / GitHub —：都没有。

## 为什么判定没有自更新器
- 静态（arm64 切片）：`superwhisper` 只出现 1 次，是菜单的「Kiln Website」链接 `https://superwhisper.com/kiln`。`kiln-builds`、`Kiln-mac`、`version.json` 都是 0 次。`Update` / `update` 的命中都不是更新逻辑：rustls 的 TLS KeyUpdate、`SecItemUpdate`、提示文案「Update macOS, then try again」、UI 框架的 entity update。`/api/` 是微软 Windows ISO 下载接口，`latest/` 是 rustls 文档链接。菜单只有 About / Hide / Quit / 编辑 / Bring All to Front / Kiln Website，没有检查更新；`Check for`、`new version`、`is available` 都是 0 次。
- 运行时（2026-10-18，启动 0.4.3 约 30 s，经本地代理看到的请求）：fedoraproject.org、download/dl.fedoraproject.org、releases.ubuntu.com、nixos.org / channels / releases.nixos.org、cachyos.org / cdn77.cachyos.org、omarchy.org / iso.omarchy.org、steamdeck-images.steamos.cloud、store.steampowered.com、downloads.raspberrypi.com、geo.mirror.pkgbuild.com、www.microsoft.com、api.github.com 以及一个镜像站。全是去查各发行版最新 ISO，没有访问 superwhisper.com 或 kiln-builds.superwhisper.com。

所以用户只能自己回产品页重新下载。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.superultra.kiln` | 独立 | — | — | ✓ |

产品页只发一个版本，没有 beta 或 nightly。

## 更新检测
- 源: `VendorProbeSource`
- 端点: `https://superwhisper.com/kiln`（Next.js 页面，Vercel，`cache-control: public, max-age=0, must-revalidate`）
- 版本: 服务端渲染的下载行 `<p class="kiln-meta">v<!-- -->0.4.3<!-- --> · <!-- -->6.0 MB…`。pattern `class="kiln-meta">v(?:<!-- -->)?([0-9]+(?:\.[0-9]+)+)<`，在真实页面上读出 `0.4.3`。这个值是页面打包代码里的常量（`page-<hash>.js` 中 `w={version:"0.4.3",mac:{url:"…/latest/Kiln-mac.zip",size:"6.0 MB"},…}`），和下载包大小写在一起，所以厂商发版时会改。版本号 = `CFBundleShortVersionString` = `CFBundleVersion`，不需要 `versionIsBuild`。
- 注意事项: 页面版本和 `latest/Kiln-mac.zip` 是两处分开维护的（见「已知问题」）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | 无更新器（见上） | 下载桶只有 `latest/` 整包，根目录与 `latest/` 列目录均 404 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | 不适用 |
| 证据 | 无更新器 | 启动后 `~/Library/Caches/kiln/` 只有一个 11 字节的 `microsoft-declined` 文件 | — |

## Changelog
- 来源: 无。产品页没有更新说明，`superwhisper.com/changelog` 只写 Superwhisper 本身（不含 Kiln），`superwhisper.com/kiln/changelog` 404，sitemap 里只有 `/kiln` 一页。
- 结构化: ✗，厂商不发布更新说明。
- 跟随 channel: 不适用
- Recipe 状态: 不需要（没有来源）

## 一键安装
- 状态: 支持
- 端到端（2026-10-18）:
  - 第一轮（未运行）：厂商不提供旧版下载，「上一版」用 0.4.3 包改了 `Info.plist` 的版本号（0.4.2）代替，Team ID 不变。`duo check Kiln` → `0.4.2 → 0.4.3 [Vendor, in-place]`；`duo install Kiln --yes --json` → `outcome: installed`，`route: vendor`，`bytesDownloaded: 6005307`，8 s。之后为 0.4.3，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，Team `XDP69BYUP9`，`diff -r --no-dereference` 与厂商包一致。
  - 第二轮（运行中）没跑：改过 `Info.plist` 的副本封印已破，macOS 拒绝启动（launchd `Code=163`），厂商又没有能启动的旧版签名包。app 没有自更新器，也就没有自更新器碰撞的问题。原装 0.4.3 正常启动，并已用它取得上面的运行时证据。
- 格式: zip（包根就是 `Kiln.app`）
- 校验: 页面不发摘要，只有 Team ID 闸。
- **读的是**: 人人可手动下载的 GA。安装地址就是产品页「Download for Mac」按钮的链接。
- 嵌套: 无
- 阻塞: 无

## 已知问题
- **页面版本与 zip 分开维护。** 页面先改、zip 后传时，一键会下载到和已装相同的旧包：Team ID 闸能过，安装照常完成，但这一行在页面和 zip 对齐之前会一直显示有更新。zip 先传、页面后改时，只是检测晚一点。两种情况都是厂商一侧短暂不同步；2026-10-18 两边都是 0.4.3。
- **HTML 抓取。** 页面改版、类名 `kiln-meta` 变了就读不到；`duo verify` 会报出来。

## 如何复验

```sh
curl -sSL -A 'Mozilla/5.0' https://superwhisper.com/kiln | grep -oE 'class="kiln-meta">v(<!-- -->)?[0-9.]+'
curl -sSL -A 'Mozilla/5.0' -o Kiln-mac.zip https://kiln-builds.superwhisper.com/latest/Kiln-mac.zip
ditto -x -k Kiln-mac.zip x
plutil -p x/Kiln.app/Contents/Info.plist | grep -E 'Identifier|Version'
codesign -dv x/Kiln.app 2>&1 | grep Team
swift run --package-path application-test feed-discover x/Kiln.app
```

2026-10-18：feed-discover `no Sparkle, no electron-builder update config and no MyGo feed`；channel-verify（已装 0.4.3）`VendorProbe ✓ recipe answered for channel 'stable'`、`winning source Vendor`、`latest 0.4.3`、`changelog pane none`、`status up to date`；页面 `0.4.3`；zip 内 `com.superultra.kiln` 0.4.3 (0.4.3)，Team `XDP69BYUP9`，`spctl` Notarized Developer ID，universal。

## 建议下一步
1. 厂商若开始发更新说明或版本清单，换成读那个。
