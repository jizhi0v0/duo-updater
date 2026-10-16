# Charles

HTTP/HTTPS 调试代理（XK72 Ltd）。Java 应用（包内自带 JDK 25），没有 Sparkle。
app 自己的「检查更新」只提示新版本，再把用户带到官网下载页，不下载也不安装。

## 基本信息
- Bundle ID: `com.xk72.Charles`
- Team ID: `9A5PCU4FSD`（Developer ID Application: XK72 Limited）
- 观测版本: short `5.2.2`, build `5.2.2`（2026-10-16）；上一版 `5.2.1`
- 自更新机制: 自研，只提示（`latest.do` 版本检查 → 对话框 → 打开官网下载页）
- 开源: 否

## 覆盖清单（Coverage checklist）

| 组 | 结论 |
|---|---|
| 其他 bundle id | 无。5.2.1、5.2.2 两个真包都是 `com.xk72.Charles`；Homebrew cask `charles` 卸载段也只写这个 id。没有其他版本（edition） |
| beta 轨 | 有这条轨，但现在没有构建可下：`/download/beta/` 页写「Sorry, there are no downloads currently available」，`5.1.1b11` 的 dmg 地址 404（2026-10-16 实测）。app 里没有 beta 开关（jar 里与更新相关的设置只有 `checkUpdates` / `lastCheckUpdates`）。未接，理由见 Channel 详情 |
| 4.x 大版本 | 厂商仍在 `/download/previous-release/` 提供 4.6.8，它自己的版本检查对 4.x 副本也回 4.x（`v=4.2.8` → `4.6.8`）。许可证按大版本卖，5 是付费升级。recipe 用 `installedVersionPattern: ^5\.` 把 4.x 排除在外。4.x 没有自己的 recipe：4.6.8 的 dmg 带许可协议（SLA），按规定不挂载，bundle id 和签名都没有核 |
| 3.x | `/download/previous-release/` 还列着 3.12.3（2018 年）。没下载、没核；不接 |
| 版本范围与 Team | 5.2.1 与 5.2.2 Team 都是 `9A5PCU4FSD`，都通过公证。更早的 5.x 没核 Team |
| 我们的宿主下限 | 包内 `LSMinimumSystemVersion` = `10.9`，主程序 universal（`x86_64 arm64`），不构成限制 |
| 一键 best-effort | 5.x 副本接一键；4.x/3.x 不在 recipe 范围内 |
| 版本 pattern | 探测 pattern 是 `5(?:\.[0-9]+)+` 直到引号：读得出两段的 `5.2`、`5.1`、`5.0`，`5.3b1` 一类读不出来，`6.0` 有意读不出来（见已知问题）。changelog pattern 读版本历史页全部 70 个正式版标题 |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**（5.x） | —  | ✓ 仅 brew 装的副本（cask 非 `auto_updates`） | — | — | ✓ 一键 |
| **beta**     | —       | —        | —   | —      | ○ 现在没有构建 |
| **4.x**      | —       | —        | —   | —      | ○ dmg 带 SLA，没核 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**（官网下载的副本）；Homebrew 装的副本由 HomebrewCaskSource 应答

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.xk72.Charles` | — | — | latest-release 页 | ✓ |
| beta    | `com.xk72.Charles` | 共享 | 版本串 `b<N>` 后缀（`5.1.1b11`、`5.0b18`） | `/download/beta/` 页 | ○ |

beta 副本今天的表现（推断，没拿 beta 真包验，因为下不到）：`5.0b18` 这种一个点的形状会被 `ReleaseChannel.detect()` 第 4 步读成 beta，stable recipe 不应答，行显示 unknown；`5.1.1b11` 这种两个点的形状读成 stable，会被提示 5.2.2。厂商自己的检查对两者都回 `5.2.2`（实测），所以后一种和厂商行为一致。

## 更新检测
- 源: `VendorProbeRecipe`（stable，`installedVersionPattern: ^5\.`）
- 端点: `https://www.charlesproxy.com/download/latest-release/`，读下载表单里的隐藏字段：
  `<input type="hidden" name="beta" value="false" />` 紧接着 `<input type="hidden" name="version" value="5.2.2" />`。
  pattern 要求 `beta` 为 `false`，版本以 `5.` 开头。
