# Aside

AI 浏览器,基于 Chromium,厂商 At Inc.(`aside.com`)。

## 基本信息
- Bundle ID: `at.studio.AsideBrowser`
- Team ID: `8CPD4K4TBB`(`Developer ID Application: At Inc. (8CPD4K4TBB)`)
- 观测版本: short `1.0.910.1`, build `910.1`(2026-09-14,官网 `/api/download/macos` 下发的 DMG)
- 自更新机制: Chromium updater(Omaha 协议)——`AsideUpdater.app` + `AsideSoftwareUpdate.bundle`(`ksadmin`/`ksinstall`)
  + `at.studio.AsideBrowser.UpdaterPrivilegedHelper`。Info.plist **无 `SUFeedURL`、无 `KSChannelID`**

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**(2026-09-14 接入,仅检测)。

- Sparkle: `feed-discover` 对真实 DMG 的结论是 `no Sparkle and no electron-builder update config`。
- Homebrew: cask `aside` 存在但 `auto_updates true`,`HomebrewCaskSource` 退让,不构成检测。
- MAS: `mas search Aside` 命中的是同名的其它 app(`Aside: Save with Purpose` 等),不是这个浏览器。
- GitHub: 非开源。`at-inc` 组织下只有 benchmark 仓库,无 release 资产。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `at.studio.AsideBrowser` | — | — | — | ✓ |

**没找到非 stable 轨。** 证据:changelog 页 `beta`/`canary`/`nightly`/`insider`/`release channel` 出现次数全为 0;
cask 只有 `aside` 一个(无 `@beta`);Info.plist 无 `KSChannelID`;Omaha 请求带 `ap` = `beta`/`dev`/`canary`/`extended`
时对 `1.0.910.1` 一律 `noupdate`(这条只能说明"没有比 910.1 更新的、按 ap 分出去的构建",不能单独证明轨道不存在)。

⚠️ 下载路径里的 `dev-updater` **不是 dev 轨**:cask 的正式 `url` 和官网下载按钮用的就是这个路径。

## 更新检测
- 源: VendorProbe,读下面第 1 个端点(`Recipes/at-studio-AsideBrowser.swift`)
- 端点(三个,2026-09-14 实测互相一致):
  1. `https://ptqgesmtzwdmeiknncqc.supabase.co/functions/v1/omaha/version_info.json` — GET,`Cache-Control: no-store`,
     Homebrew cask 的 livecheck 读的就是它。原始响应体(244 字节):
     ```json
     {"platforms":{"mac":{"version":"1.0.910.1","url":"https://releases.aside.com/dev-updater/Aside-1.0.910.1.dmg"},
      "win":{"version":"1.0.914.1","url":"https://releases.aside.com/dev-updater/windows/1.0.914.1/AsideInstaller-1.0.914.1-win-x64.exe"}}}
     ```
  2. `https://aside.com/api/download/macos` — 302,`Location: https://releases.aside.com/dev-updater/Aside-1.0.910.1.dmg`
     (Vercel;DMG `Last-Modified: Thu, 10 Sep 2026 14:32:06 GMT`,`content-length: 337397522`)。
  3. Omaha 更新检查 `POST …/functions/v1/omaha/service/update2/json`(`server: aside-edge`,响应带 `)]}'` 前缀,`protocol 4.0`):
     `appid at.studio.AsideBrowser` + `version 1.0.910.1` → `noupdate`;`version 1.0.825.1` → `nextversion 1.0.910.1`,
     唯一 pipeline `full-1.0.910.1`,下载 `Aside-1.0.910.1.crx3`(436947033 字节)。`arch` 换成 `x86_64` 结果相同;
     随机 `requestid`/`sessionid` 连打 3 次结果相同。appid 大小写不敏感(响应里回的是小写)。
     同一路径的 GET 只回健康检查 `{"status":"ok","service":"aside-updater-omaha"}`。
- 版本方案: `1.0.<月日>.<序号>`,**端点版本 == `CFBundleShortVersionString`**,普通 recipe,不需要 `versionIsBuild`。
  `CFBundleVersion` 是去掉 `1.0.` 的后半(`910.1`),不要拿它比。版本号里的月日**不含年份**,别从版本号推发布日期。
