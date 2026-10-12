# Kitten

API 客户端（Postman / Bruno 一类），基于 Zed 的 GPUI 构建：主题 schema 指向 `zed.dev`，
更新方式也照搬 Zed（每个 channel 一个 bundle id，自研 updater 向厂商 release service 要当前 channel 的最新 asset）。
2026-10 以 public beta 形式只发 Preview 轨。

## 基本信息
- Bundle ID: `dev.kitten.Kitten-Preview`（二进制里还列了 `dev.kitten.Kitten`、`dev.kitten.Kitten-Dev`）
- Team ID: 无（ad-hoc linker-signed，签名 identifier `kitten`）
- 观测版本: short `0.1.0`, build `0.1.0`（2026-10-12）
- 自更新机制: 自研（Rust `src/update.rs`，UA `Kitten Auto Updater`，下载 dmg → `hdiutil attach` → `rsync` 覆盖）
- 开源: 未找到公开仓库（`gh search repos kittenapi` 无对应项目）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | —      | ○ 轨道未开放 |
| **preview**  | —       | —        | —   | —      | ✓ 只检测 |
| **dev**      | —       | —        | —   | —      | — 未对外发布 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| preview | `dev.kitten.Kitten-Preview` | 独立 | bundle id 后缀 `-Preview` | 独立端点 `releases/preview/…` | ✓ |
| stable  | `dev.kitten.Kitten`（二进制字符串） | 独立 | — | `releases/stable/…` 现 404 | ○ |
| dev     | `dev.kitten.Kitten-Dev`（二进制字符串） | 独立 | — | 未见公开端点 | — |

Pattern A，与 Zed 相同。

## 更新检测
- 源: `VendorProbeRecipe`，`channel: .preview`
- 端点: `https://api.kittenapi.com/releases/preview/latest/asset?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64`
  - 这是 app 自己 updater 发出的请求：二进制里有 `KITTEN_UPDATE_API_URL` 钩子，指向本地 HTTP 服务后启动，
    收到 `GET /?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64`，UA `Kitten Auto Updater`。
    钩子替换的是 `…/releases/<channel>/latest/asset` 整段 base。
  - 应答 `{"version":"0.1.0","url":"https://api.kittenapi.com/releases/preview/0.1.0/download?asset=kitten-macos-aarch64.dmg&source=updater"}`
  - `version` 是 marketing 串，等于 `CFBundleShortVersionString`（也等于 `CFBundleVersion`），不需要 `versionIsBuild`。
- 另有 GitHub 形状的 `GET /releases/latest?channel=preview`（`tag_name` + `assets[]`，只有 name 和 URL），
  对应二进制里的 `KITTEN_UPDATE_REPOSITORY`（GitHub 后备）。recipe 不用它：它不是默认 updater 发的请求。
- stable：`/releases/stable/latest/asset?…` 与 `/releases/latest` 都回 `404 {"error":"release channel \"stable\" is not available"}`。
- 读的是**轨道最新**：请求不带设备 id，答的就是下载页链接的那个构建（`www.kittenapi.com/download` 指向同一 `preview/0.1.0`）。
- 按 OS 分轨：应答不含任何系统版本字段；包内 `LSMinimumSystemVersion` = `10.15.7`。
- 按架构：arm64 查询与 Intel 查询答同一个 `version`；recipe 固定 arm64 查询，只取版本号。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | updater 流程是整包 dmg + `rsync`（二进制字符串 `hdiutil` / `attach` / `rsync` / `-av` / `--exclude`），无 delta/patch 字样 | 两个端点的应答都只有整包 URL | — |

## Changelog
- 来源: recipe，读 `https://www.kittenapi.com/releases/preview`（SvelteKit 服务端渲染，每版一个 `<article class="release" id="kitten-<ver>">`）
- 结构化: `recipe changelog:dev.kitten.Kitten-Preview:preview: 1 entries; newest 0.1.0: 5 items, headings ["Notices"]; first items ["First cross-platform build: Linux, macOS", "macOS builds are unsigned. On first laun", "The Windows installer is unsigned; Smart"]`
- 跟随 channel: 是（页面按 channel 分开：`/releases` = Stable、`/releases/preview` = Preview）
- Recipe 状态: 已有（preview）

