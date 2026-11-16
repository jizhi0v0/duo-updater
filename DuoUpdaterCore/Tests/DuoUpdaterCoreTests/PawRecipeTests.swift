import Foundation
import Testing
@testable import DuoUpdaterCore

// Three complete version articles from paw.cloud/updates (2026-11-16): list,
// paragraph and historical Paw formats. Surrounding page chrome is synthetic.
private let pawUpdatesFixture = #"""
<nav><a href="/updates/99.9">macOS 27</a><li>Download</li></nav>
<article class="article-version">
            
                


<h3 class="version-title">
    <a href="/updates/4.5.5">
    <span lang="en">
        RapidAPI for Mac 4.5.5
        
    </span>
    
    <span class="version-os-version">macOS 13.0+</span>
    
    
    <span class="version-latest">Latest</span>
    
    <span class="version-date">April 20, 2026</span>
    </a>
</h3>

<div class="update-description" lang="en">
    <h4 class="update-type">
    <img src="https://cdn-static.paw.cloud/img/update-icons/Fixes-4b68d809fb.svg" class="update-type-tag noselect" />
    Fixes
</h4>

<ul>
<li>Bug fixes and performance improvements</li>
</ul>
</div>


            
        </article>
<article class="article-version">
            
                


<h3 class="version-title">
    <a href="/updates/4.5.0">
    <span lang="en">
        RapidAPI for Mac 4.5.0
        
    </span>
    
    <span class="version-os-version">macOS 11.0+</span>
    
    
    <span class="version-date">Nov. 13, 2025</span>
    </a>
</h3>

<div class="update-description" lang="en">
    <h4 class="update-type">
    <img src="https://cdn-static.paw.cloud/img/update-icons/New-b92e03d345.svg" class="update-type-tag noselect" />
    New
</h4>

<p>🐾 Add option to add additional headers during OAuth2 flow</p>
<h4 class="update-type">
    <img src="https://cdn-static.paw.cloud/img/update-icons/Fixes-4b68d809fb.svg" class="update-type-tag noselect" />
    Fixes
</h4>

<p>🐾 Yet another workaround for Window-Fill issue, where app will be resized unexpectedly</p>
</div>


            
        </article>
<article class="article-version">
            
                


<h3 class="version-title">
    <a href="/updates/3.1.8">
    <span lang="en">
        Paw 3.1.8
        
    </span>
    
    <span class="version-os-version">macOS 10.12.2+</span>
    
    
    <span class="version-date">Nov. 14, 2018</span>
    </a>
</h3>

<div class="update-description" lang="en">
    <p><img src="https://cdn-content.paw.cloud/versions/releases/paw-3.1.8-release/paw-3.1.8-release-notes-squashed.jpg" alt="Paw 3.1.8 for macOS Mojave" style="max-width: 100%;" /></p>
<h4 class="update-type">
    <img src="https://cdn-static.paw.cloud/img/update-icons/New-b92e03d345.svg" class="update-type-tag noselect" />
    Improvements
</h4>

<ul>
<li>Better syntax highlighting colors &amp; support for accent colors on macOS Mojave</li>
<li>Adds support for <em>URLSession</em>, macOS' native HTTP networking library</li>
<li>Adds an <a href="https://obdev.at/iap/index.html">Internet Access Policy</a> for better compatibility with <a href="https://obdev.at/products/littlesnitch/index.html">Little Snitch</a></li>
</ul>
<h4 class="update-type">
    <img src="https://cdn-static.paw.cloud/img/update-icons/Fixes-4b68d809fb.svg" class="update-type-tag noselect" />
    Fixes
</h4>

<ul>
<li>Fixes a UI glitch when using tabs on macOS Mojave</li>
<li>Fixes issues with HTTP 204 No Content on <em>Paw HTTP Library</em></li>
<li>Adds an easy way to delete all cookies from the current session</li>
<li>Improves text completion when using the tab key</li>
<li>Strips whitespaces &amp; newlines on headers</li>
<li>Fixes more interface glitches</li>
</ul>
</div>


            
        </article>
<footer><h4 class="update-type">Support</h4><p>Contact us</p></footer>
"""#

@Suite struct PawRecipeTests {
    @Test func extractsBothNamesAndBothChangeFormatsWithoutPageChrome() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.luckymarmot.Paw", channel: .stable, version: "4.5.5"))
        let log = try #require(ChangelogService.parse(recipe, body: pawUpdatesFixture))
        #expect(log.entries.map(\.version) == ["4.5.5", "4.5.0", "3.1.8"])
        #expect(log.entries.map(\.date) == ["April 20, 2026", "Nov. 13, 2025", "Nov. 14, 2018"])
        #expect(log.entries[0].items == ["Bug fixes and performance improvements"])
        #expect(log.entries[1].items == [
            "🐾 Add option to add additional headers during OAuth2 flow",
            "🐾 Yet another workaround for Window-Fill issue, where app will be resized unexpectedly",
        ])
        #expect(log.entries[2].items.count == 9)
        #expect(log.entries[2].items.first == "Better syntax highlighting colors & support for accent colors on macOS Mojave")
        #expect(headings(log.entries[0]) == ["Fixes"])
        #expect(headings(log.entries[1]) == ["New", "Fixes"])
        #expect(headings(log.entries[2]) == ["Improvements", "Fixes"])
        #expect(!log.entries.flatMap(\.items).contains { $0.contains("Contact us") || $0 == "Download" })
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap {
            if case .heading(let text) = $0 { text } else { nil }
        }
    }
}
