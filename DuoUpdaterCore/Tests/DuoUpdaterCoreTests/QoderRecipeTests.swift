import Foundation
import Testing

@testable import DuoUpdaterCore

/// `center.qoder.sh/algo/api/update/darwin-arm64/stable/latest`, captured
/// verbatim 2026-09-06 (the whole response is 344 bytes).
private let qoderIDEUpdateFixture = #"""
{"url":"https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-arm64.zip","name":"1.28.0","version":"68cf4c38cec43130a7dccbadcf9e5e0902ef5549","productVersion":"1.28.0","hash":"d712c37efc09025fbbadfdd00e37f8093033667c","timestamp":1788277155505,"sha256hash":"52c46d6d5fed3a36b56ede60b9354ced9077c77809149a293c18b76e621b6f0e"}
"""#

/// The x64 answer from the same server, same second — kept because it is the one
/// thing an architecture-blind pattern would happily install on an arm64 Mac.
private let qoderIDEIntelUpdateFixture = #"""
{"url":"https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-x64.zip","name":"1.28.0","version":"68cf4c38cec43130a7dccbadcf9e5e0902ef5549","productVersion":"1.28.0","hash":"04f93753eadb31fb535d95aa9ff8c4a1c4d9101d","timestamp":1788277129713,"sha256hash":"74edb29015d01c80d795c1a840cbbb05b63107e3516b1aacd5334d7cd6519579"}
"""#

/// `download.qoder.com/qoder-app/releases/latest/manifest.json`, captured
/// verbatim 2026-09-06 and trimmed to the macOS artifacts plus the Windows one
/// that follows them — the Windows entry is the neighbour a loose install
/// pattern would reach.
private let qoderAppManifestFixture = #"""
{
  "schemaVersion": 1,
  "version": "0.1.8",
  "artifacts": [
    {
      "id": "mac-arm64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip",
      "sha256": "8f71bf3899b74d028253497fe47fe2dff7a54c9ed06369595b9b46d93a33a7e7"
    },
    {
      "id": "mac-x64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-x64.zip",
      "sha256": "25e349dedb5940fec1d8c802255f351af6e93f8911ae2d8c5583f7aeae062361"
    },
    {
      "id": "win-x64-user",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-win-x64-user.exe",
      "sha256": "10ce1b6861aa819f04d29d63e195dfd4cae4e85e7cf40d468120a781626853d7"
    }
  ]
}
"""#

/// The same manifest with its two macOS entries in the other order. Same bytes,
/// different order — the one thing about a JSON array that nothing guarantees,
/// and the only body on which an anchored install pattern differs from a loose
/// one (`.bodyPattern` takes the FIRST match).
private let qoderAppManifestIntelFirstFixture = #"""
{
  "schemaVersion": 1,
  "version": "0.1.8",
  "artifacts": [
    {
      "id": "mac-x64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-x64.zip",
      "sha256": "25e349dedb5940fec1d8c802255f351af6e93f8911ae2d8c5583f7aeae062361"
    },
    {
      "id": "mac-arm64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip",
      "sha256": "8f71bf3899b74d028253497fe47fe2dff7a54c9ed06369595b9b46d93a33a7e7"
    },
    {
      "id": "win-x64-user",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-win-x64-user.exe",
      "sha256": "10ce1b6861aa819f04d29d63e195dfd4cae4e85e7cf40d468120a781626853d7"
    }
  ]
}
"""#

/// The newest two entries of `docs.qoder.com/release-notes/desktop`, 2026-09-06,
/// **with the page header above them** — that preamble is not decoration, it is
/// what makes this fixture able to fail. Verbatim but for the SVG path data,
/// which is several hundred bytes of icon geometry and says nothing about the
/// shape being parsed.
private let qoderIDENotesFixture = #"""
<div class="eyebrow text-caption-c1 text-primary-550">Release Notes</div><header class="mt-2.5 space-y-2.5"><div class="flex flex-col sm:flex-row items-start sm:items-center relative gap-12 min-w-0 justify-between"><h1 id="page-title" class="page-title font-bold text-neutral-950 tracking-tight [overflow-wrap:anywhere]">IDE Release Notes</h1><div class="hidden lg:flex"><div id="page-context-menu" class="relative flex items-center shrink-0 min-w-[143px] justify-end "><div class="flex min-h-15 items-stretch overflow-hidden rounded-[var(--adoc-radius-sm,8px)] border border-line-200 bg-background-light"><button type="button" id="page-context-menu-button" aria-label="Copy page" data-tracker-params="adoc_docs_copy_page" class="flex items-center rounded-none rounded-l-[var(--adoc-radius-sm,8px)] border-r border-line-200 pl-6 pr-4 py-3 font-normal text-neutral-950 transition-colors duration-150 cursor-pointer hover:bg-neutral-150"><div class="flex h-10 items-center gap-2"><svg aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="…"></path></svg><span class="text-[14px] leading-[20px] text-neutral-750">Copy page</span></div></button><button aria-label="More actions" aria-haspopup="menu" aria-expanded="false" type="button" data-tracker-params="adoc_docs_copy_page_more" class="group flex items-center justify-center rounded-none rounded-r-[var(--adoc-radius-sm,8px)] pl-4 pr-6 py-3 transition-colors duration-150 text-neutral-950 cursor-pointer hover:bg-neutral-150 "><span class="inline-flex h-10 items-center justify-center"><svg aria-hidden="true"><path d="…"></path></svg></span></button></div></div></div></div></header><article class="w-full overflow-x-visible mx-auto" style="max-width:var(--adoc-content-max-width-wide)"><div class="prose content mt-4 text-[14px] leading-[22px]"><p class="m-0" node="[object Object]">Release history for IDE.</p></div><div class="flex lg:hidden mt-4"><div id="page-context-menu" class="relative flex items-center shrink-0 min-w-[143px] justify-end "><div class="flex min-h-15 items-stretch overflow-hidden rounded-[var(--adoc-radius-sm,8px)] border border-line-200 bg-background-light"><button type="button" id="page-context-menu-button" aria-label="Copy page" data-tracker-params="adoc_docs_copy_page" class="flex items-center rounded-none rounded-l-[var(--adoc-radius-sm,8px)] border-r border-line-200 pl-6 pr-4 py-3 font-normal text-neutral-950 transition-colors duration-150 cursor-pointer hover:bg-neutral-150"><div class="flex h-10 items-center gap-2"><svg aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="…"></path></svg><span class="text-[14px] leading-[20px] text-neutral-750">Copy page</span></div></button><button aria-label="More actions" aria-haspopup="menu" aria-expanded="false" type="button" data-tracker-params="adoc_docs_copy_page_more" class="group flex items-center justify-center rounded-none rounded-r-[var(--adoc-radius-sm,8px)] pl-4 pr-6 py-3 transition-colors duration-150 text-neutral-950 cursor-pointer hover:bg-neutral-150 "><span class="inline-flex h-10 items-center justify-center"><svg aria-hidden="true"><path d="…"></path></svg></span></button></div></div></div><div class="adoc-mdx-content"><div class="prose content dark:prose-invert max-w-none mt-6"><span data-as="p">This page lists the release history for IDE, with the newest version first.</span>
<div id="1280-2026-09-02"></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="september-2-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#september-2-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">September 2, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.28.0</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Improvements</h3><ul>
<li>Increased the tool execution limit for single tasks in Qoder IDE to 500 rounds, making complex long-chain tasks less likely to be interrupted prematurely.</li>
<li>Tasks interrupted due to depleted credits can now be manually resumed by clicking continue after credits are restored.</li>
</ul></div></div></div>
<div id="1270-2026-08-29"></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="august-29-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#august-29-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">August 29, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.27.0</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Improvements</h3><ul>
<li>Added an enterprise control to disable external network access from the built-in browser, helping organizations meet security and operational management requirements.</li>
<li>Personal edition BYOK now supports OpenAI, Google, and OpenRouter providers, enabling model services to be connected as needed.</li>
</ul></div></div></div>
"""#

/// The newest entry of `docs.qoder.com/release-notes/qoder`, same day and same
/// trim. Note the version reads "Qoder 0.1.8" here where the IDE page's reads a
/// bare "1.28.0".
private let qoderAppNotesFixture = #"""
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="september-5-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#september-5-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">September 5, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">Qoder 0.1.8</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Custom Base URLs for BYOK</h3><h4>Features</h4><ul>
<li><strong>Custom BYOK endpoints</strong>: Personal plan BYOK now supports custom Base URLs for any OpenAI- or Anthropic-compatible model service.</li>
</ul><h4>Improvements</h4><ul>
<li><strong>Workspace Search</strong>: You can now search for content directly within the Markdown preview.</li>
<li><strong>Installer</strong>: Better process detection and install recovery on Windows</li>
<li><strong>Extension Market</strong>: Smoother category switching and detail layout</li>
</ul><h4>Fixes</h4><ul>
<li>Fixed messages lost after repeated context compression</li>
<li>Fixed MCP OAuth negotiation failure diagnostics</li>
<li>Fixed Worktree init failure with no retry option</li>
<li>Fixed voice input floating window position not preserved</li>
</ul></div></div></div>
"""#

/// The same two releases as they appear in the Next.js RSC payload the SAME page
/// also carries, verbatim (2026-09-06). Kept so the claim about it stays honest:
/// see `theRSCPayloadCopyAddsNoEntries` for what it does and does not threaten.
private let qoderRSCPayloadFixture = #"""
\"content\":[[\"$\",\"span\",null,{\"data-as\":\"p\",\"children\":\"This page lists the release history for IDE, with the newest version first.\"}],\"\\n\",[\"$\",\"div\",null,{\"id\":\"1280-2026-09-02\"}],\"\\n\",[\"$\",\"$L19\",null,{\"id\":\"september-2-2026\",\"label\":\"September 2, 2026\",\"description\":\"1.28.0\",\"tags\":\"$undefined\",\"isVisible\":true,\"children\":[[\"$\",\"h3\",null,{\"children\":\"Improvements\"}],[\"$\",\"ul\",null,{\"children\":[\"\\n\",[\"$\",\"li\",null,{\"children\":\"Increased the tool execution limit for single tasks in Qoder IDE to 500 rounds, making complex long-chain tasks less likely to be interrupted prematurely.\"}],\"\\n\",[\"$\",\"li\",null,{\"children\":\"Tasks interrupted due to depleted credits can now be manually resumed by clicking continue after credits are restored.\"}],\"\\n\"]}]]}],\"\\n\",[\"$\",\"div\",null,{\"id\":\"1270-2026-08-29\"}],\"\\n\",[\"$\",\"$L19\",null,{\"id\":\"august-29-2026\",\"label\":\"August 29, 2026\",\"description\":\"1.27.0\",\"tags\":\"$undefined\",\"isVisible\":true,\"children\":[[\"$\",\"h3\",null,{\"children\":\"Improvements\"}],[\"$\",\"ul\",null,{\"children\":[\"\\n\",[\"$\",\"li\",null,{\"children\":\"Added an enterprise control to disable external network access from the built-in browser, helping organizations meet security and operational management requirements.\"}],\"\\n\",[\"$\",\"li\",null,{\"children\":\"Personal edition BYOK now supports OpenAI, Google, and OpenRouter providers, enabling model services to
"""#

/// The newest two entries of `docs.qoder.cn/product-overview/qoder-update-log`
/// (Qoder CN), 2026-09-22, verbatim but for the SVG path data. Same docs build
/// as the global pages; the dates are Chinese ("2026年09月20日") and the 0.3.3
/// entry carries a `<video>` inside one of its `<li>`s.
private let qoderCNNotesFixture = #"""
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="2026-09-20"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#2026-09-20">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">2026年09月20日</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">Qoder 0.3.4</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>日常优化</h3><h4>修复</h4><ul>
<li>修复安全相关问题。</li>
</ul></div></div></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="2026-09-18"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#2026-09-18">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">2026年09月18日</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">Qoder 0.3.3</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Sites：通过对话创建和发布网站</h3><h4>功能</h4><ul>
<li><strong>Sites 建站</strong>：支持选择模板，通过对话创建网站，并在桌面端内预览、发布和管理站点。<!-- -->
<video src="https://download.qoder.com/assets/changelog/283/1789571870033_4bbb52b6.mp4" controls="" loop="" muted="" playsInline="" style="max-width:100%;border-radius:8px"></video>
</li>
<li><strong>PPT 创建与编辑</strong>：支持在桌面端内打开工作区中的 PPTX 文件，直接编辑并保存，可在扩展-插件市场下载PPT插件获得更好的体验。</li>
<li><strong>电脑操控</strong>：升级至 Computer Use 2.0，带来更流畅的使用体验，并支持 Linux 系统。在设置-电脑操作中开启后即可体验。</li>
<li><strong>成就贴纸</strong>：新增 7 枚成就贴纸，随使用逐步解锁，等你探索收集。</li>
<li><strong>回复批注</strong>：在设置-实验功能中开启后，可划选 Agent 回复中的文字并添加到输入框，附加评论，并在后续回复中回引对应批注。</li>
</ul><h4>优化</h4><ul>
<li><strong>语音输入</strong>：支持在输入框内长按鼠标进行语音输入，松开后将转写内容保留在输入框，方便编辑后发送。</li>
<li><strong>发送快捷键</strong>：支持在设置中选择使用 Enter 或 Cmd/Ctrl+Enter 发送消息。</li>
<li><strong>Remote Control</strong>：支持自动同步最近 7 天内更新的本地会话历史，并优化增量同步，减少重复传输。</li>
<li><strong>Worktree</strong>：优化大型仓库的起点列表加载和创建准备，减少本地改动较多时出现的加载或创建失败。</li>
</ul><h4>修复</h4><ul>
<li>修复升级后 Remote Control 无法恢复连接，以及重新连接时旧消息可能被重复执行的问题。</li>
<li>修复 Side Chat 首轮回复无法正确继承来源会话上下文的问题。</li>
<li>修复会话压缩期间发送消息后，回复可能无法显示的问题。</li>
<li>修复 Windows 更新后，任务栏固定入口仍可能打开旧版本的问题。</li>
</ul></div></div></div>
"""#

/// `Qoder CN.app/Contents/Resources/app-update.yml` from the 0.3.4 bundle
/// (the payload of `Qoder-CN-Installer-mac-arm64.zip`), verbatim.
private let qoderCNUpdateConfigFixture = #"""
provider: generic
url: https://static.qoder.com.cn/qoder-app/releases
updaterCacheDirName: qoder-cn-updater
"""#

/// `static.qoder.com.cn/qoder-app/releases/latest-mac.yml`, verbatim
/// 2026-09-22 — what that config makes the app's own updater read.
private let qoderCNLatestMacFixture = #"""
version: 0.3.4
files:
  - url: https://static.qoder.com.cn/qoder-app/releases/0.3.4/Qoder-CN-mac-arm64.zip
    sha512: t+v5C9YNx4fIh7FjKjcrAYOmRbBLAY/fHFPzMqB/LbIBhI4gbJdN9gN0WdjJXAH8pCuCbloJMao0tWoRZ9fJ2w==
    sha256: c6a93ef668864a7d662b6b86a2fa4fef1c427280cb0317177b867ce194ae6679
    size: 255505455
