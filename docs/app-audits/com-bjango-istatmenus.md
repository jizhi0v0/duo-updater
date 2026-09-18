# iStat Menus

**这不是审计**：family `com-bjango-istatmenus`（`Recipes/com-bjango-istatmenus.swift`）里 iStat Menus `com.bjango.istatmenus` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/com-bjango-istatmenus.swift — VendorProbe（`download.istatmenus.app/istatmenus7/download/` 重定向到的 zip）

#### 2026-09-17（第一版修法，#699，已被下一节取代）：小版本号只在文件名里，版本正则改为只取 MAJOR.MINOR

用户反馈：点 Update 7.50.1 之后报「The install finished without an error, but iStat Menus on disk is still 7.50 — what was downloaded wasn't 7.50.1.」。

- `download/` 当时 302 到 `https://cdn.istatmenus.app/files/istatmenus7/versions/iStatMenus7.50.1.zip`。
- 从同一 CDN 下载四个 zip，解包读 `iStat Menus.app/Contents/Info.plist`：

  | zip | `CFBundleShortVersionString` | `CFBundleVersion` |
  |---|---|---|
  | `iStatMenus7.30.zip` | `7.30` | `2282` |
  | `iStatMenus7.30.1.zip` | `7.30` | `2284` |
  | `iStatMenus7.50.zip` | `7.50` | `2355` |
  | `iStatMenus7.50.1.zip` | `7.50` | `2356` |

  7.50 与 7.50.1 的主二进制不同（`cmp` 不等），即确实是两个构建，只是 marketing 版本没动。
- 旧正则 `iStatMenus([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip` 取出 `7.50.1`，没有 build，于是 `UpdateChecker.evaluate`
  走 marketing 分支比 `7.50.1` 对 `7.50`，恒为更新；装完仍是 `7.50`，`AppListModel` 的「install applied nothing」闸报错。
  报错里「what was downloaded wasn't 7.50.1」这半句在这个场景下不成立——下载的就是 7.50.1。
- 找过能拿到 build 的公开来源，没有：app 内 `BBRUpdater` 引用的
  `updates.istatmenus.app/istatmenus7/updates/history/` 是一页 HTML（当时 `Last-Modified` 为 2026-05-14，最新一节是 7.3），
  `…/updates/patch/` GET 为 404、POST 为 405。没有继续逆向它的请求格式。
- CDN 上探过的文件名（HEAD）：`7.30`、`7.30.1`、`7.50`、`7.50.1` 为 200；`7.00`–`7.10.4` 为 301（`7.10.1` 指向 `iStatMenus7.20.zip`）；
  `7.20*`、`7.30.2`、`7.40*`、`7.50.2` 为 404。
- 取舍：正则改为 `iStatMenus([0-9]+\.[0-9]+)(?:\.[0-9]+)?\.zip`。代价是小版本（7.50 → 7.50.1）不再提示，
  方向是漏报而不是误报；iStat Menus 自带更新器。
- 生产链复验（`swift run --package-path application-test channel-verify "<解出的 iStat Menus.app>"`，
  对着当时线上的 7.50.1 重定向，四个真实包逐一跑）：

  | 包 | 旧正则 | 新正则 |
  |---|---|---|
  | 7.30（2282） | — | `UPDATE 7.30 → 7.50` |
  | 7.30.1（2284） | — | `UPDATE 7.30 → 7.50` |
  | 7.50（2355） | `UPDATE 7.50 → 7.50.1` | `up to date` |
  | 7.50.1（2356） | `UPDATE 7.50 → 7.50.1` | `up to date` |

  旧正则那两行是临时把 pattern 改回去重编后跑的，7.50.1 那行就是用户看到的幽灵更新。

#### 2026-09-17（第二版修法）：只取 MAJOR.MINOR 会漏掉绝大多数重发，改为读包内 Info.plist

#699 合并后复核「是不是所有版本都这样」，结论是第一版的代价被低估了：

- **重发很频繁。** Homebrew cask（`Casks/i/istat-menus.rb`）的提交历史里，文件名带第三段的版本：
  7.0.2/.6/.8，7.01.1/.3/.4/.5/.7/.8/.9，7.02.1–.5、.9–.15、.17，7.10.0/.2/.4/.6，7.20.4/.6/.7，7.30.1，7.50.1。
  cask 自己写着 `sha256 :no_check # required as upstream package is updated in-place`。
  只取 MAJOR.MINOR 时，7.02 周期那十几次重发一次都不会提示。
