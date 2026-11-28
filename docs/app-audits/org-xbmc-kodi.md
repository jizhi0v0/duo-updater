# Kodi

| 发行版 | 检测 | 一键安装 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版，Apple Silicon | 厂商 ARM64 镜像目录。选择最高的正式版本，只接受不带预发行后缀的镜像条目 | 厂商同一条目里的版本化 DMG，经标准签名及 Team ID 校验原地替换 Kodi.app | 官方 RSS 的正式发布文章，保留章节名和条目 |
| 官网候选版、测试版、开发构建 | 同 bundle ID。安装包版本后缀与正式版独立；正式探测只接收纯数字点分版本，可有末尾点 | 暂未接入各自的换包路径 | 暂未接入各自的日志，不能借用正式版日志 |

## 发行边界

[官网 macOS 下载](https://kodi.tv/download/macos/) 区分正式版、预发行版和开发构建，并分别提供 Intel 与 Apple Silicon 安装包。Apple Silicon 上的官网正式版由 VendorProbe 处理，通过 cask 安装的副本也可走既有 Homebrew 来源。正式版与预发行版共享 `org.xbmc.kodi` 和签名 Team，签名身份单独无法区分轨道。正式配方同时限制已安装的版本形态、ARM64 主机和下载条目。厂商目录的候选版与测试版条目在代号后加 `_rc` 或 `_beta` 等后缀，而正式版条目例如 `kodi-21.3-Omega-arm64.dmg`。

[Kodi 的正式发布](https://kodi.tv/article/kodi-21-3-omega-release/)确认 21.x 点更新可直接覆盖已有安装。官网 ARM64 DMG 中是应用本体，实包检查未见需独立安装的常驻组件。试验性安装包和纯 Intel 主机不在本配方的支持范围内。旧签名或改包同样需要通过已有的签章和 Team ID 检查。

## 夜扫覆盖

- `vendor:org.xbmc.kodi:stable` 由 VendorProbe 注册表枚举，验证镜像目录可解析出正式版。
- `install:vendor:org.xbmc.kodi:stable` 验证同一条目解析的版本化 DMG 和归档内的签名身份。下载使用官网链接的 `https=1` 参数来选用 HTTPS 镜像。目录没有随条目返回摘要，常规安装以包签名及 Team ID 为信任锚。
- `changelog:org.xbmc.kodi:stable` 读取 [Kodi 官方 RSS](https://kodi.tv/rss.xml) 的完整文章正文。当前两篇 Omega 点更新文章以粗体段落命名变更类别，后接条目。没有条目的正文不会成为结构化条目。
- [候选版、测试版](https://mirrors.kodi.tv/releases/osx/arm64/)及 [夜版](https://mirrors.kodi.tv/nightlies/osx/arm64/)与正式版分开分发。已验的 master 夜版和正式 Alpha 都使用 Alpha 版本后缀，不能靠该字段区分两者。本批只为官网正式版登记探测、安装和日志夜扫。

2026-11-28，本批用签名 Release CLI 对正式轨运行 `duo verify --vendor --changelog` 和 `duo verify-install --full`，该应用的版本源、日志和安装包均为 `ok`。

## 历史与实测

2026-11-28，官网 21.2 与 21.3 的真实 ARM64 DMG 均通过严格签名与公证检查，并与官网同名 `SHA256` 文件吻合。Team ID 为 `QR7RHK8K4X`。安装包文件名提供点分营销版本，包内 `CFBundleShortVersionString` 分别是 `21.2.`、`21.3.`，`CFBundleVersion` 则是日期与提交摘要。比较沿用现有版本比较器，末尾点不产生额外数值分量。

同日检查官网候选版 [Piers RC 2](https://kodi.tv/article/kodi-22-piers-rc-2/) 与 master 夜版真实 ARM64 包，两者与正式版同 bundle ID 和 Team，营销版本分别为 `22.0.rc2` 和 `23.0.alpha1`。Beta 2 的后缀由 [厂商源码的版本标签](https://github.com/xbmc/xbmc/blob/22.0b2-Piers/version.txt)给出。RSS 使用生产 UA 读到 [21.3](https://kodi.tv/article/kodi-21-3-omega-release/) 与 [21.2](https://kodi.tv/article/kodi-21-2-omega-release/) 的正式版正文和日期，分别提取 25、35 个条目和 9、11 个章节。

2026-11-28，在 Apple Silicon、macOS 27.3 上用签名 Release CLI 验证 21.2 → 21.3。官网下载 75,971,665 字节，停用副本实际原地替换成功。升级后复查为最新，bundle ID、原厂 Team、严格签名和公证均通过。生产日志路径读出 两个正式发布版本，21.3 的 25 条说明及 9 个原厂章节。已用官网 RC2 和 master 真包复查，分别识别为 RC 和 Alpha，正式轨未给出更新和日志。
