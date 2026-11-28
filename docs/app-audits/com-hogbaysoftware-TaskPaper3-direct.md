# TaskPaper 3

## 分发和更新渠道

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版 `com.hogbaysoftware.TaskPaper3.direct` | 官网发布页首条正式版本 | 同一版本的官方 DMG，已有安装链核对签名、Team ID 和 bundle ID | 官网逐版发布记录，保留日期、列表、段落及历史分类 |
| Homebrew `taskpaper` | cask 指向同一官网正式包，已有 Homebrew 源按实际托管状态处理 | 由现有安装来源决定 | 同一正式版发布记录 |
| 官网 Preview | 实查副本使用同一 direct ID，包内营销版本以 ` Preview` 结尾。此信号区分 Preview 与正式轨 | Preview 使用厂商的独立下载入口，本批无 Preview 安装配方 | Preview 发行说明在厂商论坛，正式日志配方排除该轨 |
| Mac App Store `com.hogbaysoftware.TaskPaper3` | 现有 App Store 源 | 现有 App Store 路径 | App Store 版本历史 |
| Setapp | 网站列出的另一发行入口，Setapp 托管副本走现有管理来源 | Setapp 客户端管理 | 本次覆盖官网直装正式版 |
| 官网旧 ID，已查到 3.3.2 | 厂商变更 direct ID 前的历史副本，3.3.2 使用现今 App Store 的 ID | 厂商指引旧用户手动下载完成首次迁移。这里仅注册已分开的 direct ID | 厂商逐版历史仍公开 |

包内虽有 Sparkle 框架，实查的官网正式包均未在 Info.plist 声明 `SUFeedURL`。官网 `/releases/` 的首条标题与同一标题内的版本化 DMG 必须一致，探针才报告该版本。安装地址沿用验证过的官网 HTTPS 主机与路径，并使用同一次探针选出的版本。旧 ID 与现今 App Store 版重合，历史迁移需另行验证直装来源识别，本次不添加共享 ID 的迁移规则。 [官网发布历史](https://www.taskpaper.com/releases/) · [App Store 身份](https://itunes.apple.com/lookup?id=1090940630&country=us) · [Homebrew cask](https://formulae.brew.sh/cask/taskpaper)

## 夜扫覆盖

- `vendor:com.hogbaysoftware.TaskPaper3.direct:stable` 检查首条正式版本和同一标头的下载锚点。
- `install:vendor:com.hogbaysoftware.TaskPaper3.direct:stable` 复用现有 vendor 安装验证，检查 DMG 下载和包内签名身份。该来源使用 Developer ID 验证。
- `changelog:com.hogbaysoftware.TaskPaper3.direct:-` 在同一官网检查逐版原生日志。Preview 独立发行尚未纳入本批夜扫。

2026-11-28，本批用签名 Release CLI 对正式轨运行 `duo verify --vendor --changelog` 和 `duo verify-install --full`，该应用的版本源、日志和安装包均为 `ok`。

## 历史与实测

2026-11-28 核对官网下载的 TaskPaper 3.9.3（484）及 3.9.4（487）。两个包都包含 arm64 和 x86_64，bundle ID 为 `com.hogbaysoftware.TaskPaper3.direct`，Team ID 为 `64A5CLJP5W`，严格代码签名及 Gatekeeper 公证验证均通过。当前 Preview 3.9.4 Preview（487）与正式包共用 direct ID、Team 和构建号，预览标志来自包内短版本。两条轨有各自的下载入口。 [正式版发布页](https://www.taskpaper.com/releases/) · [厂商 Preview 说明](https://support.hogbaysoftware.com/t/what-is-the-difference-between-taskpaper-preview-and-normal-taskpaper/1632)

实查 3.5（275）、3.5.1（276）和 3.6（285）旧官网下载仍使用相同 direct ID 和 Team，包为 pre-notarization 的 x86_64 Developer ID 签名。3.3.2（219）的官网包使用旧 ID `com.hogbaysoftware.TaskPaper3`。3.5 的发布说明把手工重新下载列为旧版变更 ID 后的迁移方式。 [厂商历史记录](https://www.taskpaper.com/releases/)

2026-11-28，在 Apple Silicon、macOS 27.3 上用签名 Release CLI 验证 3.9.3 → 3.9.4。官网下载 4,740,572 字节，停用副本实际原地替换成功。升级后复查为最新，bundle ID、原厂 Team、严格签名和公证均通过。生产日志路径读出 40 个版本，3.9.4 有 4 条原厂说明。已用官网 3.9.4 Preview 真包复查，识别为 Preview，正式轨未给出更新和日志。
