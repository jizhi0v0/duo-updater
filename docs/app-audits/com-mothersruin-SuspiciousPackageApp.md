# Suspicious Package

## 基本信息

- Bundle ID: `com.mothersruin.SuspiciousPackageApp`
- Team ID: `936EB786NH`（Developer ID Application: Randy Saldinger）。3.0、4.3.3、4.7、4.8 的真实 DMG 内 app 均为此身份。
- 观测版本: 4.8（`CFBundleVersion` 1457），上一版 4.7（1415）；审计日期: 2026-11-16。
- 分发: [官方 DMG](https://www.mothersruin.com/software/SuspiciousPackage/get.html) 和 Homebrew cask `suspicious-package`，后者使用相同的官方版本化 DMG。cask 未声明 `auto_updates`。
- 自更新: [官方 FAQ](https://www.mothersruin.com/software/SuspiciousPackage/faq.html#auto-update) 说明，周期检查只读取版本 plist，发现新版后打开下载页；不会自动下载或安装 app。不是 Sparkle。
- [FAQ](https://www.mothersruin.com/software/SuspiciousPackage/faq.html#closed-source) 明确是闭源软件；同页 `#app-store` 明确没有 Mac App Store 分发。官网产品页、下载页及当前历史中未见产品终止公告。

## 覆盖矩阵

> ✓ = 已接入；— = 不适用。旧→新安装、生产检测与结构化日志均已验收，见下。

| Channel | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---------|---------|----------|-----|--------|-------------|
| stable | — | ✓（通用） | — | — | ✓ 一键 DMG |

直接下载的 app 由 **VendorProbe** 应答；Homebrew 实际拥有的副本优先由 `HomebrewCaskSource` 应答，继续遵守现有来源归属规则。仅在 cask 目录中存在同名 app 不会使直接下载副本被 Homebrew 接管。

## 覆盖清单与 Channel

| 副本组 | 身份 / 版本差异 | 处理与证据 |
|--------|------------------|------------|
| 1.x–2.x | 只有独立 Quick Look generator，没有 `.app` | [官方 FAQ `#requirements`](https://www.mothersruin.com/software/SuspiciousPackage/faq.html#requirements) 明确说明；不属于 app 扫描和替换对象，不新增旧 ID 迁移 |
| 3.0–3.5.x | 3.0 开始成为 app，内含旧 Quick Look generator | 3.0 真包为相同 bundle ID / Team，short `3.0`、build `152`、Intel executable。检测只读 bundle；支持的 Apple Silicon / macOS 15+ 主机可取得当前 universal app，不把旧包的 OS 下限作为当前主机的限制 |
| 3.6–4.6.2 | 改为嵌入式 Quick Look preview extension；旧系统保留版不是另一发布轨 | 4.3.3 真包为相同 ID / Team，short `4.3.3`、build `1065.5`、universal、最低 macOS 11；在 DuoUpdater 支持的主机上使用当前 stable 配方 |
| 4.7–当前 | 当前 stable，最低 macOS 14 | 4.7、4.8 真包同 ID / Team，分别 short `4.7` / `4.8`，build `1415` / `1457`，均 universal；当前最低 OS 从响应中读取 |
| 历史 4.5.1 Preview | 曾为 macOS 26 兼容测试版；[4.6 历史](https://www.mothersruin.com/software/SuspiciousPackage/relnotes.html) 说明它随后成为 4.6 | 2026-11-16 真实 GET `preview.html` 重定向到 `update.html`，现为 stable 4.8 下载页，未提供独立活动轨。历史 Preview 真包未取得，不能宣称已验证其渠道信号或一键升级，见已知问题 |
| 签名被修改的副本 | ID 可能相同，Team / seal 不再可信 | 检测不因签名跳过；一键复用现有签名和同 Team 闸，拒绝无法验证的副本，不放宽信任策略 |

3.0 是 [Release History](https://www.mothersruin.com/software/SuspiciousPackage/relnotes.html) 中注明的首个 app 版本。已核对的最早 app 和当前 app 没有 bundle ID 变化，不需要 `BundleIDMigration`。官方仍保留给旧 macOS 的 4.6.2、4.3.3、4.2.1、4.0、3.5.3、3.4.1、3.2 等包；这些 OS 都低于 DuoUpdater 的 macOS 15 主机下限，不需要按旧 OS 增加配方。

## 更新检测

- 端点: [SuspiciousPackageVersionInfo.plist](https://www.mothersruin.com/software/SuspiciousPackage/data/SuspiciousPackageVersionInfo.plist)，官方 FAQ 直接链接为 app 自己检查的文件。
- 单个 release 的 XML plist，先匹配准确的 `CFBundleIdentifier`，再读取 `CFBundleShortVersionString`。当前返回 `4.8`；`CFBundleVersion` 为独立 build 计数 `1457`，不参与版本比较或 DMG 文件名。
- `MRSUpdateRequiredOSVersion` 当前为 `14.0`，使用已有 `minimumSystemVersionPattern`，随厂商响应变化；不写死当前 OS 下限。
- 数字段必须完整结束于 `</string>`，不把 `4.9-beta` 截成 stable `4.9`；两段、三段和下一主版本均可读取。

## Changelog

- 来源: [官方 Release History](https://www.mothersruin.com/software/SuspiciousPackage/relnotes.html)，一行表格对应一个 release，版本、发布日期、列表正文在同一行。
- `vnum` 的营销版本与探针一致；其后括号内 build 不作为版本。按 `vnotes` 限定正文，并把嵌套 `<li>` 分开，避免父条目吞掉子条目。
- 2026-11-16 对原始响应运行相同正则，得到 37 个版本（4.8 → 1.0）。前两版分别为 4.8 / September 16, 2026 和 4.7 / August 5, 2026，提取 7 / 8 个列表条目（含展开后的子项）。
- 真实结构的离线 fixture 验证版本、日期、嵌套条目、HTML entity 和无关表格行。生产 `ChangelogService` 的 live 检查仍须由相同 checkout 的 CLI 补跑，不能用 fixture 代替。

## 一键安装

- 状态: **4.7→4.8 已在 macOS 27.2 Apple Silicon VM 完成停用及运行中两轮实际安装。**
- 使用现有 `.dmg` 路径，URL 为 `https://www.mothersruin.com/software/archives/SuspiciousPackage-{version}.dmg`，避免解析版本与固定 latest 下载内容不同步。
- 4.8 DMG 为 8,089,083 bytes，根目录只有一个待安装的 `Suspicious Package.app`。4.7、4.8 的 app seal 校验通过，`spctl` 均为 Notarized Developer ID，Team 均为 `936EB786NH`；3.0、4.3.3 同 Team，严格 seal 校验也通过。
- 当前 app 内含 `SuspiciousPackagePreviewExtension.appex`、`spkg` 和更新检查 XPC service。整包替换会一并交付这些内嵌组件；没有增加独立后台任务或安装脚本。
- [官方用户指南](https://www.mothersruin.com/software/SuspiciousPackage/use.html#cli) 要求 `spkg` 依赖 app 内资源，通过其实际路径或符号链接运行；本配方只更新 app，不为直接下载副本新增 shell 链接。
- `VendorInstaller` 继续执行代码签名、bundle ID 和同 Team 检查。下载页单独展示 SHA256，版本 plist 不含摘要；没有为了摘要另加一次运行时页面请求。

## 增量更新与已下载整包

官方 FAQ 明确自带检查不会下载或安装更新，因此没有自更新器预先停放的安装包可复用。此接入使用完整 DMG，不声明 delta 能力，也不增加 staged-update 查询。

## 夜扫覆盖

VendorProbe / Changelog registry 已被现有 verifier 自动枚举，不向 `AuditedUpdateFeeds` 添加重复记录：

- `vendor:com.mothersruin.SuspiciousPackageApp:stable`：当前 stable 检测；同 ID 的旧 app 副本共享这条端点。
- `changelog:com.mothersruin.SuspiciousPackageApp:-`：官方完整发布历史。
- `install:vendor:com.mothersruin.SuspiciousPackageApp:stable`：通过配方的 `.dmg` URL 检查下载内容及身份。`verify-install` 的 `recipeID` 为不带 `install:` 前缀的 vendor ID。

以下实际枚举检查均已命中：vendor 与 changelog 检查为 ok，安装字节读取 8,089,083 bytes、`ok 1 / skipped 0 / unresolved 0`。没有创建或替换既有 identity/baseline，首观不冒充连续性验证：

```sh
duo verify --only com.mothersruin.SuspiciousPackageApp
duo verify-install --only com.mothersruin.SuspiciousPackageApp --report /tmp/suspicious-package-install.json
```

使用本次变更 checkout 的 CLI 完成了上述检测、changelog 和安装字节检查，结果见[集中验收](../../verify/awesome-four-20261116/README.md)。历史 Preview 没有可枚举的独立现行公开轨，未声明该组的独立夜扫字节覆盖。

## 已知问题

- 历史 4.5.1 Preview 只有已结束的公开页面证据，未取得真实 bundle。当前 `preview.html` 指向厂商的 stable 后继版本；标准 `SuspiciousPackage-4.5.1.dmg` 存档 URL 返回 404。没有可验证的独立 Preview 端点或包，故不伪造 Preview 配方或信号。若取得该旧 bundle，先验证 scanner 实际读出的渠道和它自己的更新目的地；确认为 `.preview` 时，现有 stable 渠道闸不会回答，需为该组单独决定后继映射。没有旧 bundle 证据时不把它标成已覆盖。
- 两轮换包、版本回读、严格签名、公证、显式重启及合成偏好保留均通过；没有覆盖 Finder Quick Look 的内容预览、`spkg` 的完整命令集合或任意第三方 PKG 分析。

## 如何复验

1. 保存上述版本 plist 和 history 页的原始响应；运行 `SuspiciousPackageRecipeTests` 与 `RecipeGoldenTests`。
2. 只读挂载官方版本化 DMG，读取 app 的两个版本字段、bundle ID、最低 OS，运行 `codesign --verify --deep --strict` 与 `spctl --assess --type execute`；完成后卸载镜像。
3. 使用生产检查链验证 4.7 显示 4.8、4.8 显示已是最新，并确认结构化 release history。
4. 在隔离测试环境进行 4.7 → 4.8 真实一键安装，回读版本与签名；补录实际 live / nightly 输出。

## 历史与实测

2026-11-16：读取官方版本 plist、下载页、FAQ 和 Release History；营销版本 `4.8`、build `1457`、最低 macOS `14.0` 一致。原始 history 正则匹配 37 个 release，4.8 / 4.7 / 4.6.2 的列表条目数为 7 / 8 / 2。

同日只读检查官方 3.0、4.3.3、4.7、4.8 四个 DMG；bundle ID 均为 `com.mothersruin.SuspiciousPackageApp`，Team 均为 `936EB786NH`，严格 seal 校验均通过。3.0 的 `spctl` 为 Developer ID，其余三版为 Notarized Developer ID。初次包核对只做挂载和身份检查；后续实际安装另见集中验收。

同日集成验收：真实 4.7 显示 4.8、4.8 显示最新，生产 pane 返回 37 条结构化历史；4.2 内嵌列表后的 blockquote 说明也由回归 fixture 保留。运行中更新保留旧进程，随后 `duo restart` 切换为新版，签名与合成偏好复查通过。
