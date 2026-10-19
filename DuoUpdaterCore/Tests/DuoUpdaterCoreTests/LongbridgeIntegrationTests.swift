import Foundation
import Testing
@testable import DuoUpdaterCore

// Fixtures are trimmed slices of the REAL responses (fetched 2026-08-26), with
// the asset lists kept in the vendor's own order — linux, macos, windows — so the
// arch/channel anchors are exercised against the ordering they actually face
// rather than a two-asset document where any pattern would look correct.

private let longbridgeStableManifest = #"""
{"version":"0.19.1","created_at":"2026-08-20T10:13:36Z","published_at":"2026-08-20T07:46:53Z","release_notes":{"en":"### Improvements\r\n\r\n- Fixed an issue where the editor could quit unexpectedly.","zh-CN":"### 优化\r\n\r\n- 修复编辑器问题。"},"assets":[{"name":"longbridge-v0.19.1-linux-x86_64.AppImage","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-linux-x86_64.AppImage","sha256":"02723b20e480604b2e9f44137757bc9cb4397bf261eb87c543feeafd2d6fb426"},{"name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa"},{"name":"longbridge-v0.19.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-x86_64.dmg","sha256":"5d3325bd671735b4720e2ac7d232cedf9b4a8abf3953ff2247e17e54d9d134b5"},{"name":"longbridge-v0.19.1-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-windows-x86_64.exe","sha256":"1b0c1a1d9c0b2f3e4d5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e"}]}
"""#

// The preview manifest captured here (0.19.0-preview.1) carried NO `sha256` — a
// real structural difference from stable's at the time, preserved so the fixture
// cannot flatter the recipe.
private let longbridgePreviewManifest = #"""
{"version":"0.19.0-preview.1","created_at":"2026-08-19T06:25:22Z","published_at":"2026-08-19T09:45:23Z","release_notes":{"en":"### Improvements\r\n\r\n- **Quant**: Added an abbreviation input."},"assets":[{"name":"longbridge-v0.19.0-preview.1-linux-x86_64.AppImage","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-linux-x86_64.AppImage"},{"name":"longbridge-v0.19.0-preview.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-aarch64.dmg"},{"name":"longbridge-v0.19.0-preview.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-x86_64.dmg"},{"name":"longbridge-v0.19.0-preview.1-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-windows-x86_64.exe"}]}
"""#

/// `preview/latest.json` as served 2026-10-07 (1.0.0-preview.1), trimmed to the
/// linux deb and the two macOS dmgs: by then preview assets carried `sha256` too.
/// The aarch64 dmg downloaded that day hashed to its `sha256`.
private let longbridgePreviewManifestWithDigests = #"""
{"version":"1.0.0-preview.1","created_at":"2026-09-07T11:39:49Z","published_at":"2026-09-08T02:05:26Z","release_notes":{"en":"### New Features\r\n- Added a HoverCard on the attached-order switch."},"assets":[{"name":"longbridge-v1.0.0-preview.1-linux-x86_64.deb","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-linux-x86_64.deb","sha256":"90727a40b9c7a0b21ea422460fdf67a40eff37711f14cd7aaa2584c16815ac5a"},{"name":"longbridge-v1.0.0-preview.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-aarch64.dmg","sha256":"4c9aa9992675af7787756c83dda048beb0adb2bb0abefcaec53944572331bd02"},{"name":"longbridge-v1.0.0-preview.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-x86_64.dmg","sha256":"5ceca5c26a8ca522516975a8133911ad454dfa1a0f51578db84086d6caa78798"}]}
"""#

/// Stable's minor page `…/longbridge-pro/0.19` as served 2026-10-14, trimmed to
/// its two release sections: 0.19.1 first, then 0.19.0 with its figures dropped.
/// The page holds every patch release of its line, newest first.
private let longbridgeStableMinorPage = #"""
<main class="mx-auto"><section id="v0.19.1" class="release-section" data-release-section data-rail-version="0.19.1" data-rail-date="2026-08-20" data-rail-title="Fixes for editor crashes and stray scrollbars · August 20, 2026"><h2 class="text-[1.25rem] font-semibold tracking-tight">Fixes for editor crashes and stray scrollbars</h2><div class="mt-2"><div class="flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-[0.8125rem] text-ink-soft"><time datetime="2026-08-20T00:00:00.000Z" class="tnum">August 20, 2026</time></div></div><p class="mt-3 text-[0.9375rem] leading-relaxed text-ink-soft">Fixed an issue where the editor could quit unexpectedly in c</p><div class="prose mt-5"><h2 id="improvements">Improvements</h2>
<ul>
<li>Fixed an issue where the editor could quit unexpectedly in certain syntax highlighting cases — editing content with multi-byte characters such as Chinese is now more stable.</li>
<li>Fixed vertical lists occasionally showing an unnecessary horizontal scrollbar — overlong text now truncates correctly to the actual list width.</li>
</ul></div></section><section id="v0.19.0" class="release-section" data-release-section data-rail-version="0.19.0" data-rail-date="2026-08-19" data-rail-title="Screener, quant workbench and grid trading · August 19, 2026"><h2 class="text-[1.25rem] font-semibold tracking-tight">Screener, quant workbench and grid trading</h2><div class="mt-2"><div class="flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-[0.8125rem] text-ink-soft"><time datetime="2026-08-19T00:00:00.000Z" class="tnum">August 19, 2026</time></div></div><p class="mt-3 text-[0.9375rem] leading-relaxed text-ink-soft">Screener：Added a stock screener with multi-dimensional filte</p><div class="prose mt-5"><h2 id="new-features">New Features</h2>
<p><strong>Screening &amp; quant</strong></p>
<ul>
<li><strong>Screener</strong>: Added a stock screener with multi-dimensional filters across markets, industries, themes, range indicators and technical indicators — range conditions can be dragged on the distribution chart, and a filter combination can be saved as a strategy for reuse.</li>
</ul>

