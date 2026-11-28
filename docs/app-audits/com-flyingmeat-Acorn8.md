# Acorn 8

## 官网分发与更新轨道

Flying Meat 官网 ZIP 的 bundle ID 为 `com.flyingmeat.Acorn8`，Team ID 为 `WZCN9HJ4VP`。已查验的 8.7.2 正式版、8.7.3 正式版和 8.8b1 测试版使用同一个身份。官网下载的副本使用 Sparkle，Mac App Store 安装由原商店管理。规则以 Acorn 8 的 bundle ID 为范围。

| 轨道 | 观察到的 build | 厂商源 | 安装方式 |
|---|---|---|---|
| stable | 8.7.3 / 18029 | [官方正式版 feed](https://flyingmeat.com/download/acorn8update.xml) | ZIP，feed 使用滚动地址 |
| beta | 8.8b1 / 18043 | [官方测试版 feed](https://flyingmeat.com/download/latest/acorn8update.xml) | ZIP，feed 使用滚动地址 |

8.7.3 与 8.8b1 的 arm64 可执行文件均在切换测试版时写入标准 `UserDefaults` 的 `SUFeedURL`，再把选定地址传给 Sparkle。测试版程序的启动代码同样注册正式版地址为默认值，读取偏好并迁移旧 HTTP 地址。DuoUpdater 只把完全匹配官方 HTTPS 测试版地址的值视为测试版选择。缺省及未知偏好使用正式版 feed。已安装的测试版仍受版本比较保护，关闭测试轨后不会被推送更旧的正式版。 [官方测试版与切换入口](https://flyingmeat.com/download/latest/)

## 更新检测、一键升级和更新日志

- 检测复用 Sparkle。官网包未声明 `SUFeedURL`，渠道绑定提供与偏好相符的官方地址。若未来包直接声明地址，优先沿用包声明。现有 feed 的最低系统版本字段为未展开的 `$(MACOSX_DEPLOYMENT_TARGET)`，实包最低 macOS 14，下载后仍以签名包声明做运行兼容性检查。
- 一键使用 appcast `enclosure`。两条轨道均为旧 DSA 签名，无 Ed25519 公钥。安装会验证 Developer ID、bundle ID 与已安装副本的 Team ID，并在写入之前要求下载包的 `CFBundleVersion` 与本次 feed 所报 build 完全一致，防止滚动 ZIP 更新与 feed 不同步。
- 两条 feed 自带分版本、分节的 HTML。解析直接复用已取得的 feed 内容。测试版顶部的 `Acorn 8.8` 对应 `8.8b1`，仅在顶部日志与所报测试版本前缀完全相符时挂到该版本。正式版历史保留为单独条目。当前条目的日期取自 appcast `pubDate`，HTML 里曾出现未来年份占位日期。 [官方正式版更新日志](https://flyingmeat.com/acorn/releasenotes.html)

## 包与源验证

2026-11-28 观察到正式版 8.7.2 / 18025 与 feed 正式版 ZIP 8.7.3 / 18029 的身份一致，严格签名与公证均通过。厂商公开测试版 ZIP 与其 feed 对应 8.8b1 / 18043，同样通过严格签名与公证。测试轨只提供当期滚动 ZIP，未取得可用于旧版到新版安装的历史测试版。两条 feed 的日志均有分节，正式版首条有 4 个项目，测试版首条有 13 个项目。

## 夜扫覆盖

- `feed:com.flyingmeat.Acorn8:stable`、`feed:com.flyingmeat.Acorn8:beta` 由渠道绑定枚举，检查两条公开 Sparkle feed。
- `install:sparkle:com.flyingmeat.Acorn8:stable`、`install:sparkle:com.flyingmeat.Acorn8:beta` 通过安装验证清单检查滚动 ZIP、身份和 build。已明确记录厂商仅提供 DSA，当前实包有 Developer ID Team ID。
