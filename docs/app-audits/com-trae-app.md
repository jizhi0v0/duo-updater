# TRAE

审计 2026-10-08（重测；2026-08-17 那版的结论是「官方 API 只发布 `2.3.x` 打包号、没有可比的远端版本」，
当时成立，**现在不成立了**：官方 API 已经按平台、架构发布与包内 `CFBundleShortVersionString` 同构的版本号。
同日按 A 接入 VendorProbe，见「覆盖矩阵」与「更新检测」。2026-10-09 补跑一键端到端两轮，见「一键安装」。）

## 基本信息
- Bundle ID: `com.trae.app`（官网 GA 与 API 里 `tob` 段的构建都是这个 id，见下）
- Team ID: `79M8227NKH` — Developer ID Application: SPRING (SG) PTE. LTD.（3.5.81、3.5.87、3.5.104 三个真包相同，
  均 `Notarized Developer ID`）
- 观测版本: `3.5.104`（`product.json` `tronBuildVersion` `2.3.88407`，2026-09-22 构建）；更早的真包
  `3.5.87`（`2.3.68993`）、`3.5.81`（`2.3.61406`）。三包 short = build；`LSMinimumSystemVersion` 12.0；
  arm64 与 x64 分开发包（arm64 dmg `lipo -archs` = `arm64`）。主程序可执行文件名是 `Electron`
- 自更新机制: 自研（VS Code 系 update service + 字节的 “tron” 检查客户端），落地用 electron-updater 的
  custom provider + Squirrel.framework。包里 `app-update.yml` 是 `provider: custom`、`url: ''`
- 产品线: 下载文件已从 `Trae-darwin-*.dmg` 改名为 `TraeCode-darwin-*.dmg`（`product.json` `nameAlias: TraeCode`）。
  同一 API 还发布 `solo` 段（`TraeWork-darwin-*.dmg`，版本 `0.1.69`）——那是另一个产品，bundle id 没查，不在本审计范围
- Homebrew: cask `trae` 停在 `2.3.61406`，URL 是旧文件名 `Trae-darwin-arm64.dmg`；同一旧文件名在 `2.3.88407` 目录下 404。
  推断 cask 的 livecheck 跟不上改名（未验证）。cask 是 `auto_updates: true`，本来也不参与检测
- 不开源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，且版本停在旧打包号） | — | — | ✓ 一键（官网下载 API，arm64 / x64 各一条，`va` 区） |
| **beta / alpha** | — | — | — | — | 没找到公开构建 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（`Recipes/com-trae-app.swift`，读
`data.manifest.darwin.versions[]` 中 region `va` + 本机架构那一项；`tob` / `solo` 段被锚定排除）。接入前
（2026-10-08 实测）`winning source <none>`、`status unknown (no source answered)`；接入后 3.5.87 → `UPDATE → 3.5.104`（Vendor），
3.5.104 → up to date

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.trae.app` | — | `product.json` `quality: stable` | VendorProbe 读官网下载 API（A） | ✓ |
| beta / alpha / dev | 未见真包 | — | `quality` 在构建时写进 `product.json` | — | 没找到公开构建 |

- 客户端认得几种质量：`product.json` 的 `iCubeApp.authConfig` 给 TRAE 和 SOLO 各列了 `stable` / `beta` / `alpha` /
  `dev` / `local`；`main.js` 里 `quality === "insider"` 被映射成 `beta`。这是客户端能力，不说明服务端在发。
- 服务端（2026-10-08）：官方 API 加 `?quality=beta` 或 `?channel=beta` 回的内容与不加相同（参数被忽略），
  `…/native/version/trae/beta` 是 `Not Found`；Trae 自己的检查用 `beta_` 前缀的 `uid` / `packageType` 从 3.5.81
  请求，回 `needUpdate:false`。**没找到公开 beta，不等于没有 beta**；没有加入 beta 的入口可供查证。
- 远端配置 `featureVersion/releaseBranch` 能把某个用户的检查切到另一条 release branch（`checkForUpdate(i, e)`
  里 `e !== this.branch` 时改发 `branch=<e>`、`buildId=""`）。这是按人分流的客户端能力；服务端给谁开没法从外面查。

## 更新检测

两个可比的远端版本源，语义不同；**A 已接入**（VendorProbe，`Recipes/com-trae-app.swift`），B 没接：

**A. 官网下载用的公开 API（2026-10-08 实测）**

- `GET https://api.trae.ai/icube/api/v1/native/version/trae/latest`（`cache-control: max-age=0, no-cache, no-store`）。
  官网前端 `main.*.js` 用的就是这个路径（`url:"/icube/api/v1/native/version/trae/latest"`）。