<ul>
<li><strong>Quant</strong>: Added a quant workspace for authoring indicator and strategy scripts, chart syncing and strategy backtests; once a backtest finishes, the performance report, net value curve and buy/sell markers are all available.</li>
</ul>

<p><strong>Trading</strong></p>
<ul>
<li><strong>Grid Trading</strong>: Added grid trading — for stocks that move within a fluctuating range, set up a buy-low/sell-high strategy and let it run inside the price range you specify, and it can be paused, restarted, adjusted or terminated at any time.</li>
</ul>

<ul>
<li><strong>Trade</strong>: The take-profit/stop-loss ticket has been redesigned for a more intuitive way to set stop levels, and now supports dynamic “Full position” and “Trigger price” parameters that follow position changes automatically, for greater flexibility.</li>
</ul>

<p><strong>Monitoring &amp; research</strong></p>
<ul>
<li><strong>Quotes</strong>: Added quote change alerts to stock details, pushing that stock’s alerts such as limit-up and block trades in real time.</li>
</ul>

<ul>
<li><strong>Watchlist</strong>: The list view now supports drag-and-drop sorting, with pinned stocks reordered within the pinned segment, so there is no need to open group management to change the order.</li>
</ul>

<ul>
<li><strong>Chart</strong>: Drawings can now be locked per shape or globally, preventing accidental dragging of finished lines while reading charts, with the lock state kept in sync with mobile.</li>
<li><strong>Layout</strong>: Added an adaptive layout to custom pages — widgets dragged in are arranged automatically and fit the screen size, for a more flexible layout.</li>
<li><strong>Financials</strong>: Added a “Financial Score” panel covering the latest rating, a five-dimension radar chart, score criteria details and the industry rating distribution, making it easy to see where a stock stands among its peers.</li>
</ul>

