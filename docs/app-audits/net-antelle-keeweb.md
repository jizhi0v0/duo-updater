# KeeWeb

## 基本信息
- App: KeeWeb — 开源 KeePass（kdbx）密码管理器，Electron（1.18.7 内置 Electron Framework 12.0.7），MIT
- Bundle ID: `net.antelle.keeweb`
- 仓库: `keeweb/keeweb`（默认分支 `master`，未归档）
- Team ID: `3LE7JZ657W`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.18.7（tag `v1.18.7`，资产 `KeeWeb-1.18.7.mac.arm64.dmg`）；上一版 1.18.6；观测日期: 2026-10-26
- 维护状态: **最后一个稳定版、也是最后一个带 macOS 包的版本是 1.18.7（2021-07-18）**，五年多没有新的 Mac 构建。仓库 2026 年又有人提交（最后一次 push 2026-05-08），发了两个 prerelease：v1.18.8（2026-04-30，没有任何资产）、v1.18.9（2026-05-08，只有 Linux 和 html 包）。README、仓库描述里没有停止维护或终止日期的说法，所以不是 sunset，只记在已知问题
- 自更新机制: **自研更新器**（不是 Sparkle、不是 electron-updater、没有 `app-update.yml`）。settled from source: `app/scripts/comp/app/updater.js`、`desktop/scripts/update-installer.js`、`package/osx/installer.js` on `v1.18.7`。详见下文「自更新器」
- 分发: GitHub Releases（每版 arm64 dmg + x64 dmg，没有 universal）；Homebrew cask `keeweb`（1.18.7，`auto_updates`，url 是 arm64 dmg）；没有 App Store 版；官网 keeweb.info 的下载链接指向 GitHub `/releases/latest`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | —（`app.keeweb.info/update.json` 只给版本号和日期，GitHub 更全） |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。feed-discover: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v1.18.7 arm64: `net.antelle.keeweb`，Team 3LE7JZ657W，Notarized，arm64，`CFBundleVersion` `dfc6201`，`LSMinimumSystemVersion` 10.11.0
  - v1.18.7 x64: 同 id、同 Team、Notarized，x86_64。与 arm64 包的 `Info.plist` 完全相同、`app.asar` SHA-256 相同（`42ab608b…`），文件列表只差 V8 snapshot 和 6 个 `keeweb-native-modules/*-darwin-<arch>.node` 的架构后缀；designated requirement 相同（identifier + Team，不含 cdhash）。**只是架构不同，不是两个产品**
  - v1.18.6 arm64: 同 id、同 Team，版本与 tag 一致
  - v1.14.2（release 列表里最老的一版，`KeeWeb-1.14.2.mac.dmg`，x86_64 only）: 同 id、同 Team 3LE7JZ657W，Notarized，`LSMinimumSystemVersion` 10.10.0
  - 1.16.0 及更早只有一个 `KeeWeb-<v>.mac.dmg`（x86_64）；1.16.1 起分 `mac.arm64.dmg` / `mac.x64.dmg`