## 一键安装
- 状态: **仅检测**，目前不可行
- 端到端: 未跑——没有 install spec，`duo install` 没有可执行的路线；厂商也只发过 `0.1.0` 一版，没有上一版可用来做 old→new
- 格式: dmg（arm64 / x86_64 各一个；另有 zip）
- 校验: 应答不带摘要（无 sha256 / sha512 / checksum 字段，下载的 302 目标是 Supabase storage 公共对象，响应头也没有）
- **读的是**: 轨道最新（同时也是下载页人人可手动下载的那个构建）
- 阻塞（三道闸都过不了，任一条单独就足以拦下）:
  1. 无 Team ID，gate 3（`verifyTeamIdentifierMatch`）直接拒：`noTeamIdentifier(installed)`。
  2. `codesign --verify --deep --strict` 自身失败：`code has no resources but signature indicates they must be present`
     （linker-signed 只签了 Mach-O，没有封装资源），gate 2 拒。
  3. ad-hoc 的 digest-only 路线（`InstallTrust.publishedDigestOnly`）只给 GitHub 规则开，且要求发布方公布 SHA-256、
     签名 identifier 等于 bundle id；这里没有摘要，签名 identifier 是 `kitten` ≠ `dev.kitten.Kitten-Preview`。
- 厂商自己的 release notes 写明 macOS 构建未签名（"macOS builds are unsigned"）。厂商改发 Developer ID 签名构建后再评估一键。

## 已知问题
- `duo verify` 对该 recipe 报 `oneClickCandidate` note（应答里有 dmg URL 而 recipe 只检测）。不接一键是有意为之，原因见上，
  recipe 注释里也写了。
- 只有一个版本，Update 判定路径是用改了 `Info.plist` 版本号（`0.0.9`）的副本验的，没在真实旧版上验过。

## 建议下一步
1. 厂商开放 stable 轨后，为 `dev.kitten.Kitten` 复制 preview recipe，把 URL 里的 channel 换成 `stable`、`channel` 改为 `.stable`，
   changelog 读 `/releases`；先用真包跑 `channel-verify`。
2. 厂商发出 Developer ID 签名构建后，按 Team-ID 闸评估一键（install `.bodyPattern` 读应答里的 `url`）。
3. 出现 `0.1.1`+ 时，用真实 `0.1.0` 跑一次 `channel-verify`，确认 `UPDATE 0.1.0 → …`。

## 如何复验

```bash
# 1. 端点（Preview 有、stable 404）
curl -sS "https://api.kittenapi.com/releases/preview/latest/asset?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64"
curl -sS "https://api.kittenapi.com/releases/stable/latest/asset?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64"

# 2. 生产检测 + changelog
swift run --package-path application-test channel-verify "/Applications/Kitten Preview.app" --expect preview

# 3. 签名
codesign -dv "/Applications/Kitten Preview.app" 2>&1 | grep -E "Identifier|flags|Team"
codesign --verify --deep --strict -v "/Applications/Kitten Preview.app"
```

2026-10-12 实测:
- `channel-verify`（安装副本 0.1.0）: `detected channel → preview` ✓、`VendorProbe ✓ recipe answered for channel 'preview'`、
  `latest 0.1.0`、`verdict up to date`；全链 `winning source Vendor`、`status up to date`。
- `channel-verify`（同一 bundle 的副本，`Info.plist` 两个版本号改成 `0.0.9`）: `verdict UPDATE 0.0.9 → 0.1.0`，`winning source Vendor`。
- 从 recipe 解析出的 dmg（`preview/0.1.0` arm64，14,102,260 bytes，SHA-256 `c7259f052be94be05cc7aa11346191b9db2ae1f01a3c4992e6995950263bff0f`）
  挂载后 `diff -rq` 与安装副本一致；bundle id `dev.kitten.Kitten-Preview`、`flags=0x20002(adhoc,linker-signed)`、`TeamIdentifier=not set`、arm64 only。
- `duo verify --only kitten`: vendor probe ✓ 1、changelog ✓ 1、changelog gap ✓ 1，另 1 条 `oneClickCandidate` note（见已知问题）。

## 历史与实测

### 2026-10-12 · 接入

- 端点来源：二进制字符串给出 `/releases/` + `/latest/asset` + `kitten-` + `asset` 的拼接片段和 `KITTEN_UPDATE_API_URL`；
  用这个钩子把 updater 指向本地 HTTP 服务，启动即收到 `GET /?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64`
  （UA `Kitten Auto Updater`），由此确定线上路径为 `releases/preview/latest/asset`。
- 只带 `os/arch` 而不带完整文件名（`?asset=kitten&os=macos&arch=aarch64`）时服务回 zip URL，版本相同；不带 `os` 回
  `400 {"error":"release asset requires os=linux, macos, or windows"}`。
- 下载链接 `…/download?asset=…&source=updater` 302 到 Supabase storage 公共对象，无摘要响应头。