<h2 id="improvements">Improvements</h2>
<ul>
<li>Placing a US market order outside regular trading hours now shows a reminder with a one-click switch to a limit order, avoiding accidental market fills in pre-/post-market sessions.</li>
<li>Reconnecting and disconnected states now show a status indicator with manual retry, so a stalled quote feed is no longer left to guesswork.</li>
</ul></div></section></main>
"""#

/// The 0.19.0 section as served 2026-10-14, scripts dropped: a `<strong>`
/// category label, an `<img>` mid-list and six `<video>` clips with their
/// fallback text, the shape the video and image rules have to handle.
private let longbridgeStableRichSection = #"""
<main class="mx-auto"><section id="v0.19.0" class="release-section" data-release-section data-rail-version="0.19.0" data-rail-date="2026-08-19" data-rail-title="Screener, quant workbench and grid trading · August 19, 2026"><h2 class="text-[1.25rem] font-semibold tracking-tight">Screener, quant workbench and grid trading</h2><div class="mt-2"><div class="flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-[0.8125rem] text-ink-soft"><time datetime="2026-08-19T00:00:00.000Z" class="tnum">August 19, 2026</time></div></div><p class="mt-3 text-[0.9375rem] leading-relaxed text-ink-soft">Screener：Added a stock screener with multi-dimensional filte</p><div class="prose mt-5"><h2 id="new-features">New Features</h2>
<p><strong>Screening &amp; quant</strong></p>
<ul>
<li><strong>Screener</strong>: Added a stock screener with multi-dimensional filters across markets, industries, themes, range indicators and technical indicators — range conditions can be dragged on the distribution chart, and a filter combination can be saved as a strategy for reuse.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Screener：Added a stock screener with multi-dimensional filte"><source src="https://assets.lbkrs.com/uploads/eca49d71-c8f8-4f8a-bc37-30edb934c20b/Screener.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<ul>
<li><strong>Quant</strong>: Added a quant workspace for authoring indicator and strategy scripts, chart syncing and strategy backtests; once a backtest finishes, the performance report, net value curve and buy/sell markers are all available.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Quant：Added a quant workspace for authoring indicator and st"><source src="https://assets.lbkrs.com/uploads/a78a6d7c-a64e-4763-aa70-f74f631cec2a/Quant.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<p><strong>Trading</strong></p>
<ul>
<li><strong>Grid Trading</strong>: Added grid trading — for stocks that move within a fluctuating range, set up a buy-low/sell-high strategy and let it run inside the price range you specify, and it can be paused, restarted, adjusted or terminated at any time.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Grid Trading：Added grid trading — for stocks that move withi"><source src="https://assets.lbkrs.com/uploads/3b21b781-677f-42d5-8f22-ee70e3c39973/Grid.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<ul>
<li><strong>Trade</strong>: The take-profit/stop-loss ticket has been redesigned for a more intuitive way to set stop levels, and now supports dynamic “Full position” and “Trigger price” parameters that follow position changes automatically, for greater flexibility.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Trade：The take-profit/stop-loss ticket has been redesigned f"><source src="https://assets.lbkrs.com/uploads/65032bfc-4738-426d-87e3-c0be30588879/TP-SL.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<p><strong>Monitoring &amp; research</strong></p>
<ul>
<li><strong>Quotes</strong>: Added quote change alerts to stock details, pushing that stock’s alerts such as limit-up and block trades in real time.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Quotes：Added quote change alerts to stock details, pushing t"><source src="https://assets.lbkrs.com/uploads/4d435b8b-ac15-49c5-8239-210e36227346/Big.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<ul>
<li><strong>Watchlist</strong>: The list view now supports drag-and-drop sorting, with pinned stocks reordered within the pinned segment, so there is no need to open group management to change the order.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame relative group" data-video-state="loading" style="--video-ratio:16 / 9"><video class="block w-full" data-release-video data-autoplay muted playsinline preload="metadata" loop aria-label="Watchlist：The list view now supports drag-and-drop sorting, "><source src="https://assets.lbkrs.com/uploads/6d576317-2705-4bf4-8f56-1570b0f500be/Drag.mp4" type="video/mp4"></video><span class="video-loading" aria-hidden="true"></span><button type="button" data-video-toggle class="absolute inset-0 grid cursor-pointer place-items-center" aria-label="Play"><span class="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white opacity-0 backdrop-blur-sm transition-opacity [[data-video-toggle]:focus-visible_&amp;]:opacity-100" data-video-icon><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path data-icon-pause d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"></path><path data-icon-play class="hidden" d="M8 5.2v13.6L19 12z"></path></svg></span></button><input type="range" class="video-progress" data-video-progress min="0" max="1000" value="0" step="1" aria-label="Seek"></div></figure>
<ul>
<li><strong>Chart</strong>: Drawings can now be locked per shape or globally, preventing accidental dragging of finished lines while reading charts, with the lock state kept in sync with mobile.</li>
<li><strong>Layout</strong>: Added an adaptive layout to custom pages — widgets dragged in are arranged automatically and fit the screen size, for a more flexible layout.</li>
<li><strong>Financials</strong>: Added a “Financial Score” panel covering the latest rating, a five-dimension radar chart, score criteria details and the industry rating distribution, making it easy to see where a stock stands among its peers.</li>
</ul>
<figure class="my-7" data-reveal><div class="media-frame"><img src="https://assets.lbkrs.com/uploads/945a3959-f08c-4510-83aa-252ac8bf3ac0/Score.png" alt="score" width="3584" height="2324" loading="lazy" decoding="async" data-zoomable class="block w-full"></div></figure>
<h2 id="improvements">Improvements</h2>
<ul>
<li>Placing a US market order outside regular trading hours now shows a reminder with a one-click switch to a limit order, avoiding accidental market fills in pre-/post-market sessions.</li>
<li>Reconnecting and disconnected states now show a status indicator with manual retry, so a stalled quote feed is no longer left to guesswork.</li>
</ul></div></section></main>
"""#

/// Preview's manifest `preview/latest.json` as served 2026-10-14, trimmed to the
/// keys the decoder reads. Only the newest preview build is in it.
private let longbridgePreviewManifestNotes = #"""
{"version":"1.0.0-preview.3","published_at":"2026-10-09T07:20:12Z","release_notes":{"en":"### New Features\r\n\r\n- **LongbridgeAI**: Redesigned the reasoning process, making the AI's progress easy to follow and keeping answers focused.\r\n- **Stock Details**: Added a hot topic card to the pinned board, showing trending discussions about the stock and linking straight to the topic page.\r\n- **Trade**: Added Touch ID unlock for trading on macOS — verify your trade password with just a fingerprint.\r\n- **Account**: Added account switching, so you can switch to any previously signed-in account from the avatar menu without logging out and back in.\r\n- **Chart**: Added \"Signals & Catalysts\" to the K-line chart, marking trading signals and catalyst events on the chart; open one to see the details or ask AI to analyze it, helping you quickly understand what drives a move.\r\n- **Custom Layout**: Added undo, so accidentally removed widgets or a messed-up layout can be restored at any time; tabs can be exported to a file and imported on another device, making layouts easy to share and migrate.\r\n- **Announcements**: New announcements are also sent to the system notification center while the app is in the background, so important notices are not missed.\r\n\r\n### Improvements\r\n\r\n- Added display settings to the heatmap for customizing titles, values, colors and grouping; also improved the layout so small blocks are no longer squeezed into thin strips.\r\n- The Today's Orders popover in chart trading now shows the strategy name and leg details of multi-leg option orders.\r\n- Fixed an issue where a full leap-year range was rejected as longer than one year when exporting historical orders.\r\n- Dragging a widget into an empty custom layout now shows the drop area, and the widget toolbox hides automatically while you adjust panels so it no longer covers the canvas."}}
"""#

/// The ordering the live pages do NOT currently use: illustration first, change
/// line after it. Longbridge puts media at the end of every bullet today, so this
/// is the shape a vendor restyle would introduce — and the one an item pattern
/// that treats `<img>` as a hard stop silently eats.
private let longbridgeMediaFirstNotes = #"""
<main><section id="v0.20.0" class="release-section" data-release-section data-rail-version="0.20.0" data-rail-date="2026-09-01" data-rail-title="Charts and watchlist · September 1, 2026"><h2 class="text-[1.25rem] font-semibold tracking-tight">Charts and watchlist</h2><p class="mt-3 text-[0.9375rem] leading-relaxed text-ink-soft">Charts gained a new drawing tool.</p><div class="prose mt-5"><h2 id="improvements">Improvements</h2>
<ul>
<li><img width="1200" alt="chart" src="https://assets.lbkrs.com/uploads/Chart.png">Charts gained a new drawing tool.</li>
<li>Watchlist sorting is now stable.</li>
</ul></div></section></main>
"""#

/// The releases INDEX page: a heading and no `release-section`. The no-version
/// fallback depends on this parsing to nothing.
private let longbridgeIndexPage = #"""
<main class="mx-auto w-full max-w-5xl flex-1 px-5 py-10"><h1 class="text-[1.75rem] font-semibold">Longbridge Pro</h1><div class="grid"></div></main>
"""#

@Suite struct LongbridgeIntegrationTests {

    /// Everything Longbridge in the vendor registry, keyed by channel. Derived
    /// from the registry so a channel added later is covered — or fails loudly
    /// for want of a fixture — instead of quietly escaping these assertions.
    private static let probes: [ReleaseChannel: VendorProbeRecipe] = Dictionary(
        uniqueKeysWithValues: VendorProbeRegistry.recipes
            .filter { $0.bundleID.hasPrefix("com.longbridge.app.desktop") }
            .map { ($0.channel, $0) })

    private static let changelogs: [ReleaseChannel: ChangelogRecipe] = Dictionary(
        uniqueKeysWithValues: ChangelogRecipeRegistry.recipes
            .filter { $0.bundleID.hasPrefix("com.longbridge.app.desktop") }
            .compactMap { recipe in recipe.channel.map { ($0, recipe) } })

    /// channel → (bundle id, manifest body, the version that body declares).
    private static let manifests: [ReleaseChannel: (String, String, String)] = [
        .stable: ("com.longbridge.app.desktop", longbridgeStableManifest, "0.19.1"),
        .preview: ("com.longbridge.app.desktop.preview", longbridgePreviewManifest,
                   "0.19.0-preview.1"),
    ]

    private static let notes: [ReleaseChannel: (String, String)] = [
        .stable: (longbridgeStableMinorPage, "0.19.1"),
        .preview: (longbridgePreviewManifestNotes, "1.0.0-preview.3"),
    ]

    // MARK: - Registry coverage

    @Test func everyRegisteredChannelHasAFixture() {
        #expect(!Self.probes.isEmpty)
        for channel in Self.probes.keys {
            #expect(Self.manifests[channel] != nil,
                    "vendor probe for channel \(channel.rawValue) has no manifest fixture")
        }
        for channel in Self.changelogs.keys {
            #expect(Self.notes[channel] != nil,
                    "changelog recipe for channel \(channel.rawValue) has no notes fixture")
        }
        // Both registries must agree on which channels exist, or one of them is
        // serving a channel the other silently drops.
        #expect(Set(Self.probes.keys) == Set(Self.changelogs.keys))
    }

    // MARK: - Vendor probe

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func probeReadsItsOwnChannelsMarketingVersion(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.probes[channel])
        let (bundleID, body, expected) = try #require(Self.manifests[channel])

        #expect(recipe.bundleID == bundleID)
        #expect(recipe.versionIsBuild == false)
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == expected)
    }

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func installerSelectsTheAppleSiliconDMGOfItsOwnChannel(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.probes[channel])
        let (_, body, version) = try #require(Self.manifests[channel])
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("Longbridge installer must resolve from the manifest body")
            return
        }
        let url = try #require(VendorProbeRecipe.extractVersion(from: body, pattern: pattern))
        #expect(url.hasSuffix("longbridge-v\(version)-macos-aarch64.dmg"))
        // The vendor lists linux first and x86_64 right after aarch64, so a
        // first-match-any-dmg pattern would pick the wrong file on both axes.
        #expect(!url.contains("x86_64"))
        #expect(!url.contains("linux"))
        #expect(spec.kind == .dmg)
    }

    // MARK: - Download digest

    private static func checksumPattern(_ channel: ReleaseChannel) throws -> String {
        let spec = try #require(probes[channel]?.install)
        #expect(spec.checksumFormat == .sha256Hex)
        return try #require(spec.checksumPattern)
    }

    /// The digest is the aarch64 dmg's — the asset the URL reads — not the linux
    /// asset listed first or the x86_64 dmg right after it.
    @Test func eachChannelChecksTheAppleSiliconDMGsOwnSHA256() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: try Self.checksumPattern(.stable))
            == "a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithDigests, pattern: try Self.checksumPattern(.preview))
            == "4c9aa9992675af7787756c83dda048beb0adb2bb0abefcaec53944572331bd02")
        // The preview URL pattern reads the same asset on that body.
        guard case .bodyPattern(let url) = try #require(Self.probes[.preview]?.install).urlSource
        else { return }
        #expect(VendorProbeRecipe.extractVersion(from: longbridgePreviewManifestWithDigests, pattern: url)
            == "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-aarch64.dmg")
    }

    /// `sha256` ahead of `name` and `url` inside the asset still pairs with it.
    @Test func theDigestDoesNotDependOnKeyOrder() throws {
        let entry = #"{"name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa"}"#
        let reordered = #"{"sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa","name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg"}"#
        #expect(longbridgeStableManifest.contains(entry))
        let body = longbridgeStableManifest.replacingOccurrences(of: entry, with: reordered)
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.checksumPattern(.stable))
            == "a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa")
    }

    /// An aarch64 asset without `sha256` reads nothing, not the x86_64 dmg's
    /// digest after it: on preview's 0.19.0-preview.1 manifest (no digests at
    /// all), and on stable's with only the aarch64 digest removed.
    @Test func aDigestlessAssetReadsNothingRatherThanTheNextAssetsDigest() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: try Self.checksumPattern(.preview)) == nil)
        let body = longbridgeStableManifest.replacingOccurrences(
            of: #","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa""#, with: "")
        #expect(body != longbridgeStableManifest)
        #expect(body.contains("5d3325bd671735b4720e2ac7d232cedf9b4a8abf3953ff2247e17e54d9d134b5"))
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.checksumPattern(.stable)) == nil)
    }

    /// Neither channel's digest pattern reads the other train's manifest.
    @Test func theTwoChannelsDigestPatternsCannotReadEachOthersManifest() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithDigests, pattern: try Self.checksumPattern(.stable)) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: try Self.checksumPattern(.preview)) == nil)
    }

    /// The failure a copied-from-stable recipe makes: patterns that still match,
    /// against the other train's document. Both directions, both fields.
    @Test func theTwoChannelsPatternsCannotMatchEachOthersManifest() throws {
        let stable = try #require(Self.probes[.stable])
        let preview = try #require(Self.probes[.preview])

        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: stable.versionPattern) == nil,
            "the stable version pattern must not read a preview manifest")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: preview.versionPattern) == nil,
            "the preview version pattern must not read a stable manifest")

        for (own, other, label) in [
            (stable, longbridgePreviewManifest, "stable installer vs preview manifest"),
            (preview, longbridgeStableManifest, "preview installer vs stable manifest"),
        ] {
            guard case .bodyPattern(let pattern) = try #require(own.install).urlSource else {
                Issue.record("expected a bodyPattern installer")
                return
            }
            #expect(VendorProbeRecipe.extractVersion(
                from: other, pattern: pattern) == nil, "\(label) must not resolve")
        }
    }

    @Test func thePreviewChannelRegistersAnArtifactProof() throws {
        let key = ChannelProofKey("com.longbridge.app.desktop.preview", .preview)
        let proof = try #require(ChannelProofRegistry.proofs[key])
        guard case .artifact(let pattern) = proof else {
            Issue.record("expected a URL-anchored artifact proof")
            return
        }
        let preview = try #require(Self.probes[.preview])
        guard case .bodyPattern(let installPattern) =
                try #require(preview.install).urlSource else { return }
        let url = try #require(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: installPattern))
        #expect(url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
                "the resolved preview installer must satisfy its own channel proof")
    }

    /// `com.longbridge.app.desktop.preview` must resolve to `.preview`, or the
    /// source refuses the recipe and Preview installs silently go unchecked.
    @Test func thePreviewBundleIDDetectsAsThePreviewChannel() {
        #expect(ReleaseChannel.detect(
            name: "Longbridge Preview",
            bundleID: "com.longbridge.app.desktop.preview",
            keystoneChannel: nil, version: "0.19.0-preview.1") == .preview)
        #expect(ReleaseChannel.detect(
            name: "Longbridge", bundleID: "com.longbridge.app.desktop",
            keystoneChannel: nil, version: "0.19.1") == .stable)
    }

    /// The `-preview.N` suffix has to order correctly, or Preview users get a
    /// permanent phantom update (or never get a real one).
    @Test func previewVersionsCompareWithoutPhantomUpdates() {
        #expect(!VersionComparator.isNewer("0.19.0-preview.1", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.19.0-preview.2", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.19.1-preview.0", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.20.0-preview.0", than: "0.19.0-preview.9"))
        // A finished release outranks its own pre-releases.
        #expect(VersionComparator.isNewer("0.19.0", than: "0.19.0-preview.1"))
    }

    // MARK: - Changelog

    /// Stable reads the minor page the version belongs to. That page holds every
    /// patch release of its line, newest first, so the first section is the one
    /// the entry pattern takes, and the older 0.19.0 section below it is not read.
    @Test func stableReadsTheNewestSectionOfItsMinorPage() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let (page, expected) = try #require(Self.notes[.stable])

        #expect(recipe.structuredFormat == nil)
        #expect(recipe.mode == .html)
        #expect(recipe.resolvedSource(forVersion: expected).absoluteString
            == "https://longbridge.com/en/changelog/longbridge-pro/v0.19")
        #expect(recipe.resolvedSource(forVersion: "1.0.0").absoluteString
            == "https://longbridge.com/en/changelog/longbridge-pro/v1.0")

        let log = try #require(ChangelogExtractor.extract(from: page, using: recipe))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == expected)
        #expect(entry.date == "2026-08-20")
        // Two change lines, read from the prose list. The `<p>` summary above the
        // prose repeats the first line and must not come through as a third.
        #expect(entry.items.count == 2)
        #expect(entry.items.first?.hasPrefix("Fixed an issue where the editor could quit unexpectedly") == true)
        #expect(entry.items.allSatisfy { !$0.contains("Screener") })
    }

    /// The stable entry reads its section's own date, and an installer link cannot
    /// become a change line: the section ends at its own `</section>`.
    @Test func stableEntryTakesItsOwnSectionDate() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let page = try #require(Self.notes[.stable]).0
        let entry = try #require(ChangelogExtractor.extract(from: page, using: recipe)?.entries.first)
        #expect(entry.date == "2026-08-20")
        #expect(entry.items.allSatisfy { !$0.contains("macOS installer") })
    }

    /// The 0.19.0 section carries the shapes the vendor page really uses: a
    /// `<strong>` label, an illustration mid-list, and video clips whose fallback
    /// text must not survive as a change line.
    @Test func richSectionKeepsImagesInDocumentOrderAndDropsVideoFallbackText() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeStableRichSection, using: recipe)?.entries.first)
        #expect(entry.version == "0.19.0")
        #expect(entry.date == "2026-08-19")
        #expect(entry.items.allSatisfy { !$0.contains("does not support") })
        #expect(entry.items.allSatisfy { !$0.isEmpty })
        #expect(entry.items.contains { $0.hasPrefix("Screening") })
        #expect(entry.content.contains { block in
            if case .image = block { return true }
            return false
        })
    }

    /// A change line must survive its own illustration appearing BEFORE it.
    ///
    /// `<img>` is a void tag carrying no text, `stripTags` removes it anyway, and
    /// `imagePattern` collects images from the whole body independently of item
    /// boundaries — so treating `<img` as an item terminator never added anything
    /// and could only truncate. When the image came first the captured item was
    /// empty, `minItemLength` discarded it, and scanning resumed at the `<img>`,
    /// past the point where the bullet's text lived: the whole line vanished
    /// rather than merely losing its tail.
    @Test func aChangeLineSurvivesAnIllustrationPlacedBeforeIt() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeMediaFirstNotes, using: recipe)?.entries.first)
        #expect(entry.items == [
            "Charts gained a new drawing tool.",
            "Watchlist sorting is now stable.",
        ])
        // The image is still collected. It renders AFTER its own line rather than
        // before it, even though the markup puts it first: `ChangelogExtractor`
        // interleaves on each match's START offset, and an item's match starts at
        // its `<li>` tag, which precedes the `<img>` nested inside it. So a bullet's
        // note always sorts ahead of an image belonging to that same bullet. That
        // is a property of the extractor, not of this recipe, and it reads fine —
        // pinned here so the ordering is a decision on record rather than a
        // surprise the next person re-derives.
        #expect(entry.content == [
            .note("Charts gained a new drawing tool."),
            .image(try #require(URL(string: "https://assets.lbkrs.com/uploads/Chart.png"))),
            .note("Watchlist sorting is now stable."),
        ])
    }

    /// The no-version fallback. Stable's `source` is the releases index, which must
    /// yield NOTHING, so the UI embeds the vendor page instead of presenting one
    /// pinned release's notes as if they described the installed build.
    @Test func theUntemplatedStableSourceIsAnIndexThatParsesNothing() throws {
        let recipe = try #require(Self.changelogs[.stable])
        #expect(recipe.sourceTemplate != nil)
        let fallback = recipe.resolvedSource(forVersion: nil)
        #expect(fallback == recipe.source)
        #expect(fallback.absoluteString.range(of: #"/v[0-9]"#, options: .regularExpression) == nil)
        #expect(ChangelogExtractor.extract(from: longbridgeIndexPage, using: recipe) == nil)
    }

    /// Preview has no per-version page any more. Its notes come from the manifest's
    /// `release_notes.en`, read as a JSON string: the escapes resolve, the `**`
    /// around each bullet's label is dropped, and the `###` headings are not items.
    @Test func previewReadsTheManifestsNotesAsPlainChangeLines() throws {
        let recipe = try #require(Self.changelogs[.preview])
        let (manifest, expected) = try #require(Self.notes[.preview])

        #expect(recipe.structuredFormat == .longbridgeDesktopManifest)
        #expect(recipe.sourceTemplate == nil)
        #expect(recipe.mode == .json)

        let log = try #require(ChangelogService.parse(recipe, body: manifest))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == expected)
        #expect(entry.date == "2026-10-09")
        #expect(entry.items.count == 11)
        #expect(entry.items.first == "LongbridgeAI: Redesigned the reasoning process, making the AI's progress easy to follow and keeping answers focused.")
        #expect(entry.items.contains("Chart: Added \"Signals & Catalysts\" to the K-line chart, marking trading signals and catalyst events on the chart; open one to see the details or ask AI to analyze it, helping you quickly understand what drives a move."))
        #expect(entry.items.allSatisfy { !$0.contains("**") && !$0.contains("\\") })
        #expect(entry.items.allSatisfy { !$0.hasPrefix("#") && !$0.hasPrefix("- ") })
    }

    /// Each channel's recipe reads only its own document, and the two routes are
    /// keyed by bundle id: the stable HTML pattern finds nothing in the preview
    /// manifest, and the preview decoder finds nothing in a stable page.
    @Test func eachChannelsChangelogRecipeRejectsTheOtherChannelsDocument() throws {
        let stable = try #require(Self.changelogs[.stable])
        let preview = try #require(Self.changelogs[.preview])
        let (stablePage, _) = try #require(Self.notes[.stable])
        let (previewManifest, _) = try #require(Self.notes[.preview])

        #expect(ChangelogExtractor.extract(from: previewManifest, using: stable) == nil,
                "the stable entry pattern must not read the preview manifest")
        #expect(ChangelogService.parse(preview, body: stablePage) == nil,
                "the preview decoder must not read a stable page")

        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop.preview", channel: .preview)?
            .bundleID == "com.longbridge.app.desktop.preview")
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop", channel: .stable)?
            .bundleID == "com.longbridge.app.desktop")
    }

    @Test func changelogCatalogProvidesAWebFallbackForStable() {
        #expect(ChangelogCatalog.url(forBundleID: "com.longbridge.app.desktop")?
            .absoluteString == "https://longbridge.com/desktop/release-notes/")
    }
}
