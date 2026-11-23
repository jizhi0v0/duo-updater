# kitty

本页记录 `net.kovidgoyal.kitty` 官网更新日志的接入实测。Stable 的版本探测与安装已纳入 nightly 的 `github:kovidgoyal/kitty:stable` 和 `install:github:kovidgoyal/kitty:stable` 检查。滚动 Nightly 与 Stable 共用 bundle ID，现有判轨读取的应用包元数据没有渠道标记，见 [CHANNEL_COVERAGE_TODO.md](../../CHANNEL_COVERAGE_TODO.md)。

## 历史与实测

2026-11-23 抓取 [官网详细更新日志](https://sw.kovidgoyal.net/kitty/changelog/#id1)，核对了 136 个带日期的版本段落。最新的 0.51.1 有 15 条，0.51.0 有 24 条，0.50.0 有 50 条。页面开头的功能导览使用不同格式的标题，详细日志的 `#idNN` 锚点随新版本插入移动。接入按版本标题定位，采用最近 40 版的默认上限。
