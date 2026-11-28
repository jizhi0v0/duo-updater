# Ukelele

| 交付项 | 官网副本 |
|---|---|
| 检测 | `SparkleFeedCatalog` 补全正式 HTTPS 地址，版本、轨道和系统要求由 `SparkleAppcastSource` 处理 |
| 一键安装 | 下载厂商 DMG，由现有 Sparkle 安装路径验证 EdDSA、bundle ID、Developer ID 和签名团队 |
| 更新日志 | [SIL 官方版本历史](https://software.sil.org/ukelele/ukelele-version-history/)按版本和发布日期拆分，每段说明保留为单独条目 |

SIL 官网分发 `org.sil.ukelele`。核对的 3.7.0 和 3.7.1 为 Apple Silicon 与 Intel 通用包，最低 macOS 12。其 `Info.plist` 的 `SUFeedURL` 在 URL 两侧包含字面双引号，扫描无法读出该地址。目录补全只在包内无法解析地址时生效，继续优先读取厂商日后声明的有效地址。旧版 3.5.12 也使用同一 ID、签名团队、带引号的地址及 Ed25519 公钥。

更早的 3.4.2 是 Intel 包，签名标识为 `org.sil.Ukelele`（大写 U），声明同一个厂商 feed 和相同 Ed25519 公钥。厂商 feed 为旧副本提供同一新版包，安装复用 `BundleIDMigration`，只允许同一 Team 的低于 3.5.12 的旧签名标识升级为小写标识。该界限是已观测的新版标识，大小写切换的精确首版未确定。

[官方 appcast](https://software.sil.org/downloads/r/ukelele/Ukelele_appcast.xml) 把正式版和历年测试版都写在同一个 feed。对未打轨道标签且营销版本为 `3.6b7` 这类格式的条目标作 beta，保留厂商显式给出的标签。稳定副本排除这些条目。Sparkle 仍可由匹配的已安装构建判定 beta，同时允许 beta 升到更新的正式版。

appcast 的 3.7.1 内联 HTML 有漏闭合的 `<h2>`，同一条更新还包含 3.7 的历史。官网版本历史分别列出 3.7.1 与 3.7，后者与安装包和 appcast 中的 `3.7.0` 按现有版本比较等价。

## 夜扫覆盖

- `feed:org.sil.ukelele` 对目录中的官网 appcast 做 feed 健康检查。
- `install:sparkle:org.sil.ukelele:stable` 覆盖稳定轨的官网下载包，公钥来自同组签名真包。历史 beta 仍可升级到有监控的稳定轨。`org.sil.ukelele:beta` 记为历史轨缺口，留在公开 feed 中的测试版下载均已失效。
- 2026-11-28，在本批 `duo verify --feed` 与 `duo verify-install --full` 中均通过。正式版 3.7.1 的 DMG 通过整包 Ed25519 验签。

## 历史与实测

2026-11-28，核对 3.7.0（474）和 3.7.1（475）真包，两者通过严格代码签名及公证检查，Team ID 均为 `3YE4W86L3G`。3.5.12（396）真包使用相同身份和 Ed25519 公钥。3.4.2（3.4.2.314）的只读 DMG 真包同样通过严格签名与公证，签名 ID 为 `org.sil.Ukelele`。3.7.1 无法满足 3.4.2 的原始指定要求，将要求中的签名标识改为小写后通过，证书和 Team 条件保持一致。

同日 appcast 有 29 条历史记录。逐一发送 HEAD 请求，9 个未标记的历史 beta 下载均返回 HTTP 404，具体为 3.6b1 至 3.6b7、3.5b1 和 3.4b3。回归测试用真实 feed 片段验证新版正式包仍对稳定与 beta 副本可见，并约束显式轨道优先级。官网下载历史页可读出 3.7.1 修复创建键盘布局集合问题，并单列 3.7 的改动。

同日 Apple Silicon、macOS 27.3 上的 Developer ID 签名 Release CLI 实际把停用的 3.7.0 和 3.4.2 分别换成 3.7.1。两个安装都下载 54,065,856 字节；3.4.2 的签名 ID 按迁移规则变为 `org.sil.ukelele`。两次安装后均重新通过严格签名、公证和升级状态复查。最终生产日志路径提供 40 条结构化版本历史。
