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

## 已知问题
- Bundle id 大小写：CFBundleIdentifier 为 `com.tinyapp.TablePlus`（大写 P），但 CFPreferences 域用小写 `com.tinyapp.tableplus`；`ChannelBinding.resolve` 做小写化比对避免大小写漏匹配

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`，bundle id 大小写 `com.tinyapp.TablePlus`，匹配大小写不敏感）。`ViewSetting.IsReceiveBetaBuild=1` → 本机在 **beta**；带 header `X-Tiny-Beta-Update: true` 取到 7.1.1/711，无 header 取到 7.1.0/710（机制成立）。VendorProbe 故意无应答（机制是 header-keyed Sparkle）。**stable 也已本机验证**（快照整域→翻嵌套 `IsReceiveBetaBuild=false`→`--scan`=stable→导回快照还原，TablePlus 未退出）。证据：`application-test/records/com-tinyapp-tableplus.md`
