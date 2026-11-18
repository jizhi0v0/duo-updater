# UURemote（网易UU远程）

**这不是完整审计**：本文记录 UURemote（`com.netease.uuremote`）的本机手动更新缓存、PKG 实测和早期 recipe 历史。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-netease-uuremote.swift — stable VendorProbe（Homebrew cask 为什么接不住）

转引自 recipe 注释，未复测。唯一的改写：末句一处本机状态措辞（那份拷贝的安装来源），按本目录的机器状态规则改成了针对写这句话时那台机器的说法。代码里同一处（类别：那份拷贝的安装来源）改写成了不点名任何一台机器的条件：cask 接不住直接从厂商装的拷贝。

The Homebrew cask can't cover this: its provenance gate (correctly) only
adopts apps brew actually installed, and the copy on the machine this was written on had been installed directly.

### Recipes/com-netease-uuremote.swift — stable VendorProbe（一键 pkg 与 changelog 页）

转引自 recipe 注释，未复测。整段原文，代码里留下的是 `.pkg` 交给系统安装器那几句，以及「2026-08-22 检查时没找到 changelog 页」这个结论。

One-click verified 2026-08-09 on the 4.35.0 package: `pkgutil
--check-signature` reports "Developer ID Installer: Hangzhou Bobo
Technology Co Ltd (PU9BNSBJW7)" — the same team as the installed bundle —
notarized, with a trusted timestamp. A `.pkg` hands off to macOS's own
installer, so the user still confirms it there (same flow as ToDesk and
AweSun); the install spec re-resolves the redirect at download time so it
always fetches the current package, not this version's.
No `changelogURL`: there is no such page. `uuyc.163.com/changelog` and
`/update` both answer 200, but they return byte-identical content to a
path that does not exist — an SPA catch-all serving the homepage, not a
changelog. The download page is a distinct page but contains no
更新日志/更新说明/新增/修复 markers at all. (Checked 2026-08-22.)

## 本机手动更新缓存

- 直装稳定版，Apple Silicon，Bundle ID `com.netease.uuremote`。实测路径为 `/Applications/UURemote.app`。同一应用的 Homebrew 管理副本仍优先走 Homebrew 的现有来源顺序。
- 4.47.0（631）清空缓存后重开只写入 4.47.0/build 0。点击客户端「检查更新」后，MMKV 的 `downloaded_package_manualUpdate` 写入同一份 4.48.0（632）版本、说明和 CDN PKG 地址。重启保留手动记录。缓存是追加写入，文件修改时间可能不变。
- Duo 继续用官网重定向检测版本。安装时读取手动记录和配套 CRC。缓存记录与远端同版、构建号比已装更新且链接仍有效时，优先使用缓存中的 CDN 地址。两次实测链接的 `key2` 都是检查时间加 12 小时的十六进制 Unix 秒。更新记录由 UU 客户端刷新。
- Duo 复用 PKG 的签名、目标位置和 helper 检查，并在交接前从首选包的目标应用 `Info.plist` 核对 Bundle ID、短版本和构建号。缓存缺失、不同版、失效，或首选 PKG 下载和初检失败时，Duo 走原来的官网安装地址。
- 若首选包已交给 macOS Installer，Duo 记住已验证包的 SHA-256。再次打开已下载的包时会复查指纹和常规 PKG 校验。
- 缓存地址下载的 4.48.0 PKG 实测匹配回包 MD5，Developer ID Installer 团队为 `PU9BNSBJW7`，Apple 公证可信，目标为 `/Applications/UURemote.app`，`RestartAction` 为 `None`。

## 官网灰度回退

[#2084](https://github.com/jizhi0v0/duo-updater/issues/2084) 记录官网入口
从 4.48.0 回到 4.47.0。同日已装 UU 的手动检查仍返回 4.48.0。官网版本、
安装器和架构监控继续由原 recipe 提供。

## VM 验证

在 macOS 27.2 Apple Silicon VM 中，用早期只读本机缓存的测试构建验证了安装路径。
直装 4.47.0（631）只有占位缓存时
`duo check` 返回 `unknown`。加入从真实手动检查记录提取并脱敏的单条报价后，
同一命令返回 4.48.0 和 `installer` 路线。签名构建的更新按钮下载官方 PKG，
macOS Installer 完成升级，装后为 4.48.0（632），严格签名检查通过，复查显示
`up-to-date`。VM 本轮使用复制的报价，未独立获得 4.48.0 灰度。

该 VM 在测试前已出现 helper 的 launchd `EX_CONFIG`。重启 helper 和重新启用
后台项目后仍不可用，因此本轮实测覆盖系统 Installer 回退。Duo 的 helper
信任绑定、PKG 目标和重启要求已核对。该版本的 helper 执行尚未在 VM 实测。

## 本机 helper 验证

2026-11-18 在 macOS 27.3（26C5047e）Apple Silicon 本机，以基于
`08439545` 的早期 Developer ID 签名构建读取 UU 自己写入的手动报价。用户点
Duo 的「更新」后，观察到以 root 运行的 `DuoUpdaterHelper` 启动了同为
root 的 `/usr/sbin/installer`，系统安装目标为 `/Applications/UURemote.app`。
装机版本从 4.47.0（631）变为 4.48.0（632），严格签名检查通过，Team ID
为 `PU9BNSBJW7`，Duo 复查显示 `up-to-date`。本轮未出现图形 Installer。
