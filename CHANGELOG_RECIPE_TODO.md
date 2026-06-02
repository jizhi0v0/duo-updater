# Changelog Recipe 待接清单

本机已安装第三方 app 中尚未注册 `ChangelogRecipe` 的，按优先级排列。
完成一个就把 `[ ]` 改成 `[x]`。

> 说明：MAS（App Store）安装的 app 走系统自更新，不接 changelog。
> 下面只列 **非 MAS** 且未注册 recipe 的 app。

## 待接
- [x] Surge — `com.nssurge.surge-mac`
      根因不是缺 recipe：appcast 用 `<markdownDescription>`（markdown），
      而解析器只认 `<description>`(HTML) → 内联 notes 丢失 → 回退 webview。
      已让 SparkleAppcastSource 解析 markdownDescription 为结构化 changelog
      （新增 AppcastMarkdownParser）。两个通道当前 feed 完全相同。
- [~] Mirage Host — `com.ethanlipnik.Mirage-Host`
      不接：appcast 已带 releaseNotesLink，指向干净的单版本 HTML notes 页，
      webview 已正常显示。URL 按版本固定，写死 recipe 每次发版即失效，不值。

## 不接 — 其他原因
- ToDesk `com.youqu.todesk.mac` — macOS changelog 去年停更，
  与 Windows 不同步（macos/uplog.html 是死数据）
- Claude desktop `com.anthropic.claudefordesktop` — 几乎没有 changelog

## 不接 — MAS 安装（App Store 自更新）
- Bob `com.hezongyidev.Bob`、Paste `com.wiheads.paste`、Spark `com.readdle.smartemail-Mac`
- Telegram `ru.keepcoder.Telegram`、ScreenCam `cam.thescreen`、Mirage `com.ethanlipnik.Mirage`
- DingTalk `com.dingtalk.mac`、WeChat `com.tencent.xinWeChat`、虎牙直播HD `com.yy.kiwihd`
- Microsoft Excel / Word、TestFlight、Xcode

## 不接 — 系统 / 大厂自更新 / 自研
- Apple：Safari
- 大厂自更新：Google Chrome、IntelliJ IDEA
- 自研：DuoUpdater、DuoPaste、ClaudeUsageMenuBar、OCRIndexerApp、Claude Code URL Handler
