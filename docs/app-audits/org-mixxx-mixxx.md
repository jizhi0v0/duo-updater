# Mixxx

## 已接入的副本

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版 `org.mixxx.mixxx` | 从官网 ARM 正式包链接读取版本 | 下载版本化 ARM DMG，核对官网同一下载项的 SHA-256，并验证 bundle ID 和签名方 | 从当前正式版手册提取有发布日期的版本及分节条目 |
| Homebrew `mixxx` | 现有 Homebrew 路径判断 cask 归属 | 用现有 Homebrew 路径更新登记副本 | 复用同 bundle ID 的正式日志 |
| 官网 Beta 与 Alpha 快照 | 主程序中的 Git 构建描述标明测试轨，正式版探针跳过 | 保留官网快照下载流程 | 正式日志配方仅匹配正式轨 |

Apple Silicon 上的官网正式复制包统一使用 ARM 下载。即使原副本是经 Rosetta 运行的官网 Intel 包，原地替换仍要通过安装器的代码签名、Team ID 和 bundle ID 检查。

快照版和正式版的 Info.plist 都使用 `org.mixxx.mixxx` 和纯数字点分版本。扫描器以可执行文件里的 UTF-16 Git 构建描述识别 Beta 或 Alpha。执行文件无法确认渠道时跳过正式版配方。快照编号在包内显示版本字段中没有体现，两条快照轨仍由官网独立发布。将它们与正式轨隔离，避免将以后可能版本号相同的正式包推给快照副本。

## 夜扫覆盖

- 版本探针为 vendor:org.mixxx.mixxx:stable，正式版完整 ARM 安装包为 install:vendor:org.mixxx.mixxx:stable。
- 结构化日志为 changelog:org.mixxx.mixxx:stable。手册的未发布或跳过版本没有发布日期，解析时排除。
- 快照轨没有登记为正式版目标。

## 历史与实测

2026-11-28，本机读取官网 2.5.4 和 2.5.6 的 ARM DMG。两版 bundle ID 均为 `org.mixxx.mixxx`，Team ID 均为 JBLRSP95FC，严格签名和 Gatekeeper 公证通过。DMG 的文件夹内是 Mixxx.app，现有归档提取器支持这一层目录。官网还给每个 ARM 包列出独立摘要。版本探针要求 DMG 与摘要链接写出同一版本。

2.6 Beta 和 2.7 Alpha 真包的两个 plist 版本字段分别为 2.6.0 和 2.7.0。主程序分别含 UTF-16 构建描述 2.6-beta-505-g71c5dee15c 和 2.7-alpha-450-gf8d7c4e818。两个快照同时包含 ASCII 数据库兼容字符串 2.6.0-beta，因此按该字符串判断会误标 Alpha。

[官网下载](https://mixxx.org/download/) · [官方 2.5.6 发布记录](https://mixxx.org/news/2026-03-27-mixxx-2_5_6-released/) · [官方手册日志](https://manual.mixxx.org/latest/en/chapters/appendix/changelog)
