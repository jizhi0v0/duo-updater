import Foundation

enum ai_perplexity_comet {
    static let set = AppRecipeSet(
        family: "ai-perplexity-comet",
        probes: [
        // History: docs/app-audits/ai-perplexity-comet.md#历史与实测
        // Comet — the cask's JSON update API is rollout-stale (it lags the public
        // download; versions are Chromium-major-prefixed, e.g. 145.x), so probing it
        // would report a downgrade. The official stable download GET redirects to a
        // signed R2 URL
        // whose versioned directory exactly matches the mounted bundle's marketing
        // version. HEAD is a vendor trap (redirects to example.com), hence GET with
        // redirects disabled. ai.perplexity.comet, Team 7S8W4W365S, notarized;
        // Keystone updater, no Sparkle feed.
        //
        // ONE-CLICK via `.fixed` ON THE GATEWAY ITSELF — deliberately not on the
        // signed URL the probe just resolved, and deliberately not `.redirect`.
        //
        // `.redirect` is out because it HEADs, and this vendor's HEAD answers
        // `Location: https://www.example.com?status=ok`.
        //
        // Templating the resolved signed URL would "work" and then rot: every
        // install URL is resolved at CHECK time and stored on the row until the
        // user clicks, while this signature carries `X-Amz-Expires=3600`. A row
        // checked more than an hour before the click — the default on any
        // frequency slower than hourly — would 403. Handing the download the
        // gateway instead moves the redirect to download time, where `Downloader`
        // GETs and follows it like a browser, so the signature is always minutes
        // old. That is also why the ephemeral URL never has to be re-resolved:
        // nothing durable ever holds one.
        //
        // ONE CONSTANT for both halves, not two copies of the same string. The
        // probe and the download MUST be the same endpoint — that is the entire
        // design — and two literals drift silently in the one direction every gate
        // would wave through: retarget the probe to `channel=beta` and the install
        // still fetches stable, both Perplexity-signed builds of the same bundle
        // id, so the user is offered a beta and handed a stable.
        //
        // No checksum, because the gateway publishes none — so unlike Msty there
        // is nothing here that notices when the build fetched is not the build
        // compared. The gateway always serves current: a row checked at, e.g.,
        // 151.0.7922.247 and clicked after 152.x ships installs 152.x and records
        // 151.0.7922.247 until the next check corrects it. That is bookkeeping
        // drift, not a broken app, and it is the same property every `.redirect`
        // recipe already has; it is written down because the version and the
        // artifact come from one document at PROBE time and from two moments at
        // install time.
        //
        // The dmg the gateway serves holds the real `Comet.app`, not a downloader
        // stub like 1Password's (History has the verification).
        VendorProbeRecipe(
            bundleID: "ai.perplexity.comet",
            url: Self.cometStableGateway,
            mode: .redirectFilename,
            versionPattern: #"/([0-9]+(?:\.[0-9]+)+)/comet_latest\.dmg"#,
            downloadURL: URL(string: "https://www.perplexity.ai/comet"),
            install: VendorInstallSpec(urlSource: .fixed(Self.cometStableGateway), kind: .dmg),
            followRedirects: false),
        ])

    /// Comet's stable download gateway — the endpoint the probe reads AND the one
    /// the installer fetches. Declared once because those two must never diverge:
    /// see the recipe's comment.
    static let cometStableGateway = URL(
        string: "https://www.perplexity.ai/rest/browser/download"
            + "?channel=stable&platform=mac_arm64")!
}
