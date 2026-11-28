# One Switch

- 官网版 bundle ID 为 `studio.fireball.OneSwitch`，独立于 [Setapp 版](https://setapp.com/apps/one-switch) `studio.fireball.OneSwitch-setapp`。Setapp 版由 Duo 的通用 Setapp 目录源检测，安装由 Setapp 客户端处理。
- 厂商的官网正式 appcast 由程序拼装，未写入 `SUFeedURL`。Duo 在扫描时补全该 URL，再使用通用 Sparkle 版本比较。[官网正式 appcast](https://fireball.studio/api/release_manager/studio.fireball.OneSwitchOfficial.xml)
- 官网包共用同一个 bundle ID 和版本格式。Duo 只在应用的布尔偏好 `SUUpdaterChecksForBetaUpdates` 开启时切换到 Beta appcast。Beta feed 包含正式版和预发布条目，两条 feed 均无预发布频道标签。[官网 Beta appcast](https://fireball.studio/api/release_manager/studio.fireball.OneSwitchOfficial.xml?beta=1)

## 一键安装

官网正式 appcast 提供发布构建号、营销版本和带 EdDSA 的整包 ZIP。Duo 的通用 Sparkle 安装链验证 EdDSA、应用签名、Team 与 bundle ID，再替换应用。

1.x 官网包内有后台登录项 `studio.fireball.OneSwitch.OneSwitchHelper` 和 `studio.fireball.OneSwitch.OneSwitchXPC`。2.0/462 保留该 XPC，包内已经没有旧登录 helper。需要管理员授权的 Keep Awake 功能在 1.x 使用 SMJobBless 安装特权组件，2.0/462 改为使用 `SMAppService` 注册 `studio.fireball.OneSwitch.Daemon`。该组件的授权与迁移由 One Switch 管理，已授权运行态需要单独验证。

1.x → 2.0 或更高版本保留 Sparkle 检测和发布说明，并引导用户打开 One Switch，通过应用自己的 Check for Updates 完成升级。1.x 同代升级和已经是 2.x 的副本继续走通用安装链。夜扫仍下载并检查两轨的实际更新包。

Apple Silicon macOS 27.2 VM 用签名 Release CLI 从 1.35.2/429 原地更新到 1.35.4/440，关闭态和运行态都成功。换包后 `duo restart` 将主进程从 23043 换为 23118，将 XPC 从 23052 换为 23121。旧版登录 helper 启动后自行退出。新版包内的登录 helper 和 XPC 都报告 build 440，严格签名与 Gatekeeper 通过，再检查显示已是最新版。

## Changelog

appcast 为同一条目发布多个带 `xml:lang` 的链接。结构化 recipe 读取当前条目选中的语言和 build 页面，接受官网正式版路径。页面标题是 One Switch Official。单段说明保留为一条，列表之前以冒号结束的独立段落显示为标题。页面可能附带近期版本回顾，版本归属从 appcast 选择的页面确定。

## 夜扫覆盖

- 正式与 Beta feed 分别核对 `feed:studio.fireball.OneSwitch:stable` 和 `feed:studio.fireball.OneSwitch:beta`。两条 changelog 检查是 `changelog:studio.fireball.OneSwitch:stable` 和 `changelog:studio.fireball.OneSwitch:beta`。
- 公共安装器清单记录 `sparkle:studio.fireball.OneSwitch:stable` 和 `sparkle:studio.fireball.OneSwitch:beta`，报告在各 ID 前加 `install:`。两轨使用官网旧版和当前版共有的 Ed25519 公钥。首次实包验证用于建立观测。
- VM 联跑 `duo verify --vendor --feed --changelog --only rawtherapee,studio.fireball.OneSwitch` 时，One Switch 所选 feed 与日志检查均通过。`duo verify-install --full --only studio.fireball.OneSwitch` 下载 440 和 462，两个安装包均通过检查。
- Setapp 版由订阅目录提供更新，官网公开包夜扫不覆盖该版本。

## 历史与实测

2026-11-28 检查了官网 1.34.2/413、1.35.2/429 和 1.35.4/440 的 Sparkle ZIP，以及 1.35.4/440 官网 DMG。三版 Sparkle ZIP 均有相同的 bundle ID、Team `KAQ3M6FSM7` 和 `SUPublicEDKey`，严格签名验证与 Gatekeeper 公证检查通过。413、429、440 的包内都有正式版 appcast 的基地址和文件名。429 和 440 的 ZIP 是官网 appcast 所列的相邻正式版。

同日检查了最早仍列出的 1.15/266 Intel ZIP 和 Beta 首条 2.0/462 通用 ZIP。两者保持同一身份、Team 和公钥，严格签名与 Gatekeeper 公证检查均通过。462 包内的系统下限为 macOS 15，feed 声明为 12.0。Beta feed 历史构建 411、412、427、438 的完整 ZIP，以及 462 的 delta 基底构建 461 的完整 ZIP，均返回 HTTP 404。

VM 中使用 1.35.2/429 自身的检查入口，默认获得 1.35.4。退出后将测试副本的 `SUUpdaterChecksForBetaUpdates` 改为布尔真，重新启动后从同一入口获得 2.0。429、440 和 462 的二进制还包含自身的 Beta 开关提示文本。

最终签名 CLI 中，整数 `2` 仍选正式版 440。布尔真使 440 检测到 Beta 2.0/462，462 实包显示已是最新版。Duo 日志面板将 462 英文发布页呈现为五条，原文没有分段标题。CLI 将 440 到 462 标记为自带更新器路径，直接安装请求被拒绝，副本仍为签名有效的 440。

取样的 440 英语、简体中文和繁体中文发布说明各有一段关于勿扰模式的说明。[440 英语发布说明](https://fireball.studio/api/release_manager/releasenotes/440/en/studio.fireball.OneSwitchOfficial.xml)

429 英语和简体中文说明各有两个分段，复用相同的 HTML 模板。[429 英语发布说明](https://fireball.studio/api/release_manager/releasenotes/429/en/studio.fireball.OneSwitchOfficial.xml)

Setapp ID 来自公共目录的 One Switch 条目。[Setapp 公共目录](https://store.setapp.com/store/api/v8/en)