- **按平台分轨,且 mac 与 win 可以不同步**:同一天 win 已是 `1.0.914.1`,mac 三个端点都还是 `1.0.910.1`,
  按 `…/Aside-1.0.914.1.dmg` 和 `…/macos/1.0.914.1/Aside-1.0.914.1.dmg` 两种路径猜 914.1 的 mac DMG 都是 404。
  所以读 `version_info.json` 时 **pattern 必须只取 `"mac"` 那个对象**,否则 `win` 的版本会漏进来,
  mac 用户会看到一个根本下不到的"更新"。围栏写在 pattern 里:`"mac"\s*:\s*\{[^{}]*?"version"…`,`[^{}]` 出不了 mac 对象。
  ⚠️ **不能用 `entryStartPattern` 来切**:它会在切出来的几段里挑版本**最高**的那段,在这份文档上挑中的恰好是 win 的 914.1。
  (这份审计初稿就是这么建议的,写 recipe 时读 `highestVersionEntry` 才发现。)
- OS 边界: DMG `LSMinimumSystemVersion` = `13.0`(cask `depends_on macos: :ventura` 一致);`version_info.json`
  不带任何 min/max 字段;Omaha 请求里的 OS 版本只测了 `26.0`,没测低版本会不会被分走——**没查**。
- 架构: DMG 是 universal(`x86_64 arm64`),不需要 `hostRequirement`。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无(观测样本内) | 不能 |
| 证据 | `AsideUpdater` 二进制里有 `components/zucchini/*`、`delta_patch_operation.cc`、`out_of_process_patcher.cc`;请求的 `acceptformat` 可以带 `puff,zucc` | 2026-09-14 `1.0.825.1 → 1.0.910.1` 只回 `full-1.0.910.1` 一条 pipeline,没有 diff pipeline | 格式是 Chromium 的 crx3 + zucchini/puffin,不是 Sparkle BinaryDelta,`DeltaApplier` 用不上 |

- 格式: 厂商自有(Chromium update_client)
- 阻塞项: 服务端没在发;就算发了也要新机制。不影响检测。

## 按设备灰度 / 自更新器

- 灰度: Omaha 请求里没发任何设备 id,测过的变量(arch、requestid/sessionid、`ap`)都没让结果变;`cohort` 没测。
  但 mac 轨当前只有一个构建,**灰度就算存在也观测不到**,等 mac 出 914.x 时可以再打一次。
- 自更新器抢占: 带 LaunchAgent(`at.studio.AsideUpdater.wake`、`at.studio.AsideKeystone.agent`)和一个特权 helper,
  会在后台自己更新。和一键安装会不会冲突——**没查**,接一键时要单独看。

## Changelog
- 来源: 厂商文档站(Mintlify)`https://docs.aside.com/changelog/native`,**有 Markdown 版** `…/changelog/native.md`
  (200,`text/markdown`,31291 字节,2026-09-14)——建议 recipe 读 `.md`(`markdownSource`)而不是 HTML。
- 结构: 51 条,标题一律是 `## v1.0.N.N`(`1.0.626.1` 及更新的版本)或 `## 1.0.N.N`(`1.0.624.1` 及更早的,没有 `v`);
  小节 `### …`,条目有 `* …`(有时缩进)也有纯段落,偶尔夹一段 ``` 围起来的命令;`**粗体**` 只在少数条目里出现。**日期行**(`June 26, 2026` 这种格式)只有 38 条带,`1.0.626.1` 及更早的才有,
  最新的 13 条全没有日期。
- 跟随 channel: 无 channel;但**跨平台共用一页、条目上不标平台**。`v1.0.914.1` 的第一个小节是
  「Aside is now officially available on Windows!」,同一条里也有 macOS 修复。所以页面顶部那条可以比 mac 当前版本新,
  2026-09-14 就是这样(页面顶部 914.1,mac 910.1)。**recipe 不能默认"第一条就是最新的 mac 版"**。
- 页面比远端版本还新时: `ChangelogExtractor` 不按版本过滤条目,解析到什么就渲染什么,所以 mac 还没发的 914.1
  会照样列在最上面;`duo verify` 的滞后检查只在最新条目**落后于**探测版本时才报,这个方向不报。
  界面上实际长什么样**没看过**。
- 另有 `/changelog/components`,是浏览器内组件(Aside Components)的更新日志,不是 app 版本,不要读。
- Recipe 状态: 已有(2026-09-14)。读 `.md`,`markdownSource`,`headingPattern` 把 `###` 渲染成小节标题,
  条目取所有非空、非标题、非围栏行(段落本身就是说明),`maxEntries: 10`。`**粗体**` 会原样显示(`markdownSource`
  只解开代码和链接)。

