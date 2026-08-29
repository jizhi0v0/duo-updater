# Grok Bot

审计 2026-08-29。

## 基本信息

- Bundle ID: `com.anysphere.sand`
- App 名: `Grok Bot.app`
- 官网 / 下载页: https://x.ai/bot
- 观测版本: `0.30.0`（`CFBundleShortVersionString` 与 `CFBundleVersion` 同为 `0.30.0`）
- Team ID: `DCNK4UB866` — **Anysphere Incorporated**，`spctl` 判定 "Notarized Developer ID"
- 架构: arm64 thin（`Format=app bundle with Mach-O thin (arm64)`）
- `LSMinimumSystemVersion`: `12.0`（cask 的 `depends_on macos: :monterey` 与之一致）
- 自更新机制: **Electron + Squirrel.Mac**（`Contents/Frameworks/` 下有
  `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`、
  `Electron Framework.framework`；业务在 `Contents/Resources/app.asar`）

**这个 app 是 xAI 的产品，但由 Anysphere（Cursor 那家）构建、签名、分发。**
这不是推测：bundle id 就是 `com.anysphere.sand`，签名 Team 是 Anysphere，
更新接口在 `api2.cursor.sh`，产物在 `downloads.cursor.com`。所以它在 registry
里挨着 Cursor 放，而不是按品牌归到 x.ai 下面。

内部代号是 **`sand`**，这个词贯穿三处：bundle id 的末段、更新接口的 app name、
以及 asar 里的 `isSandUpdateTrack` / `sandTrack` / `window.__sandStatus`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | — | ✗ | — | — | ✓ 一键 |

当前生效源：**VendorProbe**。其余四条源为什么都不答：

- **Sparkle** — bundle 里没有 `SUFeedURL`，`Contents/Frameworks/` 下也没有
  `Sparkle.framework`。它用的是 Squirrel。
- **Homebrew** — cask `grok-bot` 存在，但 `auto_updates true`，
  `HomebrewCaskSource` 按设计 `return nil`。**注意 cask 本身并不滞后**：
  raw 定义当天就是 `0.30.0`，和厂商接口一致；本机 `brew info` 报 `0.29.0` 是
  本地 tap 元数据陈旧，不要拿它当"cask 落后"的证据。
- **MAS** — `itunes.apple.com/lookup?bundleId=com.anysphere.sand&entity=macSoftware`
  返回 `resultCount: 0`。
- **GitHub** — 没有公开发布仓库。`anysphere` 组织下 83 个公开仓库里唯一沾边的是
  `anysphere/bugbot-context`（Cursor 的 Bugbot，不是这个 app），`xai-org` 下搜
  `grok-bot` 返回 0 条。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.anysphere.sand` | 独立 | — | — | ✓ |
| nightly | — | — | — | 客户端强制回落 stable | ✗ 不可达 |
| dogfood | — | — | — | 需内部 unlock，且服务端无此 app name | ✗ 不可达 |

**只有 stable，这是厂商的立场，不是我们的假设。** asar 里确实定义了三条轨道：

```js
var _ze = ["stable","nightly","dogfood"];
function vgi(n){switch(n){
  case "stable":  return "sand";
  case "nightly": return "sand-nightly";
  case "dogfood": return "sand-dogfood";
}}                                    // appNameForTrack
```

但同一份 asar 里两处把它们关掉了：

```js
var Jdt = !0;
function ghe(t){ return Jdt && t === "nightly" ? "stable" : t }   // coerceToEnabledTrack
var yCt = !0, Iii = ["dogfood"];
function E3t(n){ return _ze.filter(e => yCt && e === "nightly" ? !1
                                        : Iii.includes(e) ? n : !0) } // selectableUpdateTracks
```

nightly 被强制读作 stable，dogfood 只在 `unlockInternalTracks` 为真时出现在
选择器里。服务端也是同一个答案：`sand-nightly` / `sand-dogfood` 在任何 channel
路径下都 404（`{"error":"Invalid app name - can only download stable for cursor or sand"}`）。

所以一条 recipe、`channel: .stable`，`GrokBotProbeRecipeTests` 里钉了这一条。

## 更新检测

接的是：

```
GET https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand
```

```json
{"downloadUrl":"https://downloads.cursor.com/grokbot/stable/darwin-arm64/0.30.0/Grok_Bot_0.30.0.dmg",
 "rehUrl":"https://cursor.blob.core.windows.net/remote-releases/2385d.../vscode-reh-darwin-arm64.tar.gz",
 "version":"0.30.0",
 "commitSha":"2385d097738b3719cc5ecd9281a107aa106215f1"}
