# MagicQuit

| 交付项 | 官网直装副本 |
|---|---|
| 检测 | 1.4 没有包内更新源，由 `SparkleFeedCatalog` 补全官方 appcast。2.0 优先使用 ZIP 包内声明的同一 appcast |
| 一键安装 | 使用官方 appcast 的 ZIP 和现有 Sparkle 安装链。1.4 以 Developer ID、同 Team 和同 bundle ID 为信任锚。2.0 起另验下载包的 EdDSA 签名 |
| 更新日志 | 取目标版本发布标签的 `CHANGELOG.md`，按版本拆分且保留分节。没有更新结果的 1.x 副本读取 v2.0 标签归档中的旧版说明。未发布到 appcast 的开发分支说明不会进入发布版日志 |

[官网](https://magicquit.com/) 提供 1.4 DMG，[项目发布页](https://github.com/BigBerny/magicquit/releases/tag/v2.0) 提供 2.0 ZIP。两版均为 universal，bundle ID 为 `com.MagicQuit`。1.4（build 15）包内没有 Sparkle feed 或公钥。2.0（build 16）声明 [官方 appcast](https://raw.githubusercontent.com/BigBerny/magicquit/main/appcast.xml) 和 `SUPublicEDKey`，包内最低系统为 macOS 14。当前只有稳定版 appcast 条目。

官方 [发布流程](https://github.com/BigBerny/magicquit/blob/v2.0/RELEASING.md) 说明开发构建没有有效 Sparkle 公钥时不会启动厂商更新器。开发者签名安装路径仍以已安装包的 Team 和 bundle ID 为锚。没有可用签名锚的开发副本无法通过一键安装的既有检查。

## 夜扫覆盖

- `feed:com.magicquit` 对补全目录中的厂商 appcast 做健康检查。
- `install:sparkle:com.MagicQuit:stable:legacy-no-key` 检查老副本更新所指的 ZIP 和身份。1.4 没有公钥可供这一组验签。档案中的新包公钥属于验得的包身份，后续仍按旧版的无公钥路径检查。
- `install:sparkle:com.MagicQuit:stable:ed25519` 额外验证 ZIP 的 EdDSA 签名。公钥从签名 2.0 包取得。
- `changelog:com.magicquit:-:<2` 检查旧版的固定归档。当前版本的结构化日志模板需要具体版本，无安装副本的夜扫会在日志检查之后才查询 Sparkle feed，因此不会检查当前标签的 Markdown。可在有新版副本的 Mac 上用 `duo verify --changelog --only magicquit` 核对当前标签，或对真实副本执行 `channel-verify`。

## 历史与实测

2026-11-28，核对官网 1.4 DMG 与 GitHub 2.0 ZIP。两包均通过严格代码签名和公证检查，Team ID 均为 `4HMNGH59W8`。同日，appcast 的稳定条目是 2.0（16），enclosure 指向 2.0 发布 ZIP。发布标签内的 [Markdown](https://github.com/BigBerny/magicquit/blob/v2.0/CHANGELOG.md) 分列 2.0、1.4 和 1.3.1，2.0 标题下有 New 与 Improvements 两节。开发分支同日已出现 2.0.1 说明，appcast 尚未发布该版本。

同日 Apple Silicon、macOS 27.3 上用 Developer ID 签名 Release CLI 检测到 1.4 → 2.0。经现有大版本确认后，停用副本一键原地升级成功，下载 2,834,274 字节。安装后核对 build 16、原厂 Team、严格签名和公证，状态为最新。最终生产日志路径读出 3 个发布条目，2.0 有 10 条说明并保留 New 和 Improvements 标题。