path: Qoder-CN-mac-arm64.zip
sha512: t+v5C9YNx4fIh7FjKjcrAYOmRbBLAY/fHFPzMqB/LbIBhI4gbJdN9gN0WdjJXAH8pCuCbloJMao0tWoRZ9fJ2w==
releaseDate: 2026-09-19T08:53:03.284Z
releaseId: 0.3.4
commit: 081b9000518bbd81daf8108840085007425d9bb9
buildNumber: "73913403"
buildKind: official
differential:
  blockmapUrl: https://static.qoder.com.cn/qoder-app/releases/0.3.4/Qoder-CN-mac-arm64.zip.blockmap
  sha256: 2dcb1460686c98b19bfd525f42f6deb9746a05959f22b4f3b4903af98f90dcab
  size: 267344
releaseNotes: {}
"""#

/// `lingma-api.tongyi.aliyun.com/algo/api/qodercn/update/darwin-arm64/stable/latest`
/// (Qoder CN IDE), verbatim 2026-09-22 — one of the two answers it alternated
/// between that day. Note `url`: the moving `lastest` alias, which the CDN edge
/// was still serving as 1.31.1 while this said 1.31.2.
private let qoderCNIDEUpdateFixture = #"""
{"url":"https://ide.qoder.com.cn/qoder/release/lastest/QoderCN-darwin-arm64.zip","name":"QoderCN","version":"fcfc01753018885dfe7894f2e5a8013cb500c629","productVersion":"1.31.2","hash":"a3203c350f11903c8a402bd8d2837fcc3204d2d9","timestamp":1790004402000,"sha256hash":"e32e221825aabdd8b0f0abfea47a6c9a9dce212cfcfecbb715d35a1dd19ae971"}
"""#

/// The newest two entries of `docs.qoder.cn/product-overview/qoder-cn-ide-update-log`,
/// 2026-09-22, verbatim but for the SVG path data. Bare versions, Chinese dates.
private let qoderCNIDENotesFixture = #"""
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="2026-09-18"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#2026-09-18">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">2026年09月18日</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.31.0</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>日常优化</h3><h4>优化</h4><ul>
<li><strong>Editor 视窗增加 Experts 入口</strong>：支持在 Editor 视窗使用 Experts 专家团模式。</li>
<li><strong>启动与响应更快</strong>：减少 Shell 环境的重复采集与本地连接等待，Skill 监听不再阻塞新建会话；冷启动先展示对话面板，历史记录在后台恢复。</li>
<li><strong>长会话内存占用更低</strong>：及时回收闲置的文件编辑资源，清理 Markdown、终端标签与消息流的冗余持有，并完善图片预览的资源限制与关闭逻辑。</li>
<li><strong>自动重试过程可见</strong>：模型请求失败或繁忙时会自动重试，同时透出重试状态，便于随时了解进度。</li>
</ul><h4>修复</h4><ul>
<li>修复短暂断连后聊天记录无法自动恢复的问题，并优化重开历史提问的续跑逻辑。</li>
<li>修复登录回跳与跨窗口更新重启的异常，减少因可恢复的等待任务而触发的退出确认。</li>
<li>修复子 Agent 命令在特定场景下被误路由的问题。</li>
<li>修复 Windows 终端输出乱码与文件重复显示的问题。</li>
</ul></div></div></div>
<div id="v1301-2026-09-15-日常优化"></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="2026-09-15"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#2026-09-15">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">2026年09月15日</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.30.1</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>日常优化</h3><ul>
<li>优化长会话页面性能。</li>
<li>Qoder CN IDE 启动时默认进入 Editor 视窗。</li>
<li>优化 Agent 响应前的准备流程，减少无效等待，提升首次响应速度与会话流畅度。</li>
<li>优化首包超时时的提示信息，让等待原因与后续操作更清晰易懂。</li>
<li>提升 WSL 启动速度与连接稳定性。</li>
</ul></div></div></div>
<div id="v1290-2026-09-08-qoder-security-企业安全治理升级"></div>
"""#

@Suite struct QoderRecipeTests {

    private func probe(_ bundleID: String) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    private func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern for \(recipe.bundleID)")
            return ""
        }
        #expect(spec.kind == .zip)
        return pattern
    }

    // MARK: - Qoder IDE

    /// `productVersion`, not `name` and emphatically not `version` — the last is
    /// the commit. A pattern that drifted onto it would compare a 40-hex string
    /// against `1.27.0` forever, which is the one failure this app can produce
    /// that still looks like a working recipe.
    ///
    /// The real response cannot tell `name` from `productVersion` — they read
    /// "1.28.0" and "1.28.0" — so on it alone a pattern keyed to either field
    /// passes, which is `f(X) == f(X)`, not a test. The second body below is the
    /// real fixture with ONE field changed to what the protocol permits there:
    /// `name` is the field a vendor may put a human string in. A pattern reading
    /// `name` returns nil on it; the shipped one still returns 1.28.0.
    @Test func ideReadsProductVersionRatherThanTheCommit() throws {
        let recipe = try probe("com.qoder.ide")
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderIDEUpdateFixture, pattern: recipe.versionPattern) == "1.28.0")

        let humanName = qoderIDEUpdateFixture.replacingOccurrences(
            of: #""name":"1.28.0""#, with: #""name":"Qoder 1.28 (September)""#)
        #expect(humanName != qoderIDEUpdateFixture)
        #expect(VendorProbeRecipe.extractVersion(
            from: humanName, pattern: recipe.versionPattern) == "1.28.0")
        // What the mutant would do on the same body.
        #expect(VendorProbeRecipe.extractVersion(
            from: humanName,
            pattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#) == nil)
        // And the commit field is not a version by any reading.
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderIDEUpdateFixture,
            pattern: recipe.versionPattern) != "68cf4c38cec43130a7dccbadcf9e5e0902ef5549")
    }

    /// The endpoint is conditional — it answers 204 with an EMPTY BODY when the
    /// commit you name is already newest — so the request has to be the
    /// unconditional `latest` sentinel and never this machine's commit. An empty
    /// body must read as a failure, not as "up to date".
    @Test func ideAsksTheUnconditionalLatestSentinel() throws {
        let recipe = try probe("com.qoder.ide")
        #expect(recipe.url.absoluteString
            == "https://center.qoder.sh/algo/api/update/darwin-arm64/stable/latest"
            + "?machineId=__IDENTITY__")
        // The property that matters is not "the URL ends in latest" but "the last
        // segment is not a commit" — a 40-hex tail is what turns the endpoint
        // conditional, and it is the only thing that could get put there.
        #expect(recipe.url.lastPathComponent.range(
            of: "^[0-9a-f]{40}$", options: .regularExpression) == nil)
        // Nor may a commit be smuggled in anywhere else in the path.
        #expect(recipe.url.absoluteString.range(
            of: "[0-9a-f]{40}", options: .regularExpression) == nil)
    }

    /// The install spec takes the zip the API itself names, and only the arm64
    /// one: the same server answers `/darwin/stable/latest` with a byte-identical
    /// document whose only difference is `darwin-x64` in the URL.
    @Test func ideInstallsTheArm64ZipTheAPINames() throws {
        let recipe = try probe("com.qoder.ide")
        let pattern = try installPattern(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: qoderIDEUpdateFixture, pattern: pattern)
            == "https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-arm64.zip")
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderIDEIntelUpdateFixture, pattern: pattern) == nil)
    }

    /// `timestamp` is epoch MILLISECONDS; `ReleaseDate` reads that window as ms,
    /// so the row gets an exact publish time rather than a date in 58 700 AD.
    @Test func ideReadsTheEpochMillisecondTimestamp() throws {
        let recipe = try probe("com.qoder.ide")
        let pattern = try #require(recipe.publishedAtPattern)
        let stamp = try #require(
            VendorProbeRecipe.extractVersion(from: qoderIDEUpdateFixture, pattern: pattern))
        #expect(stamp == "1788277155505")
        let parsed = try #require(ReleaseDate.parse(stamp))
        #expect(abs(parsed.timeIntervalSince1970 - 1_788_277_155.505) < 1)
    }

    // MARK: - Qoder (the app)

    /// `"version"` must not be satisfied by `"schemaVersion"`, whose value is the
    /// unquoted integer 1 — a pattern that matched it would report "1" as the
    /// app's version and never move again.
    /// `"schemaVersion"` sits ABOVE `"version"` in the document and `.bodyPattern`
    /// takes the first match, so this is the neighbour that matters. Three things
    /// keep it out, and it is worth knowing which is load-bearing:
    /// `extractVersion` compiles the pattern with NO options, so the match is
    /// case-sensitive and `schemaVersion` spells it `Version`; the key is matched
    /// with its own opening quote; and its value is an unquoted integer. The
    /// second body below removes the third of those — a quoted schema version —
    /// and the shipped pattern still answers 0.1.8, while the loosened
    /// `[Vv]ersion` form that survives all three answers "1.0".
    @Test func appReadsTheManifestVersionAndNotTheSchemaVersion() throws {
        let recipe = try probe("com.qoder.app")
        #expect(qoderAppManifestFixture.contains(#""schemaVersion": 1"#))
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderAppManifestFixture, pattern: recipe.versionPattern) == "0.1.8")

        let quotedSchema = qoderAppManifestFixture.replacingOccurrences(
            of: #""schemaVersion": 1,"#, with: #""schemaVersion": "1.0","#)
        #expect(quotedSchema != qoderAppManifestFixture)
        #expect(VendorProbeRecipe.extractVersion(
            from: quotedSchema, pattern: recipe.versionPattern) == "0.1.8")
        // What a pattern without the leading quote would answer on the same body.
        #expect(VendorProbeRecipe.extractVersion(
            from: quotedSchema, pattern: #"[Vv]ersion"\s*:\s*"([0-9]+(?:\.[0-9]+)*)""#) == "1.0")
    }

    /// arm64 only — and the arm64 entry being FIRST in the vendor's array is why
    /// the happy path alone proves nothing: `.bodyPattern` takes the first match,
    /// so a pattern loosened to any artifact would return the same URL. The
    /// second body reorders the array the way the vendor is free to at any time;
    /// only an anchored pattern still answers arm64 there.
    @Test func appInstallsTheArm64ZipTheManifestNames() throws {
        let recipe = try probe("com.qoder.app")
        let pattern = try installPattern(recipe)
        let arm64 = "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip"
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderAppManifestFixture, pattern: pattern) == arm64)

        #expect(qoderAppManifestIntelFirstFixture.range(of: "mac-x64")!.lowerBound
            < qoderAppManifestIntelFirstFixture.range(of: "mac-arm64")!.lowerBound)
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderAppManifestIntelFirstFixture, pattern: pattern) == arm64)
    }


    /// The manifest is served from `download.qoder.com` and names artifacts on
    /// `download.qoder.com.cn`. Both hosts serve the same object, and the vendor's
    /// own installer fetches the `.cn` one, so the pattern accepts either rather
    /// than pinning whichever host we happened to fetch the manifest from.
    @Test func appAcceptsEitherOfTheVendorsTwoDownloadHosts() throws {
        let recipe = try probe("com.qoder.app")
        let pattern = try installPattern(recipe)
        let comHost = qoderAppManifestFixture.replacingOccurrences(
            of: "download.qoder.com.cn", with: "download.qoder.com")
        #expect(VendorProbeRecipe.extractVersion(from: comHost, pattern: pattern)
            == "https://download.qoder.com/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip")
    }

    /// Two products, two bundle ids, two Team IDs — and so two recipes that must
    /// never be collapsed into one. The Teams are the vendor's own statement, from
    /// the installer stub's `installer-manifest.json`.
    @Test func theTwoProductsAreSeparateRecipesOnSeparateEndpoints() throws {
        let ide = try probe("com.qoder.ide")
        let app = try probe("com.qoder.app")
        #expect(ide.url.host != app.url.host)
        #expect(ide.changelogURL != app.changelogURL)
    }

    // MARK: - Release notes

    private func notes(_ bundleID: String, _ fixture: String) throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
        #expect(recipe.source.host == "docs.qoder.com")
        return try #require(ChangelogExtractor.extract(from: fixture, using: recipe))
    }

    @Test func ideNotesParseVersionDateAndBullets() throws {
        let log = try notes("com.qoder.ide", qoderIDENotesFixture)
        #expect(log.entries.map(\.version) == ["1.28.0", "1.27.0"])
        #expect(log.entries.first?.date == "September 2, 2026")
        #expect(log.entries.first?.items.count == 2)
        #expect(log.entries.first?.items.first?.hasPrefix(
            "Increased the tool execution limit") == true)
    }

    /// The app's page prefixes its version with the product name; the shared
    /// pattern makes that optional, so "Qoder 0.1.8" still yields "0.1.8" — not
    /// "0.1.8" prefixed, and not nothing.
    @Test func appNotesStripTheProductNameFromTheVersion() throws {
        let log = try notes("com.qoder.app", qoderAppNotesFixture)
        #expect(log.entries.map(\.version) == ["0.1.8"])
        #expect(log.entries.first?.date == "September 5, 2026")
        // Three `<ul>`s under three `<h4>`s: 1 feature + 3 improvements + 4 fixes.
        #expect(log.entries.first?.items.count == 8)
        #expect(log.entries.first?.items.contains {
            $0.contains("Fixed messages lost after repeated context compression")
        } == true)
    }

    /// The docs page also embeds a Next.js RSC payload repeating every release in
    /// JSON-escaped form, so it is worth saying exactly what protects against it —
    /// and it is NOT the `data-component-part` anchors. Measured 2026-09-06: that
    /// payload spells its fields as `\"description\":\"1.28.0\"` and contains no
    /// `</div>` at all, so the entry pattern's element structure alone excludes it.
    /// Appending it to a real page's entries changes neither the count nor the
    /// versions.
    @Test func theRSCPayloadCopyAddsNoEntries() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        #expect(qoderRSCPayloadFixture.contains("1.28.0"))
        #expect(!qoderRSCPayloadFixture.contains("</div>"))
        #expect(ChangelogExtractor.extract(from: qoderRSCPayloadFixture, using: recipe) == nil)
        let combined = qoderIDENotesFixture + "\n" + qoderRSCPayloadFixture
        let log = try #require(ChangelogExtractor.extract(from: combined, using: recipe))
        #expect(log.entries.map(\.version) == ["1.28.0", "1.27.0"])
    }

    /// An entry that loses one of its three parts must not be able to borrow it
    /// from the NEXT release. With a plain `.*?` between the parts it can, and
    /// the damage is worse than a missing entry: measured on this fixture with
    /// one `update-description` attribute renamed, the untempered pattern returns
    /// a single entry reading `1.27.0` against `September 2, 2026` — a version
    /// and a date from two different releases — and 1.28.0 vanishes from the
    /// pane. The tempered gaps refuse to cross the next release's container, so
    /// the damaged entry is dropped and the intact one keeps its own date.
    @Test func aDamagedEntryCannotBorrowPartsFromTheNextRelease() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        let damaged = qoderIDENotesFixture.replacingOccurrences(
            of: #"data-component-part="update-description">1.28.0</div>"#,
            with: #"data-component-part="update-renamed">1.28.0</div>"#)
        #expect(damaged != qoderIDENotesFixture)
        let log = try #require(ChangelogExtractor.extract(from: damaged, using: recipe))
        #expect(log.entries.map(\.version) == ["1.27.0"])
        #expect(log.entries.first?.date == "August 29, 2026")
    }

    /// The other damage mode, and the worse one: lose the `update-content`
    /// attribute and the untempered pattern keeps the newest release's version
    /// AND date while pulling the SECOND-newest release's bullets under them —
    /// measured `1.28.0 / September 2, 2026` carrying 1.27.0's two items. Nothing
    /// on screen looks wrong; the notes are simply the wrong release's. The
    /// tempered gaps drop the damaged entry instead.
    @Test func aDamagedEntryCannotBorrowTheNextReleasesNotes() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        let damaged = qoderIDENotesFixture.replacingOccurrences(
            of: #"data-component-part="update-content">"#,
            with: #"data-component-part="update-renamed">"#,
            options: [], range: qoderIDENotesFixture.range(
                of: #"data-component-part="update-content">"#))
        #expect(damaged != qoderIDENotesFixture)
        let log = try #require(ChangelogExtractor.extract(from: damaged, using: recipe))
        #expect(log.entries.map(\.version) == ["1.27.0"])
        #expect(log.entries.first?.date == "August 29, 2026")
        #expect(log.entries.first?.items.count == 2)
    }

    /// The tempering sentinel must be the vendor's semantic attribute, not the
    /// `update update-container` class the entries happen to sit in. Both work on
    /// today's page and on a damaged entry — the difference only shows when the
    /// vendor restyles: with the class renamed AND an entry damaged, a
    /// class-tempered gap degrades back to `.*?` and pairs 1.28.0's date with
    /// 1.27.0's version, silently. Nothing else in this suite separates the two
    /// choices, which is why this case exists.
    @Test func theTemperingSentinelSurvivesTheVendorRestylingItsClasses() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        let restyled = qoderIDENotesFixture
            .replacingOccurrences(of: #"class="update update-container"#,
                                  with: #"class="release-block"#)
            .replacingOccurrences(of: #"data-component-part="update-description">1.28.0</div>"#,
                                  with: #"data-component-part="update-renamed">1.28.0</div>"#)
        #expect(!restyled.contains("update update-container"))
        let log = try #require(ChangelogExtractor.extract(from: restyled, using: recipe))
        #expect(log.entries.map(\.version) == ["1.27.0"])
        #expect(log.entries.first?.date == "August 29, 2026")
    }

    /// The newest entry's date must be its own label, not the page's own
    /// `<div class="eyebrow">Release Notes</div>` header, which sits above every
    /// entry and is the nearest `>…</div>` a loose pattern reaches first.
    ///
    /// ⚠️ This is NOT a test of the `data-component-part` anchors, though it was
    /// named as one when it was written. Measured afterwards: with the gaps
    /// tempered, stripping the three attribute prefixes changes nothing here — the
    /// tempering sentinel IS the label attribute, so it does this job now, and
    /// this case passes under that mutant. What it does pin is the outcome, which
    /// is worth pinning on its own: both mechanisms could be lost at once. The
    /// anchors themselves are pinned by the two damage cases above.
    @Test func theNewestEntrysDateIsItsOwnLabelNotThePageHeader() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        #expect(qoderIDENotesFixture.contains(#">Release Notes</div>"#))
        let log = try #require(ChangelogExtractor.extract(from: qoderIDENotesFixture, using: recipe))
        #expect(log.entries.first?.date == "September 2, 2026")
        #expect(log.entries.first?.date != "Release Notes")
    }

    // MARK: - Qoder CN

    /// Qoder CN has no version recipe on purpose: its bundle names its own
    /// electron-updater feed, and `ElectronManifestSource` reads that. These pin
    /// the two real files that path depends on — the config resolves to the
    /// manifest the app's updater reads, and the manifest yields the arm64 zip
    /// with a checksum, which is what makes it installable at all.
    @Test func qoderCNIsCoveredByItsOwnElectronFeed() throws {
        #expect(!VendorProbeRegistry.recipes.contains { $0.bundleID == "com.qodercn.app" })

        let config = try #require(ElectronUpdateConfig.parse(qoderCNUpdateConfigFixture))
        #expect(config.manifestURL?.absoluteString
            == "https://static.qoder.com.cn/qoder-app/releases/latest-mac.yml")

        let manifest = try #require(ElectronManifest.parse(qoderCNLatestMacFixture))
        #expect(manifest.version == "0.3.4")
        let file = try #require(manifest.artifact(forArch: "arm64"))
        #expect(file.url
            == "https://static.qoder.com.cn/qoder-app/releases/0.3.4/Qoder-CN-mac-arm64.zip")
        #expect(file.sha512?.isEmpty == false)
    }

    /// The CN page is the same docs build, so the shared pattern reads it — and
    /// the Chinese date comes through as the entry's own label, as text.
    @Test func qoderCNNotesParseOnTheSharedPattern() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qodercn.app"))
        #expect(recipe.source.host == "docs.qoder.cn")
        let log = try #require(ChangelogExtractor.extract(from: qoderCNNotesFixture, using: recipe))
        #expect(log.entries.map(\.version) == ["0.3.4", "0.3.3"])
        #expect(log.entries.map(\.date) == ["2026年09月20日", "2026年09月18日"])
        #expect(log.entries.first?.items == ["修复安全相关问题。"])
        // 5 功能 + 4 优化 + 4 修复, under three `<h4>`s.
        #expect(log.entries.last?.items.count == 13)
        #expect(log.entries.last?.items.first?.contains("Sites 建站") == true)
    }

    /// A third product, not a mirror: its own bundle id AND its own notes page.
    /// Collapsing it onto `com.qoder.app` would show the global app's notes to
    /// a CN install.
    @Test func qoderCNIsNotTheGlobalApp() throws {
        let cn = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qodercn.app"))
        let global = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.app"))
        #expect(cn.source != global.source)
    }

    // MARK: - Qoder CN IDE

    /// `productVersion` — `name` is "QoderCN" and `version` is the commit.
    @Test func qoderCNIDEReadsProductVersion() throws {
        let recipe = try probe("com.aliyun.lingma.ide")
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderCNIDEUpdateFixture, pattern: recipe.versionPattern) == "1.31.2")
        let stampPattern = try #require(recipe.publishedAtPattern)
        let stamp = try #require(VendorProbeRecipe.extractVersion(
            from: qoderCNIDEUpdateFixture, pattern: stampPattern))
        #expect(stamp == "1790004402000")
    }

    /// The `qodercn` path, asked with `latest`. The plain VS Code path on the
    /// same host is a legacy table that answers "Lingma 0.11.4" to any commit
    /// it doesn't know — reading it would never report an update.
    @Test func qoderCNIDEAsksTheQoderCNTableNotTheLegacyOne() throws {
        let recipe = try probe("com.aliyun.lingma.ide")
        #expect(recipe.url.host == "lingma-api.tongyi.aliyun.com")
        #expect(recipe.url.path.hasSuffix("/api/qodercn/update/darwin-arm64/stable/latest"))
    }

    /// The install URL is built from the resolved version, never taken from the
    /// body: the body's `lastest` alias was measured serving the PREVIOUS
    /// release from the CDN edge while the API already answered the new one.
    @Test func qoderCNIDEInstallsTheVersionedZipNotTheMovingAlias() throws {
        let recipe = try probe("com.aliyun.lingma.ide")
        let spec = try #require(recipe.install)
        #expect(spec.kind == .zip)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("expected a version template"); return
        }
        #expect(qoderCNIDEUpdateFixture.contains("/release/lastest/"))
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: qoderCNIDEUpdateFixture, pattern: recipe.versionPattern))
        #expect(template.replacingOccurrences(of: "{version}", with: version)
            == "https://ide.qoder.com.cn/qoder/release/1.31.2/QoderCN-darwin-arm64.zip")
    }

    @Test func qoderCNIDENotesParseOnTheSharedPattern() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.aliyun.lingma.ide"))
        #expect(recipe.source.host == "docs.qoder.cn")
        let log = try #require(ChangelogExtractor.extract(from: qoderCNIDENotesFixture, using: recipe))
        #expect(log.entries.map(\.version) == ["1.31.0", "1.30.1"])
        #expect(log.entries.map(\.date) == ["2026年09月18日", "2026年09月15日"])
        #expect(log.entries.map(\.items.count) == [8, 5])
    }

    /// Four products under one name. The two IDEs share source and even commits,
    /// and must still never share a recipe: different bundle ids, Teams, update
    /// servers and notes pages.
    @Test func theTwoIDEsAreSeparateRecipes() throws {
        let global = try probe("com.qoder.ide")
        let cn = try probe("com.aliyun.lingma.ide")
        #expect(global.url.host != cn.url.host)
        #expect(global.changelogURL != cn.changelogURL)
    }

    // MARK: - Both IDEs: the rollout id

    /// A made-up id, shaped like the real one (sha256 hex).
    private static let machineID = String(repeating: "0123456789abcdef", count: 4)

    /// `storage.json` as VS Code writes it — the id among unrelated state.
    private func appSupport(_ directory: String, storage: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qoder-identity-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("\(directory)/User/globalStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let storage {
            try Data(storage.utf8).write(to: dir.appendingPathComponent("storage.json"))
        }
        return root
    }

    private func storageJSON(machineID: String, padding: Int = 0) -> String {
        #"{"telemetry.sqmId":"","telemetry.machineId":"\#(machineID)","#
            + #""telemetry.devDeviceId":"f24275e6-4ea8-4096-bd28-8120d30d42e5","#
            + #""windowsState":{"lastActiveWindow":{"folder":"\#(String(repeating: "x", count: padding))"}}}"#
    }

    /// Each IDE sends its OWN app's id, from its own data directory. Without
    /// it the server buckets every request afresh and the answer flaps; a
    /// recipe reading the other IDE's directory would still work on a Mac with
    /// both installed and quietly send the fixed fallback on one with only
    /// this one.
    @Test(arguments: [("com.qoder.ide", "Qoder", "center.qoder.sh"),
                      ("com.aliyun.lingma.ide", "QoderCN", "lingma-api.tongyi.aliyun.com")])
    func eachIDESendsItsOwnMachineID(bundleID: String, directory: String, host: String) throws {
        let recipe = try probe(bundleID)
        let identity = try #require(recipe.identities.first)
        #expect(recipe.identities.count == 1)
        let root = try appSupport(directory, storage: storageJSON(machineID: Self.machineID))
        let resolved = try #require(identity.resolve(recipe.url, applicationSupportDirectory: root))
        #expect(resolved.host == host)
        #expect(resolved.query == "machineId=\(Self.machineID)")

        let other = try appSupport(directory == "Qoder" ? "QoderCN" : "Qoder",
                                   storage: storageJSON(machineID: Self.machineID))
        #expect(identity.resolve(recipe.url, applicationSupportDirectory: other)?.query
            == "machineId=\(ProbeIdentity.vsCodeMachineIDFallback)")
    }

    /// Never launched → no `storage.json` → one fixed id, never a skip: a
    /// skipped recipe leaves the app unchecked, and on a sweep machine without
    /// the app, unwatched. Fixed rather than random so the answer is stable.
    @Test(arguments: ["com.qoder.ide", "com.aliyun.lingma.ide"])
    func aMissingStorageFileFallsBackToOneFixedID(bundleID: String) throws {
        let recipe = try probe(bundleID)
        let identity = try #require(recipe.identities.first)
        #expect(identity.fallback == ProbeIdentity.vsCodeMachineIDFallback)
        let expected = "machineId=\(ProbeIdentity.vsCodeMachineIDFallback)"
        let missing = try appSupport("Elsewhere", storage: nil)
        let blank = try appSupport(bundleID == "com.qoder.ide" ? "Qoder" : "QoderCN",
                                   storage: storageJSON(machineID: ""))
        for root in [missing, blank] {
            let resolved = try #require(identity.resolved(recipe.url, applicationSupportDirectory: root))
            #expect(resolved.url.query == expected)
            #expect(resolved.provenance == .fallback)
        }
    }

    /// VS Code stores a UUID when it could read no MAC; that is still the id
    /// the app sends, so it passes. Anything else is refused.
    @Test func theUUIDFallbackIsAcceptedAndOtherShapesAreNot() throws {
        let identity = ProbeIdentity.vsCodeMachineID(applicationSupportDirectory: "QoderCN")
        let uuid = "f24275e6-4ea8-4096-bd28-8120d30d42e5"
        #expect(identity.value(applicationSupportDirectory:
            try appSupport("QoderCN", storage: storageJSON(machineID: uuid))) == uuid)
        for bad in [String(Self.machineID.dropLast()), Self.machineID.uppercased(), "test"] {
            #expect(identity.value(applicationSupportDirectory:
                try appSupport("QoderCN", storage: storageJSON(machineID: bad))) == nil)
        }
    }

    /// The file holds window state and grows with use (70 KB measured); the
    /// 4 KB default identity cap would silently skip a long-used install.
    @Test func aLargeStorageFileIsStillRead() throws {
        let identity = ProbeIdentity.vsCodeMachineID(applicationSupportDirectory: "QoderCN")
        let root = try appSupport("QoderCN", storage: storageJSON(machineID: Self.machineID, padding: 200_000))
        #expect(identity.value(applicationSupportDirectory: root) == Self.machineID)
    }
}