- `data.manifest.darwin.versions` 现在是数组，每项 `{region, arch, url, version}`：4 个区域（`cn` / `sg` / `va` /
  `usttp`）× 2 个架构（`apple` / `intel`），8 项全部 `"version":"3.5.104"`，URL 都在 `releases/stable/2.3.88407/darwin/`。
  `win32` 段也是 3.5.104。
- 同一响应里还有：`data.solo`（TraeWork，0.1.69 / 2.3.87414）、`data.mobile`（商店链接）、`data.tob.manifest`
  （`2.3.68993`，`version` `3.5.87`，同样是 `TraeCode-darwin-*.dmg`）。`tob` 从 `main.js` 的
  `/trae/gtm/tob/api/v1/package/check_update` 路径看是企业版轨（推断）。
- **真包对上了**：`2.3.88407/darwin/TraeCode-darwin-arm64.dmg`（414,318,607 B，MD5 与 CDN `etag`
  `e986444e…27a1` 相同）挂载后 `com.trae.app`、`CFBundleShortVersionString` / `CFBundleVersion` 都是 `3.5.104`，
  `product.json` `appVersion 3.5.104`、`tronBuildVersion 2.3.88407`。`tob` 段的 `2.3.68993` 包同理对上 `3.5.87`（etag
  `4061cad6…4584` 与 MD5 相同）。
- 陷阱（写 recipe 时要处理）：同一 body 里 `"version"` 出现在 `manifest.win32`、`manifest.darwin`、`solo.*`、`tob.*`
  多处，版本各不相同；必须用 `entryStartPattern` 把切片锚在 `data.manifest.darwin.versions` 并按 `arch` 选，不能取第一个匹配。
  `manifest.darwin.download`（旧形状，只有 URL）仍然并存。

**B. Trae 自己的检查（2026-10-08 实测，参数照 `main.js` 拼）**

- `GET https://icube-normal.trae.ai/icube/api/v1/package/check_update?pid=7409949320595642651&uid=stable_<设备号>&mid=…&did=0&packageType=stable_i18n&productCode=TRAE&platform=Mac&arch=arm64&appVersion=<x>&buildVersion=<2.3.x>&traeVersionCode=20250325&branch=release_desktop_i18n&buildId=<包内 package.json 的 buildId>`。
  少了 `packageType` 回 `{"err_code":1000,"err_message":"缺少包类型"}`。
- 结果：从 3.5.81（buildId `1191350185730`）→ `needUpdate:true`、`"appVersion":"3.5.87"`、`manifest.darwin.version` `2.3.68993`；
  从 3.5.87（`1199862657538`）→ `needUpdate:false`；从 3.5.104（`1232067209986`）→ `needUpdate:false`。
  用 12 个随机设备号各请求一轮，12/12 同一答案。
- 客户端拿 `tronBuildVersion`（2.3.x）和 `manifest.<platform>.version` 比（semver），然后从
  `<url>/latest_<arch>[_<region>]` 走 electron-updater custom provider。那个 feed 文件名没查清：
  `latest_arm64{,_va}/latest-mac.yml`、`latest_arm64.yml` 等几个候选都 404。

