# Fork

> 审计日期 2026-06-04 · 复审 2026-09-07 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel，ChannelBinding + Changelog，Sparkle feed-swap**
>
> ⚠️ **2026-09-07 更正**：`applicationUpdateChannel` 的映射原来写反了（写的 2→stable，实际 **1→stable、2→Develop**）。后果和复验方法见下文「2026-09-07：映射写反」。

## 基本信息
- Bundle ID: `com.DanPristupov.Fork`（两 channel **共用**同一 bundle id）
- 自更新机制: Sparkle（两 channel 各自 feed，Info.plist `SUFeedURL` 永远指向 Developer/beta feed）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(feed-swap) | ✗(auto) | — | — | — |
| **beta**     | ✓(feed-swap) | ✗(auto) | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 提供 feedOverride）

## Channel 详情（Pattern B — 共享 bundle id，偏好切换 feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.DanPristupov.Fork` | 共享 | `applicationUpdateChannel` pref = **1** | feed-swap → `fork.dev/update/feed-stable.xml` | ✓ |
| beta    | `com.DanPristupov.Fork` | 共享 | pref ≠ 1（**2 = Develop 菜单项写的值**；unset 也是 Develop） | feed-swap → `fork.dev/update/feed.xml` | ✓ |

Fork 命名反直觉：UI 称"Develop"为 beta 轨道（shipped default），"Stable (delayed 1 week)"为 stable。
`applicationUpdateChannel = 1` → stable；**2 / unset / 其他** → beta（Develop）。
Fork 的选择逻辑是对 1 的单次比较，不是枚举，所以我们也照着比 1、其余全落 Develop。

## 更新检测
- `ForkChannel.resolveCurrent()` 读 `CFPreferencesCopyAppValue("applicationUpdateChannel", "com.DanPristupov.Fork")` → Int
- `ChannelBinding.resolve()` 返回 `ResolvedChannel(channel:, feedOverride:)`
- `SparkleAppcastSource` 使用 feedOverride 替换 plist `SUFeedURL`

## Changelog
- ChangelogRecipe ✓（`fork.dev/releasenotes`，`<h4 class="header4 release-notes">Fork <version></h4>` 结构）
- 仅一个 recipe，不分 channel（stable 和 beta 的 release notes 在同一页按版本降序）

## 一键安装
- Sparkle 自更新（stable/beta 各自 feed 带 `<enclosure>`），duo-updater 不额外覆盖安装

## 2026-09-07：映射写反

**现象**：用户 Fork 2.69.0，Fork 自己的 Sparkle 弹窗提示 2.70.0，DuoUpdater 一声不吭。

**根因**：`applicationUpdateChannel = 2`（Fork 的 Updates 面板显示 "Develop"）。我们把 2 读成
stable，于是把这台机器重定向到 `feed-stable.xml`；那份 feed 的 head 是 **2.66.7**，比装着的
2.69.0 还旧。**"比装着的还旧"渲染成"已是最新"，不是错误**，所以整条链路全绿、2.70.0 从不出现。

**原验证为什么没抓到**：`channel-verify --scan` 跑的是**我们自己的** `detect()`。把 pref 设成 2、
看我们答 "stable"，证明的只是我们自我一致——`f(X) == f(X)`。它对"Fork 认为 2 是什么"一无所知。
这正是 CLAUDE.md 里那条「先核 issue／别把自己的实现当证人」的形状。

**这次的证据（读 Fork 2.69.0 arm64 slice，不是读我们的 Swift）**：

```
# feed 选择，0x1002156fc
bl   -[NSUserDefaults integerForKey:]   # "applicationUpdateChannel" -> x21
cmp  x21, #0x1
csel x20, <…/feed-stable.xml>, <…/feed.xml>, eq

# 两个写入点，各是一条 setInteger:forKey: 的立即数
enableStableChannel(_:)   0x10030e888   mov w2, #0x1
enableDevelopChannel(_:)  0x10030e774   mov w2, #0x2
```

复现命令（只读，不动 Fork 的偏好）：

```
lipo -thin arm64 /Applications/Fork.app/Contents/MacOS/Fork -output /tmp/Fork.arm64
otool -tV /tmp/Fork.arm64 | sed -n '/00000001002156dc/,/0000000100215708/p'
```

**旁证（各自独立）**：`defaults read com.DanPristupov.Fork applicationUpdateChannel` = 2，
而 Fork 自己的 Updates 面板把它显示成 "Develop"；同一台机器上 Fork 弹出的是 2.70.0，
而 2.70.0 **只存在于** `feed.xml`。

**留下的坑**：`feed-stable.xml` 的 head 长期停在 2.66.7（`Last-Modified` 却是最近的），
所以任何真的切到 Stable 的 Fork 用户，在我们这里都会看到"已是最新"。这是厂商行为，
不是我们的 bug，但下一个人看到"stable 无更新"时先查这个。

## channel-verify 状态
- ⚠️ **2026-06-04 那次的 stable 一半是无效的**（见上）。`--scan` 能验"这台机器当前解析到哪个
  channel"，**不能**验"pref 的数值语义"——后者只能读 Fork 的二进制或在 Fork UI 里切一次再读
  `defaults`。
- ✓ beta/Develop 侧仍然有效：`applicationUpdateChannel` 未设或为 2 时走 **Develop/beta**。
  VendorProbe 故意无应答（机制是 Sparkle feed-swap）。
  ⚠️ 2026-06-04 那条写的是「feed head 与 installed 一致（2.67.0）」——**那是当天的观测，不是判据**。
  2026-09-07 实测 head=2.70.0、installed=2.69.0，正好相反。判据是「解析到哪个 channel」，
  不是「head 等不等于 installed」；后者只说明那天厂商没发新版。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan com.DanPristupov.Fork --expect beta
```