- 版本是 marketing 串，等于 `CFBundleShortVersionString`，也等于 `CFBundleVersion`。
- app 自己的检查：`POST https://www.charlesproxy.com/latest.do`（自动检查走 `latest-auto.do`），表单
  `v={版本}&jv=…&jvn=…&os=…&osv=…&int=…`，回纯文本版本号，已是最新时回空 body。GET 回 405。
  回答随发送的版本变：`4.2.8` → `4.6.8`，`4.6.8` → `5.2.2`，`3.12.2` → `3.12.3`，`5.2.1` → `5.2.2`（2026-10-16）。
  recipe 不能把装机版本填进请求体，空 body 也读不出版本，所以没用它。
- **读的是**: 人人可手动下载的 GA 构建。页面对所有人一样，没有设备 id。
- 按 OS / 架构分轨：没有。只有一个 universal dmg，页面不写系统范围。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 版本检查类（`tsRP`）只读一行版本号；提示类（`carW`）只打开 `/download/` 或 `/download/beta/` | `latest.do` 应答只有版本号 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（没跑第二轮） | — |
| 证据 | app 不下载更新，只打开网页（jar 字符串） | — | — |

## Changelog
- 来源: recipe，读 `https://www.charlesproxy.com/documentation/version-history/`
- 结构化: `recipe changelog:com.xk72.Charles:-: 20 entries; newest 5.2.2: 1 items, headings ["Bug fixes"]; first items ["Session importing fixes; faults existed "]`
- 页面结构：每版一个 `<h4>Version X</h4>`，接 `<p>` 日期，再接若干 `<p>` 分类标题 + `<ul>`。
  beta 条目（14 个）被 pattern 跳过；正式版 70 个条目全部读到，都带日期。
  嵌套列表（5.0 等 6 个条目）按「父行 + 每个子项」拆开。4 个没有列表的老版本退回读 `<p>`。
- 4.6.x 的维护版按日期穿插在 5.x 中间（厂商就是这样排的），所以 5.x 的面板里会看到 4.6.8、4.6.7 等条目。
- 跟随 channel: 否（一页覆盖所有版本）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（5.x）
- 端到端: 真机端到端：待主会话执行
- 格式: dmg（UDBZ，无 SLA；内含 `Charles.app` 和 `Applications` 链接）
- 下载地址: `.versionTemplate`，`https://www.charlesproxy.com/assets/release/{version}/charles-proxy-{version}.dmg`，与 Homebrew cask 同一个地址形状。
  5.2.2、5.2.1、5.2、5.1、5.0 都回 200（两段版本 `5.2` 也是这个形状）。
- 校验: 页面不发摘要（latest-release 页里没有 sha256 / sha512 / checksum），只走 Team ID 闸。
- **读的是**: 人人可手动下载的 GA 构建
- 特权 helper: 包内 `Contents/Library/LaunchServices/com.xk72.charles.ProxyHelper`，由 SMJobBless 装到
  `/Library/PrivilegedHelperTools/`，用来改系统代理设置。它是按需启动的 Mach 服务（launchd plist 只有 `Label` 和
  `MachServices`，没有 `RunAtLoad` / `KeepAlive`），从安装目录运行，不从 app 包里运行，所以换包不会让它跑旧代码。
  它只认 Team `9A5PCU4FSD` 签名的 `com.xk72.Charles`（`SMAuthorizedClients`），换上的新包满足这个条件。
  5.2.1 和 5.2.2 的 helper 字节相同（SHA-256 `177e914b…031a`，版本 1.3 / build 5），这次升级不会触发重新安装 helper。
  helper 版本变了的那次升级，app 启动时可能要求管理员授权重新装 helper（推断，app 有 `getVersionWithReply:`，没实测）。
