# TablePlus

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel，header-keyed ChannelBinding + Changelog**

## 基本信息
- Bundle ID: `com.tinyapp.TablePlus`（两 channel **共用**；CFPreferences 域小写 `com.tinyapp.tableplus`）
- 自更新机制: Sparkle（单一 feed URL；server 根据请求 header 返回 stable 或 beta 内容）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(header-keyed) | ✗(auto) | — | — | — |
| **beta**     | ✓(header-keyed) | —       | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 注入 HTTP header）

## Channel 详情（Pattern B-variant — 共享 bundle id，header 切换，无 `<sparkle:channel>` 标签）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.tinyapp.TablePlus` | 共享 | `ViewSetting[IsReceiveBetaBuild] = false` | 无额外 header（server 默认返回 stable） | ✓ |
| beta    | `com.tinyapp.TablePlus` | 共享 | `ViewSetting[IsReceiveBetaBuild] = true`  | header `X-Tiny-Beta-Update: true` | ✓ |

`TablePlusChannel.resolveCurrent()` 读 `CFPreferencesCopyAppValue("ViewSetting", "com.tinyapp.tableplus")` → `[String: Any]` → `IsReceiveBetaBuild` Bool。header 值字符串 `"true"` 是 TablePlus 实际发送的形式（非布尔 JSON）。

CFPreferences 强制 sync（`CFPreferencesAppSynchronize`）避免长时间运行的菜单栏 app 读到 stale 值。

## Changelog
- ChangelogRecipe ✓（`tableplus.com/osx/changelog`，Jekyll blog post 结构；bundleID `com.tinyapp.tableplus` 小写）

## 一键安装
- Sparkle 自更新

## 订阅门槛（2026-10-17）
- TablePlus 是一年更新授权：发布时间晚于授权更新截止日的版本激活不了。规则出自 TablePlus 27.1.0 (821) 二进制里的文案（`strings`）：「This version of TablePlus was released after the license's updates ended.」「TablePlus %@ came out after them, so the key can't activate it. Renew the license for this build, or download the last build it covers.」——比的是**发布日期**和 `TBLicenseModel.updatesAvailableUntil`。
- 它的 `bestValidUpdateInAppcast:forUpdater:`（`UpdaterDelegate`，arm64 反汇编）按**构建号**封顶：把一个整数上限转成字符串，用 `SUStandardVersionComparator` 和条目 `versionString` 比，只留 ≤ 上限的最高条目。这个上限对应文案「Updates are approved by the license owner up to build %@.」（团队授权管理员批准），不是到期，本次未接入。
- 截止日在本机只出现在 TablePlus 自己的 URL 缓存 `~/Library/Caches/com.tinyapp.TablePlus/Cache.db`：定期的 `GET tableplus.com/v1/licenses/devices` 响应 `Data.UpdatesAvailableUntilString`（如 `"6 June 2027"`），过期后照样返回（本机 3–5 月缓存为 `"4 May 2026"`，6 月续订后变 `"6 June 2027"`）。`.licensemac` 是加密的，请求带 `X-Tiny-License-Sign` 签名，二者都不读也不重放。
- 实现：`TablePlusSubscription` 拷贝 Cache.db（含 -wal/-shm）后只读查询最新一条 devices 响应，截止日按 UTC 当天零点；feed `<pubDate>` 是 RFC 822，早于该时刻才覆盖——**截止日当天发布的版本也拦**（TablePlus 是否算当天未确认，取保守）。只读日的 pubDate 按当天结束算。缓存缺失/被清/格式变 → 不提供更新版本，用户可在 TablePlus 里更新。UI 与 Surge 相同（动作列锁），日期只显示到天。Setapp 版（`com.tinyapp.TablePlus-setapp`）不受此门槛。
- 续订：TablePlus 启动/退出、回到 DuoUpdater 窗口时按指纹重检（指纹含窗口）；没有给 Cache.db 加文件监听（它一直在写）。
- 真机 2026-10-17：读出 `before(2027-06-06 00:00 UTC)`；`duo check` 照常报 27.1.0 (821) → 27.1.0 (827)（827 发布于 2026-10-16，在窗口内）。

## 已知问题
- Bundle id 大小写：CFBundleIdentifier 为 `com.tinyapp.TablePlus`（大写 P），但 CFPreferences 域用小写 `com.tinyapp.tableplus`；`ChannelBinding.resolve` 做小写化比对避免大小写漏匹配

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`，bundle id 大小写 `com.tinyapp.TablePlus`，匹配大小写不敏感）。`ViewSetting.IsReceiveBetaBuild=1` 时判定为 **beta**；带 header `X-Tiny-Beta-Update: true` 取到 7.1.1/711，无 header 取到 7.1.0/710（机制成立）。VendorProbe 故意无应答（机制是 header-keyed Sparkle）。**stable 也已在真实 bundle 上验证**（嵌套键 `IsReceiveBetaBuild=false` 时 `--scan` 结果=stable；改动前后整域快照比对一致，无需退出 TablePlus）。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan com.tinyapp.TablePlus --expect beta
```

## 端点

- 版本端点：`https://tableplus.com/osx/version.xml`（同一 URL 按请求头返回 stable 或 beta 构建）。