## 一键安装
- 状态: 仅检测(recipe 不带 `install`);要做就用 DMG
- 格式: dmg(universal,337 MB);Omaha 那条给的是 `.crx3`,不要用
- **读的是**: 人人可手动下载的 GA——`version_info.json` 的 `mac.url` 和官网下载按钮的 302 目标逐字相同
  (`releases.aside.com/dev-updater/Aside-1.0.910.1.dmg`),也和 Omaha 对旧版本分配的 `nextversion` 相同。
  这个判断的前提是 mac 轨当前只有一个构建;将来如果厂商开始灰度,`version_info.json` 可能跑到分配前面,到时要重看。
- 阻塞: 签名 Team `8CPD4K4TBB` 已从 DMG 读到;自更新器会不会抢(见上)没查。

## 已知问题
- mac 版可以比 Windows 版和 changelog 顶部晚发(2026-09-14:win 914.1 / mac 910.1)。这是厂商按平台分开发布,
  不是端点坏了,不要写成 recipe 故障。

## 如何复验

```bash
# 1. 版本源(应只取 mac 对象)
python3 -c 'import urllib.request,json;print(json.load(urllib.request.urlopen(urllib.request.Request("https://ptqgesmtzwdmeiknncqc.supabase.co/functions/v1/omaha/version_info.json",headers={"User-Agent":"Mozilla/5.0"})))["platforms"])'
# 2. 官网下载重定向(应和 1 的 mac.url 相同)
curl -sI https://aside.com/api/download/macos | grep -i '^location'
# 3. 通用源都覆盖不到(应为 no Sparkle and no electron-builder update config)
swift run --package-path application-test feed-discover <Aside-*.dmg>
# 4. bundle 身份
hdiutil attach -nobrowse -readonly <Aside-*.dmg>
plutil -p "/Volumes/Aside Browser/Aside.app/Contents/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleShortVersion|CFBundleVersion|SUFeedURL|LSMinimumSystem'
codesign -dv "/Volumes/Aside Browser/Aside.app" 2>&1 | grep TeamIdentifier
lipo -archs "/Volumes/Aside Browser/Aside.app/Contents/MacOS/Aside"
```

2026-09-14 的结果: (1) mac `1.0.910.1` / win `1.0.914.1`;(2) 同一个 DMG URL;(3) `noKnownUpdater`;
(4) `at.studio.AsideBrowser` / `1.0.910.1` / `910.1` / 无 `SUFeedURL` / `13.0` / `8CPD4K4TBB` / `x86_64 arm64`。

recipe 接入后(2026-09-14):

```bash
make cli && duo verify --only asidebrowser --samples
```

结果: vendor probe ✓ `1.0.910.1`(== 真实 DMG 的 `CFBundleShortVersionString`),changelog ✓ 10 条、最新 `1.0.914.1`
(页面跨平台,见 Changelog 一节)。另有一条 note `oneClickCandidate`——响应里有 DMG 链接;仅检测是有意的,理由写在 recipe 注释里。

**没跑的**: 从真实 bundle 出发的生产链路(`channel-verify <dmg>`)。当天 `application-test` 的 `channel-verify` 在 main 上
编译不过(`GitHubToken.resolve()` 已改成 async,`main.swift` 两处没 `await`),而 `duo check <路径>` 只认已安装位置。
单 channel、无 channel 检测信号,所以缺的是"bundle → 优先链"这段接线的实跑,不是渠道判定。

## 建议下一步
1. 一键: 单独决定,先查 AsideUpdater 后台更新和一键会不会撞。要做的话 install URL 用同一个 mac 对象里的 `"url"`
   (同样要 `[^{}]*?` 围栏),Team `8CPD4K4TBB`。
2. mac 出下一个构建时再打一次 Omaha,看有没有灰度。
3. 渠道: 暂无,不需要改 `CHANNEL_COVERAGE_TODO.md`。
