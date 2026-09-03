# Notion

## 基本信息
- Bundle ID: `notion.id`
- Team ID: `LBQJ96FQ8D`
- 观测版本: 7.31.3（universal，`x86_64 arm64`）
- 自更新机制: Electron + electron-updater（`Contents/Resources/app-update.yml`，`channel: latest`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|--------------|---------|----------|-----|--------|-------------|----------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           | ✗(见下)   |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**

## 三个产物，版本互不同步 —— 这是这份审计的重点

Notion 同时维护三条互不同步的发布面。三者都真实、都由 Notion 自己发布，但它们**不是同一条轨的不同架构**：

| 面 | 端点 | 产物 | 谁在读 |
|---|---|---|---|
| 官网下载 | `www.notion.so/desktop/mac/download` 307 | `Notion-<ver>-universal.dmg` | **我们的 VendorProbe 配方** |
| 默认 manifest | `desktop-release.notion-static.com/latest-mac.yml` | `Notion-<ver>.zip` —— **纯 x86_64** | `channel: latest` 的构建 |
| arm64 轨 | `desktop-release.notion-static.com/arm64-mac.yml` | `Notion-arm64-<ver>.zip` | **`channel: arm64` 的构建** |

2026-09-01 实测的一次错开（四天、一个 minor）：

```
latest-mac.yml   version: 7.31.3   path: Notion-7.31.3.zip         releaseDate 2026-08-27T01:59:39Z
arm64-mac.yml    version: 7.32.0   path: Notion-arm64-7.32.0.zip   releaseDate 2026-08-31T20:30:08Z
官网 307         →  Notion-7.31.3-universal.dmg
```

### `arm64-mac.yml` 是另一条轨，不是另一个架构

两条硬证据：

1. **electron-updater 在 macOS 上不按架构选 manifest。** `Provider.getChannelFilePrefix()` 只对 linux 追加 `-${arch}`（且仅当 arch ≠ x64）；对 darwin 返回 `-mac`。架构选择发生在 manifest **内部**——`MacUpdater.ts` 判断 `process.arch === "arm64"` 后从 `files:` 列表里挑 arm64 条目。所以 `arm64-mac.yml` 不是标准路径，只有 `app-update.yml` 写着 `channel: arm64` 的构建会读它。
   - <https://github.com/electron-userland/electron-builder/blob/master/packages/electron-updater/src/providers/Provider.ts>
   - <https://github.com/electron-userland/electron-builder/blob/master/packages/electron-updater/src/MacUpdater.ts>

2. **arm64 包自己就换轨。** 下载 `Notion-arm64-7.32.0.zip` 解开读它自带的配置：

   ```
   Notion-arm64-7.32.0.zip → Contents/Resources/app-update.yml
     channel: arm64
   ```

   而 universal 构建带的是 `channel: latest`。装上 arm64 包会把用户从 `latest` **单向搬到** `arm64` 轨，此后 Notion 自己的更新器也回不去。

**结论：不要让 `ElectronManifestSource` 接管 Notion。** 走 `latest-mac.yml` 会拿到纯 x64 包（本仓库 arm64-only，装上就是架构降级）；走 `arm64-mac.yml` 会换轨。官网那条 universal dmg 才是用户所在轨该装的东西，而那正是 VendorProbe 配方读的。

## 更新检测
- 源: VendorProbe
- 端点: `https://www.notion.so/desktop/mac/download`，`mode: .redirectFilename`，`followRedirects: false`
- 为什么不跟随: 跳转目标就是 ~200 MB 的 dmg，跟随会让 CDN 直接把包发过来。读 307 的 `Location` 即可。
- 为什么用 `.so` 而不是 `.com`: `.com/desktop/mac/download` 会先绕一跳 `app.notion.com`。
- 版本方案: `Notion-([0-9]+\.[0-9]+\.[0-9]+)-` 从 `Location` 文件名取，marketing 版本，与 bundle 的 `CFBundleShortVersionString` 同构。

## Changelog
- 来源: What's New (Mac & Windows) 页，`ChangelogRecipe(notion.id)` 渲染原生条目
- `VendorProbe.changelogURL` 指同页作 WebView 兜底
- 注意: **不要**指向 `www.notion.com/releases` —— 那是产品公告 feed，「版本」是文章标题、不带 build 号，与安装版对不上

## 一键安装
- 状态: 支持
- 格式: dmg（官网 307 HEAD-follow 到 `Notion-<ver>-universal.dmg`）
- 门: VendorInstaller 强制同 Team `LBQJ96FQ8D` + 签名 + bundle id + 架构
- 说明: 装在 Notion 自己的 Squirrel 更新器之上；`defersToSelfUpdater` 在「运行中 + 延后」策略下会让路

## 已知问题
- 无阻塞项。脆弱点是官网那条 307：Notion 改下载页路由或改文件名前缀，`versionPattern` 就会失配 → 退化成 unknown（不会造假版本）。

## 如何复验

```sh
duo verify --only notion.id --samples

# 三条面各自现在给什么（不跟随重定向，避免拉下 200 MB）
python3 - <<'PY'
import urllib.request
class NR(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*a,**k): return None
try:
    urllib.request.build_opener(NR).open("https://www.notion.so/desktop/mac/download")
except urllib.error.HTTPError as e:
    print("官网 307 →", e.headers.get("Location"))
for f in ("latest-mac.yml","arm64-mac.yml"):
    b=urllib.request.urlopen("https://desktop-release.notion-static.com/"+f).read().decode()
    print(f, [l for l in b.splitlines() if l.startswith(("version","path","releaseDate"))])
PY
```

要复核「arm64 是另一条轨」这条结论，把 `Notion-arm64-<ver>.zip` 下下来读 `Contents/Resources/app-update.yml` 的 `channel:` 字段即可。
