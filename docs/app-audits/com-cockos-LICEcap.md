# LICEcap

## 分发和更新渠道

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版，通用二进制 | 官网 Download 栏的 macOS 链接，按 `CFBundleVersion` 比较 | 同一栏的版本化 DMG，复用 Developer ID、架构和包身份校验 | 官网逐版列表保留发布日期、条目和平台前缀 |
| 官网 1.29、1.30 Intel 副本 | 同 ID、同版本字段，可在有 Rosetta 的 Apple Silicon 上检查 | 同 Team，目标包原生支持 Apple Silicon。旧包的 Finder 元数据会使在挂载点上的严格签名复核失败 | 与通用版本共用官网发布历史 |
| 官网 1.28 及更老的历史轨 | 实查 1.25、1.28 的包仅含 i386/PPC 时代的可执行文件，当前系统无法运行 | 官网现行 DMG 可手动安装 | 官网保留早期历史 |
| Homebrew `licecap` | cask 指向同一官网 DMG，现有 Homebrew 源处理它所托管的副本 | 由现有安装来源决定 | 同一官网发布历史 |

官网当前发布区只有一个 macOS 正式下载入口，另列 Windows 版本及历史包。官方 GitHub 镜像是源码入口。实查的 macOS 包没有声明 Sparkle 更新源。安装路径采用同一份官网响应中经过版本号核对的相对链接。包内只写了 `CFBundleVersion`，扫描器因此为此 ID 将该字段用作界面所需的版本标签，探测仍按构建字段比较。 [官网发布页](https://www.cockos.com/licecap/) · [官方源码镜像](https://github.com/justinfrankel/licecap) · [Homebrew cask](https://formulae.brew.sh/cask/licecap)

官网为 1.32 显示的条目均明确标为 Windows，结构化日志保留原标记。1.31、1.30 和 1.29 有厂商标明的 Mac 条目。

## 夜扫覆盖

- `vendor:com.cockos.LICEcap:stable` 监测官网最新 macOS 版本与对应下载链接。
- `install:vendor:com.cockos.LICEcap:stable` 监测官网正式版 DMG 的下载和签名身份。
- `changelog:com.cockos.LICEcap:-` 监测官网有日期的 macOS 发布记录。

动态检查随本批 VM 验收运行 `duo verify --vendor --changelog` 和 `duo verify-install --full`。

## 历史与实测

2026-11-28 在 Apple Silicon macOS 27.2 VM 挂载官网 1.31 和 1.32 DMG。镜像均带 GPL 文本，现有 DMG 挂载逻辑通过标准输入处理确认。两包均为 arm64/x86_64，bundle ID 为 `com.cockos.LICEcap`，Team ID 为 `Y3T58622SG`，严格签名及 Gatekeeper 公证均通过。两个版本均无 `CFBundleShortVersionString`，构建字段分别为 `1.31` 和 `1.32`。

实查 1.29 和 1.30 官网包同 ID、同 Team，版本也只有构建字段。1.29 有 x86_64/i386，1.30 只有 x86_64。两个历史包均通过 Gatekeeper 公证，在只读镜像上运行严格签名复查时报告 Finder 信息或资源叉。1.25 和 1.28 同 ID、同 Team，未包含 x86_64 或 arm64。 [官网下载历史](https://www.cockos.com/licecap/#old)