- **厂商自己不把第三段当版本号。** `bjango.com/mac/istatmenus/versionhistory/` 只列 `7.5`、`7.3`、`7.2 (2273)`、`7.2`、`7.1`、`7.02`、`7.01`、`7.0`。
- **又核了一个真实包**：`iStatMenus7.20.7.zip` → `7.20` / `2268`（共 3 个带第三段的包都是 marketing 不动）。
  7.20.7 之前的重发包 CDN 上已 404 或 301 到 `iStatMenus7.20.zip`，无法核。所以「所有重发都这样」是 n=3 加厂商历史页写法的推断。
- **CDN 支持 Range**：`accept-ranges: bytes`，`Range` 请求回 206。`iStatMenus7.50.1.zip` 的目录里 `iStat Menus.app/Contents/Info.plist` 是第 10 条（共 3060 条，目录偏移 910 B），
  压缩后约 1 KB。

改法：新的 probe mode `.redirectArchiveInfoPlist(entry:)`。仍用重定向文件名确认拿到的是 iStat 的 zip（`versionPattern` 恢复为能匹配第三段），
然后按 Range 读包内 `Info.plist`，把包自己的 `CFBundleShortVersionString` / `CFBundleVersion` 当作远端版本。
这样 2355 的副本会被提示、2356 的副本显示已是最新，而安装后磁盘上报的正好是被提示的那一对，安装后与重启落地的检查不需要改。

否决过的方案：只在「安装后」加豁免（build 变了就允许显示版本对不上）。安装后的检查本来就只在 build 也没变时报错，
而提示本身来自每次检查的比较，所以这样改既消不掉一直显示的「有更新」，也消不掉已在 2356 的副本点「更新」后的报错。


复验（同日，改完之后）：

- 生产链：`swift run --package-path application-test channel-verify "<解出的 iStat Menus.app>"`，对着当时线上的 7.50.1 重定向：

  | 包 | 第一版（只取 MAJOR.MINOR） | 第二版（读包内 Info.plist） |
  |---|---|---|
  | 7.20.7（2268） | — | `UPDATE 7.20 (2268) → 7.50 (2356)` |
  | 7.30（2282） | `UPDATE 7.30 → 7.50` | `UPDATE 7.30 (2282) → 7.50 (2356)` |
  | 7.30.1（2284） | `UPDATE 7.30 → 7.50` | `UPDATE 7.30 (2284) → 7.50 (2356)` |
  | 7.50（2355） | `up to date`（漏报） | `UPDATE 7.50 (2355) → 7.50 (2356)` |
  | 7.50.1（2356） | `up to date` | `up to date` |

- 每次检查的额外流量，取自请求账本（`duo events --host cdn.istatmenus.app`，`duo verify --only istat` 一轮）：
  3 个 206 的 GET，响应体 1,024 + 4,096 + 2,120 = 7,240 B，另加每个约 0.4 KB 的响应头。
  第一轮实测这 3 行都记成了 `errorCode -999`：读够字节就 `break` 会取消任务，账本把它们当成被取消的请求。
  改成把 206 的响应体读到自然结束（超过所请求长度则拒绝）后复测，3 行都没有错误码。
- `verify/baseline.json` 里这条 recipe 的 `lastGoodVersion` 同步改成 `7.50`：`duo verify` 记的是 `shortVersion ?? version`，
  两版修法报出的都是包里的 `7.50`，而基线里存的是旧写法的 `7.50.1`，`Baseline.reconcile` 会把它报成「version went BACKWARDS」。


#### 2026-09-18（#713 收尾）：基线里的 `7.50.1` 一直没改掉

上一节最后一行写了「`verify/baseline.json` 里这条 recipe 的 `lastGoodVersion` 同步改成 `7.50`」，但实际没改进去。
后果正是那一行预言的：`Baseline.reconcile` 拿基线里的 `7.50.1` 对这次读到的 `7.50`，报「version went BACKWARDS」。

这个警报**自己永远清不掉**：倒退值按设计不写回基线（写回去下次就变成 7.50 比 7.50，静音在一条真坏了的 recipe 上），
所以基线一直攥着 `7.50.1`，每轮扫描都再报一次，连报四轮开了 #713。

改法：把 `vendor:com.bjango.istatmenus:stable` 的 `lastGoodVersion` 手工改成 `7.50`。
`7.50` 是第二版修法**正确**的输出——`.redirectArchiveInfoPlist` 读包内 `Info.plist`，`iStatMenus7.50.1.zip` 里的
`CFBundleShortVersionString` 就是 `7.50`（上表实测），而 `duo verify` 记的是 `shortVersion ?? version`。
2026-09-18 复核重定向仍指向 `iStatMenus7.50.1.zip`，即线上状态没变，要改的只是基线。