- 阻塞: 无

## 已知问题
- 4.x 副本没有检测（见覆盖清单）。
- 版本 pattern 锁了大版本 `5`。Charles 6 接管 latest-release 页那天，这条 recipe 读不出版本、探测失败（`duo verify` 会报），
  而不是给 5.x 副本提示一个要付费的 6.x。那时要做两件事：5.x 这行改读 5.x 所在的页面（大概是 previous-release），
  6.x 另加一行。`installedVersionPattern: ^5\.` 只看装机版本，挡的是 4.x 副本，挡不住远端换大版本，所以两边都要锁。

## 建议下一步
1. 厂商发布 beta 构建时，下真包核对版本串形状，再决定 beta 行（共享 bundle id，用版本后缀区分）。
2. Charles 6 发布时按上面的已知问题改 5.x 行、加 6.x 行。
3. 如需覆盖 4.x：由用户在 dmg 的许可协议对话框里点同意后挂载 4.6.8，核 bundle id、Team、公证，再加 `^4\.` 一行读 previous-release 页。

## 如何复验

```bash
# 1. 版本页与 app 自己的检查
curl -sSL "https://www.charlesproxy.com/download/latest-release/" | grep -E 'name="(beta|version)"'
curl -sS -X POST --data "v=5.2.1&jv=25.0.3&jvn=OpenJDK&os=Mac+OS+X&osv=26.0&int=false" https://www.charlesproxy.com/latest.do

# 2. 生产检测 + changelog（真包，只读挂载）
swift run --package-path application-test channel-verify charles-proxy-5.2.1.dmg --expect stable
swift run --package-path application-test channel-verify charles-proxy-5.2.2.dmg --expect stable

# 3. 签名与公证
codesign -dvv Charles.app 2>&1 | grep TeamIdentifier
spctl -a -vv -t exec Charles.app
```

2026-10-16 实测:
- `channel-verify`（5.2.1 dmg）: `detected channel → stable`、`VendorProbe ✓ recipe answered for channel 'stable'`、
  `verdict UPDATE 5.2.1 → 5.2.2`；全链 `winning source Vendor`、`download https://www.charlesproxy.com/assets/release/5.2.2/charles-proxy-5.2.2.dmg`、`status UPDATE → 5.2.2`。
- `channel-verify`（5.2.2 dmg）: `verdict up to date`，`winning source Vendor`，`status up to date`。
- 两个 dmg：`Software License Agreement: false`；`spctl` 均 `accepted, source=Notarized Developer ID`；Team `9A5PCU4FSD`；
  主程序 `x86_64 arm64`。5.2.2 dmg 83,191,861 bytes，SHA-256 `560e10c31bb2e680b9b9dadf0fb66450289bd22b4a68bcac5a13a8cce52d9f05`；
  5.2.1 dmg 83,227,158 bytes，SHA-256 `d233395a7fbb487f0fe20ddff16e02a65990add20d5aa9ce1e87a8f9ff0fe0d5`。

## 历史与实测

### 2026-10-16 · 接入

- 4.6.8 dmg（57,280,451 bytes）`hdiutil imageinfo` 报 `Software License Agreement: true`，按接入规则没有挂载。
- `latest.do` 用 GET 回 405；POST 时 `v=5.2.2` 回空 body，`v=5.1.1b11`、`v=5.0b18`、`v=5.0` 都回 `5.2.2`，`v=3.12.3` 回 `5.2.2`。
- 版本历史页：84 个 `<h4>` 标题，其中 70 个正式版、14 个 beta。
- 价格页原文要点：每个许可证对购买时的当前大版本有效，下一个大版本按原价 40% 升级。
