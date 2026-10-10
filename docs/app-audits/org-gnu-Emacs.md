# Emacs for Mac OS X

**这不是审计**：family `org-gnu-Emacs`（`Recipes/org-gnu-Emacs.swift`）里 Emacs `org.gnu.Emacs` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-gnu-Emacs.swift — VendorProbe（一键 dmg 的挂载核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（dmg 里的 Emacs.app 是 org.gnu.Emacs、Team 5BRAQAFB8B、Notarized Developer ID，checked 2026-08-16），挂载的是哪个 dmg、读到的 `CFBundleShortVersionString` 搬到这里（上一段仍在代码里用 30.2-2 解释 `-N` 后缀的陷阱）。

One-click verified 2026-08-16 by mounting the 30.2-2 dmg: Emacs.app is
org.gnu.Emacs, CFBundleShortVersionString 30.2, Team 5BRAQAFB8B
(Galvanix), notarized Developer ID. The install pattern reuses the same
`<title>`-scoped entry's `<link type="binary/octet-stream">` href, so it
always fetches the dmg for the version just matched (suffix included,
since that's the real filename) rather than a template that would guess
wrong when a repack bumps only the suffix.

### changelogURL 改为首页 #Releases（2026-10-10）

接入前挂的是 `https://www.gnu.org/software/emacs/news/`，2026-10-10 GET 回来是 Apache 目录列表
（`Index of /software/emacs/news`）：每个版本一份纯文本 `NEWS.<x.y>`，HTML 版只有 `NEWS.28.html` 与
`NEWS.31.html`（没有 `NEWS.29.html`/`NEWS.30.html`），所以按大版本拼 `NEWS.<major>.html` 不可靠。
`https://www.gnu.org/software/emacs/` 的 `<h2 id="Releases">` 一节写着最新两个大版本的发布日期、要点和
`news/NEWS.<x.y>` 链接（当时：Emacs 31.1，Aug 24, 2026；baseline 提供的版本也是 31.1），页面注释说只保留
最近两个大版本——这是会随发布自动更新的稳定落点，于是改挂 `…/emacs/#Releases`。

注：这台机器经本机代理（`HTTPS_PROXY=127.0.0.1:6152`）访问 www.gnu.org 连接超时，`--noproxy '*'` 直连
0.8 s 返回 200；以上抓取都是直连。