**A 与 B 不一致**：官网 / 公开 API 给 3.5.104，未登录的应用内检查停在 3.5.87（= API 里 `tob` 段的版本）。
是分阶段放量、按登录态分配、还是应用内轨本来就落后官网，从外面分不清。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 没查（feed 文件没找到） | 没查 |
| 证据 | — | — | — |

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 / 按人分流 | 有：检查带 `uid=<quality>_<设备号>`；远端 `featureVersion/releaseBranch` 能换分支 | 匿名随机设备号：12/12 相同，没看到按设备分；登录后未验证 | — |
| 按架构 / 按 OS 分轨 | 按架构：`apple` / `intel` 两个 dmg；按区域：4 个 CDN | 8 项同一版本；OS 下限 12.0 只在包里 | recipe 要按本机架构选 URL |
| 自更新器会不会和我们抢 | 有自己的下载 / `quitAndInstall` 流程 | — | 第二轮已跑（见「一键安装」）：app 运行中 duo 装上 3.5.104，退出后没有被换回 |

## Changelog
- 来源: 无（`trae.ai/changelog` 是 JS 壳，`docs.trae.ai/ide/changelog` 停在 v3.5.89~3.5.91），没有 changelog recipe
- 结构化: `changelog pane  none — the pane says there are no release notes`（3.5.104 与 3.5.87 两个包）
- `https://www.trae.ai/changelog` 返回的是 JS 壳（16 KB HTML，`file` 判定为 UTF-8 文本，不是压缩字节；无版本号）
- `https://docs.trae.ai/ide/changelog` 有内容，嵌在页面里的 Quill delta JSON：按日期分条（“August 19, 2026 (Hotfix)”），
  条目写版本区间（“TraeCode v3.5.89 ~ 3.5.91 are released”）。最新一条是 2026-08-19，**没有 3.5.104**
  （3.5.104 构建于 09-22）
- Recipe 状态: 检测接上之前不需要；接上之后也难做（版本区间、日期分条、内容滞后）

## 一键安装
- 状态: 支持（dmg，按架构分包，每个架构一条 recipe、各带 `hostRequirement`；安装 URL 也钉死本架构的文件名）
- 端到端（2026-10-09，CLI 由当天 `origin/main` `make cli` 构建）: 旧版用上表 3.5.87 arm64 包，`ditto` 进 `/Applications`。
  `duo check` → `Trae  3.5.87  →  3.5.104  [Vendor, in-place]`。
  - 第一轮（不运行）: `duo install /Applications/Trae.app --yes --json` → `outcome installed`、`route vendor`、
    `bytesDownloaded 414318607`。装后 3.5.104，`codesign --verify --deep --strict` 通过，Team `79M8227NKH`
  - 第二轮（运行中）: 换回 3.5.87、启动，运行约一分钟后 `duo install` → 同样 `installed`、`route vendor`、同样字节数；
    磁盘上 3.5.104，运行中的进程仍是旧 PID；`duo restart /Applications/Trae.app` → `restarted`，新 PID；
    正常退出后仍是 3.5.104、strict 通过，`duo check --all` → `up to date`。Trae 自己的应用内检查给的是 3.5.87
    （见「更新检测」B），推断它当时没有可暂存的更新；暂存目录没查
- 格式: dmg，按架构分包（arm64 414,318,607 B）
- 校验: API body 没有摘要字段；CDN 的 `etag` / `content-md5` 是 MD5（不支持的格式），只能靠 Team 闸
- **读的是**: 官网下载按钮给的 GA（A），人人可手动下载，**超前于 Trae 应用内检查分配的版本**（3.5.104 对 3.5.87）。
  2026-10-08 用户决定跟随官网：一键会把 Trae 自己当下还不推的版本装上，recipe 注释里写明了
- Team: 3.5.104（arm64、x64）与 3.5.87 arm64 同为 `79M8227NKH`，与已装 app 相同，`codesign --verify --deep --strict` 均退出 0；
  `spctl` 都是 `Notarized Developer ID`（3.5.104 没有装订票据，3.5.87 有）。x64 dmg 442,635,468 B，3.5.104，只有 x86_64
- 嵌套: `check-bundle.sh` 只列出 4 个 Electron helper（`LSUIElement`）；没有 `Contents/Library`、`Contents/Helpers`
- 阻塞: 无已知

## 已知问题
- 官网 / 公开 API 与应用内检查不同步（A 与 B）；duo 跟随官网（A）
- Homebrew cask 停在旧文件名、旧版本

