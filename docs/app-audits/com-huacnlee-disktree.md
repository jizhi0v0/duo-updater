# Disktree NSH

核对日期：2026-11-15。独立接入 `huacnlee/disktree`，不与 tobi 的 GPUI 产品互换。

## 身份与版本组

- Bundle ID：`com.huacnlee.disktree`；显示名 `Disktree`，文件夹也可能叫
  `Disktree NSH.app`。真实 0.1.0、0.1.7、0.1.8 副本的 short/build 均等于发布版本。
- 三份副本均为 ad-hoc 签名，无 Team ID；签名 identifier 等于 bundle ID，
  `codesign --verify --deep --strict` 均通过。无 `SUFeedURL`。
- 0.1.7 的 `Resources/nsh/app.json` 声明同一 ID、版本；
  `assets/nsh-updater.json` 指向 `huacnlee/disktree`。
- [上游 README](https://github.com/huacnlee/disktree) 明确说受
  [tobi/disktree](https://github.com/tobi/disktree) 启发，用 NSH 独立实现。
  后者的 ID 是 `io.github.tobi.disktree`，已有另一配方。没有证据表明它们是 ID
  迁移，因此两者保留各自 recipe family，不加 `BundleIDMigration`。

## 分发源与发布渠道

| 副本组 | 实际来源 | 检测 / 安装覆盖 |
|---|---|---|
| 手动解压的完整 App | GitHub Releases 普通 macOS tar.gz | GitHub 检测；开启 digest-only 后可一键 |
| 官方脚本安装的 App | 同一完整归档，固定目录内的 App 加 Applications 软链 | 可见 App 使用同一规则；脚本安装过程不由 Duo 执行 |
| mise 管理的副本 | 同一 GitHub 资产，mise 的版本目录 | 无默认 Applications 项；是否被扫描取决于副本位置，更新建议交给 mise |
| tobi 的 GPUI App | 独立 `tobi/disktree` 仓库 | 仍使用原有独立配方，不匹配此规则 |

[官方安装说明](https://github.com/huacnlee/disktree/blob/main/docs/install.md)
列出脚本、mise 与手动下载。此次未发现上游另列的 Homebrew、MAS 或 TestFlight
分发；Homebrew 的 `Casks/d/disktree.rb` 查询为 404，不把它当作所有第三方 tap 的证明。
0.1.0–0.1.8 共九个 release 均为 stable，未见 beta/nightly 或另一 bundle ID。

官方说明区分无自更新器的旧版与 updater-enabled 构建；观测 0.1.7 已含
自更新配置，启动时检查、用户确认下载与重启。新规则不执行厂商 shell 安装器，
直接更新完整 App；也不消费单独的 `-updater.tar.gz`。

## 检测、更新日志与一键

- 检测：GitHub `huacnlee/disktree`，tag 全串锚定 `vX.Y.Z`，不截断预发布版本。
  两个 plist 版本字段与 tag 同构，没有 marketing/build 换算。
- 更新日志：已有 GitHub Release 解析器。生产链实读 0.1.8 得到一条版本记录、
  两条正文（并行目录删除与 Intel 构建），不是只有下载链接。
- 一键：普通 `disktree-vX.Y.Z-aarch64-apple-darwin.tar.gz`。
  updater、Intel、Linux、校验和 sidecar 均不匹配；在受支持的 Apple Silicon
  宿主上取原生 arm64 App。
- 信任：复用 `.publishedDigestOnly`，需要用户开启既有设置；先核对 GitHub API
  公布的文件 digest，再核对严格签名、ad-hoc 身份、bundle ID 与落地版本。
  缺 digest、内容不符或身份不符时拒绝，不放宽通用安装门控。
- 0.1.8 普通 arm64 归档为 12,659,183 字节，实际 SHA-256 与 API 的
  `7b08b6196d23a075115e801b083d295f83b39c366c9b9cc5eba5db9d29b775ef` 相同。
  解压得到独立 `Disktree.app`，可执行文件只链接系统 framework。
- 官方脚本顶层 `disktree` launcher 委托 bundle 内的可执行文件，所以 App 换包也
  更新被启动的运行时。外层 launcher、安装标记及 mise 元数据不在此次替换范围内。
- 状态文件独立保存在 `~/Library/Application Support/Disktree/state.json`，
  内容为记住的目录；可用 `DISKTREE_STATE` 覆盖。

## 如何复验

真实 0.1.0、0.1.7 与 0.1.8 的生产 `channel-verify --expect stable` 均退出 0：
前两份为 GitHub → UPDATE 0.1.8，后一份为 GitHub → up to date。真实包的 bundle
ID 均为 `com.huacnlee.disktree`，short/build 分别为对应版本。

VM 原生一键结果及界面证据记录在
[VM 验证](../../verify/disktree-nsh-20261115/README.md)。

## 边界

- 验证的是普通完整 App。mise 的版本选择与元数据没有整合到此 App recipe。
- 厂商改用 Developer ID 时，既有 ad-hoc→Team 路线会拒绝，需要人工安装一次并
  重新评估配方，不能凭发布者账号相同就放行。
- Intel Mac 不属于 DuoUpdater 的支持宿主；在 Apple Silicon 上的 Intel 副本未
  单独做安装轮次。没有使用这个理由放宽归档选择或身份检查。
