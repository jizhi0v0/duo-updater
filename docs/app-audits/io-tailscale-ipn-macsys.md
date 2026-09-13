# Tailscale

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable 完整（检测+一键+Changelog）；unstable/rc 轨道未覆盖**

## 基本信息
- Bundle ID: `io.tailscale.ipn.macsys`
- 自更新机制: **Sparkle 2**（`Contents/Frameworks/Sparkle.framework`，`SUEnableInstallerLauncherService = true`）。feed 地址写在二进制里：`pkgs.tailscale.com/{stable,release-candidate,unstable}/appcast.xml`，enclosure 是 `Tailscale-<ver>-macos.zip`（不是 pkg）。app 内含 network system extension。（2026-09-13 补；原先这里写的「通过系统 pkg 更新」是我们一键走的路线，不是它自己的）
- Team ID: `W5364U7YZB`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **unstable** | —       | —        | —   | —      | ○           |

当前生效源: **VendorProbe**（stable 端点 `pkgs.tailscale.com/stable/`）

## Channel 详情

| Channel  | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|----------|-----------|----------|---------|------|
| stable   | `io.tailscale.ipn.macsys` | — | — | ✓ |
| unstable | `io.tailscale.ipn.macsys` | 共享(推测) | — | ○ 可加（端点 `pkgs.tailscale.com/unstable/`）|

## 更新检测
- stable: `https://pkgs.tailscale.com/stable/?mode=json` → `"MacZipsVersion":"X.Y.Z"`
  - 顶层 `Version` 是 Linux/Windows 版本（不同方案，不用！）
  - install URL 从 `"universal-package":"Tailscale-<ver>-<hash>.pkg"` 拼出，base `pkgs.tailscale.com/stable/`

## Changelog
- ChangelogRecipe ✓（`tailscale.com/changelog`）

## 一键安装
- ✓ pkg，Team W5364U7YZB

## 与它自己的 Sparkle 冲突（2026-09-13，mac mini 实测）

- **mini 上这份 bundle 是 `root:wheel`**（由 pkg 安装；归属是实测，「因为 pkg」是推断），于是 Tailscale 的 Sparkle 更新要管理员授权：安装器提交到系统域、`Autoupdate` **以 root 运行**，暂存在 `/var/root/Library/Caches/io.tailscale.ipn.macsys/org.sparkle-project.Sparkle/Installation/<rand>/<rand>/Tailscale.app`（用 `sudo` 看到的）。它的进度程序 `Updater` 仍以用户运行、在 `~/Library/Caches/io.tailscale.ipn.macsys/org.sparkle-project.Sparkle/Launcher/<rand>/`。用户缓存里没有 `Installation/`。
- 触发方式：About 页点「1.102.4 available」→ 输密码 → 停在「Restart to update」即为上膛。点「Restart to update」会立即安装。
- **我们的 pkg 在上膛时装会撞车**：pkg 的 `preinstall` 自己会 `Asking io.tailscale.ipn.macsys to quit`，这正是 root `Autoupdate` 等的信号。实测 15:04:13 preinstall 请求退出 → 15:04:14 bundle inode 变化、Autoupdate 退出（它把暂存那份换进来了）→ PackageKit 报 156 条 `st_dev/st_ino mismatch (possible TOCTOU swap)`，并把 Sparkle.framework / 分享扩展 / 登录项 / network-extension 四个嵌套 bundle shove 进 Sparkle 那份 → 15:04:21 回执 1.102.4、"Installed"。同版本所以签名校验通过，**版本不同时会是混版本 bundle**。
- **同日 16:08 复现第二次，结果更坏**：上膛（16:08:18）后用命令行 `sudo installer -pkg Tailscale-1.102.3-macos.pkg` 装旧版（与 Duo 无关）→ 16:08:23 Sparkle 把 1.102.4 换进来、PackageKit 再报 TOCTOU → pkg 把 1.102.3 写进这份 bundle。之后 `codesign --verify --deep --strict` **失败**（`file modified` 落在 network-extension 的 `Info.plist` 和可执行文件上），`Info.plist` 说 101.102.3 而 `Tailscale version` 说 1.102.4。所以撞车与安装器是谁无关，任何 pkg 安装都会；后果可以是**签名损坏的混版本 bundle**。在 Duo 里点 Relaunch 让 Sparkle 整包换入后恢复：签名 valid，app 与扩展均 101.102.4，`systemextensionsctl` 里 1.102.4 为 activated enabled。
- 修法：`SelfUpdaterStaging.sparkleInstallerArmedWithUnreadableStaging` —— parked `Updater` 在、但读不到暂存的 `.app` 时，行给 Relaunch（版本未知），App 与 `duo install` 都拒绝安装。判据用户态可取；以用户身份读 root 进程：argv 读不到（`KERN_PROCARGS2` 报 EINVAL，在开发机的其他 root 进程上量的），uid 读不到（`proc_pidinfo` 对那个 root `Autoupdate` 报 EPERM），`proc_pidpath` 能读到。判据没用这三者。

## 建议下一步
1. 如需 unstable 支持：端点 `https://pkgs.tailscale.com/unstable/?mode=json` → 同 pattern；bundle id 需确认是否独立（如独立则 Pattern A，如共享则需 channel 检测信号）
2. 若 unstable 共享同一 bundle id，需有偏好/版本信号可区分（暂无确认信息）

## channel-verify 状态
- ✓ **stable 已验证 2026-06-04**（`--scan`，对真实 `io.tailscale.ipn.macsys` bundle 1.98.5/101.98.5）。VendorProbe 应答 1.98.5=installed，无幽灵更新。`unstable` 轨无 recipe、不在范围。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan io.tailscale.ipn.macsys --expect stable
```
