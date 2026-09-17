# iStat Menus

**这不是审计**：family `com-bjango-istatmenus`（`Recipes/com-bjango-istatmenus.swift`）里 iStat Menus `com.bjango.istatmenus` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/com-bjango-istatmenus.swift — VendorProbe（`download.istatmenus.app/istatmenus7/download/` 的重定向文件名）

#### 2026-09-17：小版本号只在文件名里，版本正则改为只取 MAJOR.MINOR

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