```

`version` 与磁盘上的 `0.30.0` 同构（同一个 marketing 串，app 的 build 号也等于它），
可以直接比。整份 body 里**只有一个**引号包起来的点分数字，pattern 又两侧锚在引号上，
不存在抓错号的余地。

app name 是 `sand` 不是 `grok-bot`/`grokbot` —— 这条是接口自己说的，任何别的名字都会
回 `Invalid app name - can only download stable for cursor or sand`。

### 另外两个端点，都是故意不用的

1. **x.ai/bot 下载按钮那条**
   `https://api2.cursor.sh/updates/download/stable/darwin-arm64/grok-bot-bd824e1890d8b96f`
   —— 302 到同一个 dmg，但全程不发布版本号，只能靠读文件名。
   顺带说一句这串 hash 的来路：它是**官网 HTML 里直接写着的**（x.ai/bot 页面源码
   grep 得到，就是这条完整 URL），不是客户端算出来的，所以它至少不随机器变。
   会不会随 build 变没验证——反正我们不读它。

2. **cask livecheck 那条 —— app 自己的 Squirrel feed**
   `https://api2.cursor.sh/updates/api/update/darwin-arm64/sand/<已装版本>/stable`

   ```
   /0.0.0/stable   → 200 {"url":"…/Grok_Bot_0.30.0.zip","name":"0.30.0"}
   /0.30.0/stable  → 204，body 0 字节
   ```

   这是**条件端点**：已经最新就回 204 空 body。空 body 同时也是"端点坏了"的样子，
   拿它做探测等于教 sweep 把沉默读成好消息。`/updates/api/download/…` 无条件应答
   且直接给 `version`，所以选它。
   （asar 里的 zod schema 与此吻合：darwin 走 `squirrel`，schema 是 `{url, name}`；
   非 darwin 走 `iupdate`，schema 是 `{url, version, sha256hash?}`。）

## 一键安装

**已接入，`kind: .dmg`。**

- **Team 闸**：dmg 里的 `Grok Bot.app` 与已装副本同为
  `Developer ID Application: Anysphere Incorporated (DCNK4UB866)`，`spctl` 判
  "Notarized Developer ID"。
- **为什么不是 `.pkg`**：装机内容全在 bundle 内部
  （`Contents/Frameworks`、`Contents/Helpers/Grok Bot Helper.app`），
  `/Library/LaunchDaemons`、`/Library/LaunchAgents`、`~/Library/LaunchAgents`
  里都没有 anysphere/grok 相关项。换 bundle 就是整个更新。
- **install pattern 钉了两段路径前缀**：

  ```
  https://downloads.cursor.com/(?:grokbot|sand)/stable/darwin-arm64/…dmg
  ```

  两段是因为**同一份产物厂商在两个前缀下都发**：接口回 `/grokbot/…`，
  Homebrew cask 的 url 模板拼的是 `/sand/…`，两条实测都 200 且
  `content-type: application/x-apple-diskimage`。

  钉前缀而不是只钉 host，是因为 `downloads.cursor.com` 同时供着 Cursor 自己的
  构建（`/production/…/Cursor-darwin-arm64.dmg`）和本 app 的 x64 / universal
  变体。前缀哪天再改，pattern 失配 → 一键消失，这是它该失败的方向。
- **没有 checksum**：这个端点不发 sha。（cask 里有 sha256，但那是 cask 自己的
  数据，不在我们读的 body 里。）

## Changelog

**没有，`changelogURL: nil`，不是疏漏。** xAI 不为这个桌面 app 发版本级 release
notes。x.ai 站内唯一带 changelog 的链接是 `x.ai/api/changelog`，标题
"Console Changelog"，讲的是开发者 API 控制台，产品和版本方案都不是一回事；挂上去
只会给用户展示一个不相干的页面。（对照 registry 里 Spotify 那条同样的处理。）

## 已知问题 / 后续

- 该 app 的自更新走 Squirrel，我们的一键是 best-effort 覆盖，遵循既有策略。
- 若接口哪天把 `downloadUrl` 换成第三个路径前缀，或改回 `.zip`（Squirrel feed 那条
  已经在发 zip 了），一键会静默消失但检测不受影响；sweep 会报 install 侧失配。