## 建议下一步
1. （已做）A：VendorProbe 读官网下载 API，每个架构一条 recipe、各带 `hostRequirement`，一键装官网 dmg（见上）。
   `VendorProbeRecipe.swift` 里两段过期的 TRAE 注释已改
2. B 更贴近 Trae 自己的行为，但请求要带包内 `package.json` 的 `buildId`，现有 recipe 字段没有这个能力；不建议为它加机制
3. （已做）一键端到端 3.5.87 → 3.5.104 两轮，见「一键安装」

## 如何复验

2026-10-08。dmg 从 API 给的 `va` 区 URL 下载（`curl -fL --retry 5 -C -`），各放一个空目录；只读挂载、
`ditto` 拷出 .app，不安装、不启动。下载的 MD5 与 CDN `etag` 相同。

```bash
curl -sS -A "<browser UA>" -o trae.json https://api.trae.ai/icube/api/v1/native/version/trae/latest
python3 -c 'import json; d=json.load(open("trae.json"))["data"]; \
  print(sorted({(v["arch"], v["version"]) for v in d["manifest"]["darwin"]["versions"]})); \
  print(sorted({(v["arch"], v["version"]) for v in d["tob"]["manifest"]["darwin"]["versions"]}))'
curl -fL -o TraeCode-darwin-arm64.dmg \
  https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.88407/darwin/TraeCode-darwin-arm64.dmg
curl -fL -o TraeCode-darwin-arm64-68993.dmg \
  https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.68993/darwin/TraeCode-darwin-arm64.dmg
curl -fL -o Trae-darwin-arm64-61406.dmg \
  https://lf-cdn.trae.ai/obj/trae-ai-us/pkg/app/releases/stable/2.3.61406/darwin/Trae-darwin-arm64.dmg
md5 -q TraeCode-darwin-arm64.dmg; curl -sSI <同一 URL> | grep -i etag
swift run --package-path application-test channel-verify <Trae.app>
python3 -c 'import json; p=json.load(open("<Trae.app>/Contents/Resources/app/product.json")); \
  print(p["appVersion"], p["tronBuildVersion"], p["quality"])'
python3 -c 'import json; p=json.load(open("<Trae.app>/Contents/Resources/app/package.json")); print(p["branch"], p["buildId"])'
# Trae 自己的检查，参数见「更新检测」B；设备号用 uuidgen 现生成
```

以下 `status` 是**接入前**的实测；接入后 3.5.87 → `UPDATE → 3.5.104`（Vendor），3.5.104 → up to date。

| 包（`tronBuildVersion`） | 来源 | short / build | `appVersion` | Team | detected | status |
|---|---|---|---|---|---|---|
| 2.3.88407 arm64 | API `manifest.darwin` | 3.5.104 / 3.5.104 | 3.5.104 | 79M8227NKH | stable | unknown (no source answered) |
| 2.3.68993 arm64 | API `tob.manifest.darwin`；应用内检查从 3.5.81 给的也是它 | 3.5.87 / 3.5.87 | 3.5.87 | 79M8227NKH | stable | unknown (no source answered) |
| 2.3.61406 arm64 | 2026-08-17 审计用的包（Homebrew cask URL） | 3.5.81 / 3.5.81 | 3.5.81 | 79M8227NKH | 没跑 | 没跑 |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`（`source=Notarized Developer ID`）。

**一键端到端:** 上一版用上表第二行的 3.5.87 arm64 包（接入 A 后它被推 3.5.104），2026-10-09 两轮跑通，见「一键安装」。

## 重审更正（相对 2026-08-17 版）
- 「网络响应不发布 `appVersion`」：现在发布了（`versions[].version`，与真包逐字相同）；Trae 自己的检查响应也带
  `appVersion`
- 「Homebrew ✗」：cask 存在，`auto_updates`，且停在旧版本 / 旧文件名
- 新增：官网与应用内检查给的版本不一致；API 里有 `tob` 与 `solo` 两段同形数据，写 recipe 时必须避开
- 「已验证版本」改为「观测版本」