- 改名前的旧 bundle id: v1.0.0–v1.2.4（2016 年）的 Gruntfile 没有设 `app-bundle-id`，electron-packager 会给默认 id（推断为 `com.electron.keeweb`，**未验证**：这些 release 已删除，拿不到包）；v1.3.0 起 Gruntfile 写死 `net.antelle.keeweb`。这些 2016 年的副本没有签名（Gruntfile `sign: false`，没有 osx-sign），`BundleIDMigration` 不跨 Team、也不接受无 Team 的旧 id，所以不加；它们是 Electron 1.2 的 x86_64 构建，记为缺口
- 其他轨: 没有。release 列表 27 个 release 里只有 v1.18.8、v1.18.9 是 prerelease，都没有 macOS 资产；beta.keeweb.info 是网页版（`keeweb/beta.keeweb.info` 仓库只有 html），没有桌面 beta 构建
- 版本范围: 131 个 tag 里 130 个是 `v<数字>(.<数字>)+`，剩下一个是不带 `v` 的 `1.19.0`（没有对应 release）——`versionPattern` 用 `^v?…$`，下一版如果用这个 tag 也读得出；`-rc` 之类不匹配。release 只保留到 1.14.2，更早的已删除
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；KeeWeb `LSMinimumSystemVersion` 10.11，不需要 `hostRequirement`
- 架构: arm64 主机上，x64 副本（1.16.0 及更早只有 x64；1.16.1 起用户也可能装了 x64 包）会被一键换成 arm64 包。安装闸 5b 只拦"丢掉已有 arm64 片"，x64 → arm64 是放行的方向。KeeWeb 自己的更新器按运行进程的 `process.arch` 选包，x64 副本（Rosetta 下）会一直留在 x64；我们这里不同，这是有意的
- 1.16.0 及更早的副本（asar 更新器）: 那一代的更新器只下载 `UpdateDesktop.zip` 里的 `app.asar` 放到 userData，启动脚本 `desktop/main.js` 发现 userData 里的版本更高就加载它（settled from source: `desktop/main.js` on `v1.14.2`、`v1.16.0`）。所以这类副本的 `Info.plist` 版本可能低于实际运行的 app 版本（最高到 1.16.0）。对检测无害：它们都低于 1.18.7，行上显示 bundle 版本 → 1.18.7。1.18.7 的 `desktop/main.js` 不再读 userData 里的 `app.asar`，一键后旧 asar 留在 userData 但不会被加载

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.antelle.keeweb` | — | — | GitHub `/releases/latest` | ✓ |

没有 beta / nightly 桌面轨（见覆盖清单）。

## 更新检测
- 源: `keeweb/keeweb` GitHub Releases，`/releases/latest`（2026-10-26 返回 v1.18.7，2021-07-18T14:53:06Z）
- 版本方案: tag `v1.18.7` → `CFBundleShortVersionString` `1.18.7`、`CFBundleVersion` `dfc6201`（commit 短哈希，只比 short version）
- `versionPattern` `^v?([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^KeeWeb-[0-9]+(?:\.[0-9]+)+\.mac\.arm64\.dmg$`。同一个 release 里另外的安装包是 `mac.x64.dmg`、Windows exe/zip、Linux AppImage/snap/deb/rpm/zip 和网页版 `html.zip`，都不匹配
- 厂商自己的版本端点 `https://app.keeweb.info/update.json` 2026-10-26 返回 `{"version": "1.18.7", "date": "2021-07-18"}`，与 GitHub 一致

## 自更新器

settled from source（`v1.18.7`）:
- 检查: `Updater.check` 读 `Links.UpdateJson` = `https://app.keeweb.info/update.json`，24 h 一次（首次启动约 0.5 s 后）。设置项 `autoUpdate` 默认 `"install"`
- 下载: 版本更新时自动下载 `https://github.com/keeweb/keeweb/releases/download/v<ver>/KeeWeb-<ver>.mac.<process.arch>.dmg` 到 `$TMPDIR/KeeWeb/`（Electron `app.getPath('temp')` 下的 `KeeWeb` 目录），再下 `Verify.sign.sha256` 存为同名 `.sign`，用 app 内置公钥验签名；不通过就删
- 安装: **只在用户点「Restart and update」时**（`installAndRestart` → `requestRestartAndUpdate` → 主进程 `update-installer.js`）。把 `Contents/Installer/KeeWeb Installer.app`（JXA applet）拷到 `$TMPDIR/KeeWeb/`，带 `--update --wait-pid --dmg --app` 启动后退出 KeeWeb。applet 等进程退出（10 s 后 `kill`），`hdiutil attach` dmg，`rm -rf` 目标 app，`cp -pR` 新 app 进去，`open` 它。目标是 root 拥有或不可写时用 `with administrator privileges` 跑，并 `chown -R 0` 回去
- 抢跑风险: 低。它不会自己换包；用户在 duo 装完 1.18.7 后再点它的「Restart and update」，换进来的也是同一个 1.18.7。下载到一半时 duo 换了包，KeeWeb 下次启动读到自己已是 1.18.7，不再下载

## 按架构 / 按 OS 分轨
- 1.16.1 起每版两个 dmg：`mac.arm64.dmg`（arm64）、`mac.x64.dmg`（x86_64），没有 universal。我们只取 arm64（DuoUpdater 只跑在 Apple silicon 上）
- `LSMinimumSystemVersion` 10.11.0（1.18.7）；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（1.16.1 起） | 无 | — |
| 证据 | 1.18.7 `updater.js` 只下整个 dmg。1.16.0 及更早下的是 `UpdateDesktop.zip`（只含 `app.asar`），那是"只换 JS 层"，不是二进制补丁 | 1.18.7 release 资产里没有 `UpdateDesktop.zip`，也没有 patch 文件 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（自动下载，等用户点安装） | 2026-10-26 运行中一轮（约 1 分钟）没看到 `$TMPDIR/KeeWeb/` 出现 | ○（`SelfUpdaterStash` 没有这个布局） |
| 证据 | 目录 `$TMPDIR/KeeWeb/`；文件 `KeeWeb-<ver>.mac.<arch>.dmg` + `KeeWeb-<ver>.mac.<arch>.dmg.sign`（整份 `Verify.sign.sha256` 文本，RSA 签名，不是摘要）。没有完成记录：`transport.js` 直接写到最终文件名，`UpdateModel.save` 把 `update*` 字段（含 `updateStatus: 'ready'`）剔掉不落盘；下到一半的文件与完整文件只能靠核对 release 的 `Verify.sha256` 区分 | — | 要用就得新加一个布局：按文件名取版本，用 release 的 `Verify.sha256`（hex SHA-256，已核与真包一致）校验整包。没做 |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 1.18.6 起）: `source structured: 1 entries; newest 1.18.7: 6 items, headings []; first items ["`+` added Microsoft Teams storage", "`+` added a possibility to override tena", "`!` disabled automatic installation of K"]`
- 结构化，没有标题可保留：正文本来就没有标题，也没有列表符号，每行是一条，用反引号里的 `+`（新增）/ `!`（改动）/ `-`（修复）开头。5 条改动 + 1 条末尾的捐款行 = 6 条（捐款行混进了条目）
- 从 1.14.2 起也只有 1 条：stable rule 只读 `/releases/latest` 一个对象，这是 `GitHubReleasesSource` 的设计
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（arm64 dmg，任何架构的已装副本）
- 端到端（2026-10-26，本分支 `make cli` 的 duo；**只做了第一轮**）:
  - 第一轮（不运行）: 1.18.6 → `duo install` → 1.18.7，Team `3LE7JZ657W`（没有 GitHub digest）✓；bundle 属主仍是 `bobby:staff`（没有被改成 root）
  - 第二轮（运行中，用户在场）: 1.18.6 运行中 → `duo install` 就地换包、"Still running the old code" → `duo restart KeeWeb` → "restarted"，新进程跑 1.18.7、Team 3LE7JZ657W、`codesign` 0 ✓。bundle 全程是用户所有（`bobby:staff`）：1.18.6 启动时要求 root 的那次授权没有生效，1.18.7 重启后 3 s `KeeWeb Installer.app/Contents/MacOS/applet --install` 又弹「Allow administrator access for "KeeWeb Installer"」，用户处理后 bundle 仍是 `bobby:staff`。所以这轮测的是用户所有的 bundle；root 拥有的副本走提权换包没测（要先把旧版放进 root 拥有的目录，需要管理员）
  - 终态: 1.18.7，从没启动过
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `KeeWeb.app` + `Applications` 软链 + `.background`、`.VolumeIcon.icns`
- 嵌套: `Contents/Frameworks/KeeWeb Helper*.app`（Electron 的 GPU/Plugin/Renderer helper，随主进程起落）；`Contents/Installer/KeeWeb Installer.app`（上面说的 JXA 安装 applet，只在更新或首启权限修复时被调用，不常驻）；`Contents/MacOS/util/keeweb-native-messaging-host`（arm64，Team 3LE7JZ657W）。没有 LoginItems、LaunchAgent、`SMAppService`
- 浏览器 native messaging: 用户在设置里开浏览器集成后，KeeWeb 往 `~/Library/Application Support/{Google/Chrome,Mozilla,Microsoft Edge}/NativeMessagingHosts/` 写 `net.antelle.keeweb.keeweb_connect.json`（以及 KeePassXC-Browser 兼容的 `org.keepassxc.keepassxc_browser.json`），`path` 是 bundle 内的绝对路径 `…/KeeWeb.app/Contents/MacOS/util/keeweb-native-messaging-host`（`desktop/scripts/util/browser-extension-installer.js`）。原地换包后这个路径仍然有效，指向新版。host 由浏览器拉起，连 `~/Library/Group Containers/3LE7JZ657W.keeweb/conn.sock`，KeeWeb 退出、socket EOF 时它自己退出（`keeweb-connect` 仓库 `native-messaging-host/src/native-messaging-host.cpp` 的 `close_keeweb_pipe` / `quit_on_error`）。所以换包后不会有指向旧代码的常驻 host（读源码得出，未在真机上看）
- root 拥有的 bundle: KeeWeb 从 `/Applications/KeeWeb.app` 启动时，若 bundle 不是 uid 0，会弹窗说明并立刻跑 `KeeWeb Installer.app --install`，用管理员权限 `chown -R 0 /Applications/KeeWeb.app`（`AppRightsChecker`，app.asar 里读到；cask 的 `uninstall_preflight set_ownership` 也是为这个）。所以很多副本是 root 拥有的：`InPlaceSwap` 走提权路径（会要管理员密码），并按原 bundle 的 uid:gid `chown -R`，换完仍是 root 拥有，KeeWeb 不会再弹这个框
- 签名: 1.14.2、1.18.6、1.18.7（arm64 与 x64）都是 Team `3LE7JZ657W`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产没有 `digest`（2021 年上传）。release 自带 `Verify.sha256`：`KeeWeb-1.18.7.mac.arm64.dmg` 为 `6e4870b1660b91e735eaf30e7d751c7bb8dfae623d5b6c47899bd4d5ab1e6cae`，与下载文件 `shasum -a 256` 相同，大小 85807370 字节等于资产大小。GitHubReleaseRule 没有读校验文件的字段，没接
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；KeeWeb 自己的更新器读的 `update.json` 也是这一版）
- 阻塞: 无
- 真机前的注意点（来自源码 / 包内容，均未在真机上观察；第二轮没做，见上面的端到端）:
  - 首启若 bundle 不是 root 拥有，会弹「app rights」提示并立刻要管理员密码（`chown -R root`）。可以点不再询问（`skipFolderRightsWarning`）或取消；取消后 bundle 保持用户拥有
  - 首启约 0.5 s 后检查更新，1.18.6 会自动把 1.18.7 dmg 下到 `$TMPDIR/KeeWeb/`（约 86 MB）+ `.sign`；装完要提示「Restart and update」，不要点
  - 首启会建 `~/Library/Group Containers/3LE7JZ657W.keeweb/`（`conn.sock`，推断）和 `~/Library/Application Support/KeeWeb/`
  - Info.plist 声明 `kdbx` 文档类型（Editor，未写 `LSHandlerRank`），没有 URL scheme
  - 没有登录项、LaunchAgent、root helper
  - 1.18.7 是 Electron 12（2021 年），在当前 macOS 上能否正常启动没验证

## 已知问题
- 项目事实上停在 1.18.7：五年没有新的 Mac 构建。2026 年的 prerelease 是新维护者发的，没有 macOS 包；仓库里的 `build-run.yaml` 仍有 darwin 任务（用 `APPLE_CERTIFICATE` 等 secrets 签名），将来若出 Mac 包，Team 是否还是 3LE7JZ657W 不知道——换了 Team 的话所有旧副本的一键会被 Team 闸拒（检测不受影响）
- 2016 年 v1.0.0–v1.2.4 的副本（无签名、推断 id `com.electron.keeweb`）不检测，见覆盖清单
- changelog 末尾的捐款行被当成一条更新条目

## 如何复验
```bash
gh release view v1.18.7 -R keeweb/keeweb --json assets -q '.assets[]|select(.name|test("mac"))|.name+" "+(.size|tostring)'
gh release download v1.18.7 -R keeweb/keeweb -p 'KeeWeb-1.18.7.mac.arm64.dmg'
gh release download v1.18.6 -R keeweb/keeweb -p 'KeeWeb-1.18.6.mac.arm64.dmg'
gh release download v1.18.7 -R keeweb/keeweb -p 'Verify.sha256' -O - | grep mac     # 与 shasum -a 256 对
.claude/skills/coverage-discovery/scripts/check-bundle.sh KeeWeb-1.18.6.mac.arm64.dmg   # net.antelle.keeweb, Team 3LE7JZ657W, Notarized
swift run --package-path application-test feed-discover KeeWeb-1.18.7.mac.arm64.dmg     # no Sparkle / electron-builder / MyGo
swift run --package-path application-test channel-verify KeeWeb-1.18.6.mac.arm64.dmg --expect stable   # GitHub, UPDATE → 1.18.7
swift run --package-path application-test channel-verify KeeWeb-1.18.7.mac.arm64.dmg --expect stable   # up to date
curl -sS https://app.keeweb.info/update.json      # KeeWeb 自己的检查端点
```

channel-verify 原始输出（2026-10-26）:
```
1.18.6 arm64 dmg:
    detected channel  → stable
    winning source  GitHub
    latest          1.18.7
    download        https://github.com/keeweb/keeweb/releases/download/v1.18.7/KeeWeb-1.18.7.mac.arm64.dmg
    changelog pane  source structured: 1 entries; newest 1.18.7: 6 items, headings []; first items ["`+` added Microsoft Teams storage", "`+` added a possibility to override tena", "`!` disabled automatic installation of K"]
    status          UPDATE → 1.18.7
1.18.7 arm64 dmg:
    winning source  GitHub
    latest          1.18.7
    status          up to date
1.14.2 x86_64 dmg (KeeWeb-1.14.2.mac.dmg):
    winning source  GitHub
    latest          1.18.7
    status          UPDATE → 1.18.7
```

## 建议下一步
1. 两轮已做（2026-10-26，见「一键安装」，用户所有的 bundle）；root 拥有的副本走提权换包、换完是否仍是 root 拥有，还没在真机上看
2. 若厂商恢复发 Mac 包，复核 Team ID 和资产名
