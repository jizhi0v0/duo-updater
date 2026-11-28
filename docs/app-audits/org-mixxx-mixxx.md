# Mixxx

## 已接入的副本

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版 `org.mixxx.mixxx` | 从官网 ARM 正式包链接读取版本 | 下载版本化 ARM DMG，核对官网同一下载项的 SHA-256，并验证 bundle ID 和签名方 | 从当前正式版手册提取有发布日期的版本及分节条目 |
| 官网历史 Intel 2.1.8、2.2.3、2.2.4 及已识别的 2.3.x | 用旧包的签名哈希或 Git 构建描述识别，继续检测正式版 | 旧包 Team ID 为 FLYL4D545V，与现行 Team 不同，需从官网手动更新 | 正式版日志 |
| Homebrew `mixxx` | 现有 Homebrew 路径判断 cask 归属 | 用现有 Homebrew 路径更新登记副本 | 复用同 bundle ID 的正式日志 |
| 官网 Beta、Alpha 与维护快照 | 主程序中的 Git 构建描述标明快照轨，正式版探针跳过 | 保留官网快照下载流程 | 正式日志配方仅匹配正式轨 |

Apple Silicon 上的官网正式复制包统一使用 ARM 下载。即使原副本是经 Rosetta 运行的官网 Intel 包，原地替换仍要通过安装器的代码签名、Team ID 和 bundle ID 检查。

快照版和正式版的 Info.plist 都使用 `org.mixxx.mixxx` 和纯数字点分版本。扫描器先检查 Beta、Alpha 和维护快照的 Git 构建描述，再用 Git 标记 HEAD 与同一完整版本确认正式版。已核实的 2.1.8、2.2.3 和 2.2.4 SCons 正式包使用签名哈希确认。实查正式 2.3.6 使用旧 Team，正式 2.4.0 使用现行 Team。2.4 的公开 Beta 在 HEAD 后记录不带提交后缀的 `2.4-beta`。其余不能确认渠道的副本跳过正式版配方。

## 夜扫覆盖

- 版本探针为 vendor:org.mixxx.mixxx:stable:arm64 及历史 Intel 探针 vendor:org.mixxx.mixxx:stable:legacy-intel，正式版完整 ARM 安装包为 install:vendor:org.mixxx.mixxx:stable:arm64。
- 结构化日志为 changelog:org.mixxx.mixxx:stable。手册的未发布或跳过版本没有发布日期，解析时排除。
- 快照轨没有登记为正式版目标。

## 历史与实测

2026-11-28，本机读取官网 2.5.4 和 2.5.6 的 ARM DMG。两版 bundle ID 均为 `org.mixxx.mixxx`，Team ID 均为 JBLRSP95FC，严格签名和 Gatekeeper 公证通过。DMG 的文件夹内是 Mixxx.app，现有归档提取器支持这一层目录。官网还给每个 ARM 包列出独立摘要。版本探针要求 DMG 与摘要链接写出同一版本。

2.6 Beta 和 2.7 Alpha 真包的两个 plist 版本字段分别为 2.6.0 和 2.7.0。主程序分别含 UTF-16 构建描述 2.6-beta-505-g71c5dee15c 和 2.7-alpha-450-gf8d7c4e818。两个测试快照均含 ASCII 数据库兼容字符串 2.6.0-beta。另实查官网维护快照 2.5.4-1-g08b6aeb3ee，其 plist 版本是 2.5.4，可执行文件的 ASCII Git 构建描述带提交后缀。2.5.4 和 2.5.6 正式包则在 HEAD 之后记录不带后缀的完整版本。

[官网下载](https://mixxx.org/download/) · [官方 2.5.6 发布记录](https://mixxx.org/news/2026-03-27-mixxx-2_5_6-released/) · [官方手册日志](https://manual.mixxx.org/latest/en/chapters/appendix/changelog)
