import Foundation

enum com_anthropic_claudefordesktop {
    static let set = AppRecipeSet(
        family: "com-anthropic-claudefordesktop",
        probes: [
        // History: docs/app-audits/com-anthropic-claudefordesktop.md#历史与实测
        // Claude desktop — TWO endpoints, both listed, highest wins (see
        // `VendorProbeSource.best`). Anthropic runs a staged rollout, so "latest"
        // genuinely has two answers and which leads flips during a ramp:
        //
        //   1. the public GA redirect below — what claude.ai/download serves;
        //   2. the Squirrel rollout endpoint below — what THIS machine's own
        //      updater acts on, keyed by its device id.
        //
        // Neither alone is right. GA alone goes blind for the whole ramp, reporting
        // "up to date" while the app's own updater has already staged a newer build
        // (History has the incident). The rollout endpoint alone would go blind the
        // other way if a bucket is held back.
        //
        // The old reason for skipping the rollout endpoint — a synthetic device id
        // lands in an unrelated bucket, hiding real updates when behind and
        // inventing them when ahead — is answered by reading the id Claude itself
        // wrote (`ProbeIdentity`), not by inventing one.

        // (1) Public GA download redirect: no id, the current GA build, exactly
        // what the website's download button gives.
        // The version is in the 307 `Location` path (…/universal/<version>/…);
        // GET only (HEAD 405s) and don't follow (that downloads the archive). Use
        // api.anthropic.com, NOT claude.ai — the latter sits behind a Cloudflare
        // JS challenge that a non-browser client can't pass.
        //
        // One-click install is safe here: `/latest` is the public GA build (same
        // as a manual claude.ai/download), not a held-back rollout, so installing
        // it never jumps this machine ahead of a cohort. We take the `zip` (the
        // format Claude's own Squirrel updater uses) over the heavier dmg. The
        // `Location` URL is reused as the install body, so the same response yields
        // both the version and the download. Team Q6L2SF6YDW gates the swap.
        VendorProbeRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            url: URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/zip/latest/redirect")!,
            mode: .redirectFilename,
            versionPattern: #"/darwin/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
            downloadURL: URL(string: "https://claude.ai/download"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            followRedirects: false,
            variant: "ga"),

        // (2) Claude desktop — the staged-rollout endpoint its own Squirrel
        // updater calls. `device_id` is REQUIRED (no id → HTTP 400) and selects
        // the rollout bucket (synthetic ids land in different buckets), which is
        // exactly why the id must be this machine's real one
        // (`~/Library/Application Support/Claude/ant-did`, a base64-wrapped UUID)
        // and never a fabricated one. With the real id the answer is, by
        // construction, what Claude's own updater will do.
        //
        // The response is small JSON, e.g.:
        //   {"currentRelease":"1.30096.5","releases":[{"version":…,"updateTo":{
        //     "name":…,"version":…,"pub_date":"2026-08-14T22:50:24.042387",
        //     "url":"https://downloads.claude.ai/releases/…zip","notes":…}}]}
        // `currentRelease` is the authoritative "what this device should be on" —
        // it's returned whether or not the device is behind, so the install URL
        // always resolves and there's no spurious `installURLUnresolved` once
        // we're current.
        //
        // The id rides in the query at fetch time only; `url` here keeps the
        // placeholder, and that is the copy logs and verify findings carry.
        // One-click is safe for the same reason as (1) and then some: this is
        // precisely the build allocated to this machine. Team Q6L2SF6YDW gates
        // the swap. `pub_date` is UTC, and it's what finally gets Claude into the
        // Release Log timeline.
        VendorProbeRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            url: URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/squirrel/update?device_id=__IDENTITY__")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://claude.ai/download"),
            publishedAtPattern: #""pub_date"\s*:\s*"([0-9T:.\-]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            identities: [ProbeIdentity(
                applicationSupportPath: "Claude/ant-did",
                encoding: .base64,
                validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#)],
            variant: "rollout"),
        ],
        changelogs: [
        // Claude Desktop — the official docs changelog at
        // claude.com/docs/cowork/changelog. We fetch the `.md` twin (Mintlify serves a
        // text/markdown form of every docs page): server-rendered, on a stable URL, and
        // free of the hashed-JS + zstd-cache fragility of the in-app "What's new" popup
        // (which reads an inline array baked into claude.ai's web bundle — variable
        // names rotate every deploy). Each release is one block, e.g.:
        //   <Update label="v1.22209.0" description="2026-07-16"> … </Update>
        // version = the label minus its leading "v" (matches the
        // com.anthropic.claudefordesktop build the VendorProbe reads); date = the
        // description verbatim. Inside, notes are grouped into `**General**`, `**Code**`,
        // `**Cowork**`, and `**3P**` sections of `* ` markdown bullets.
        //
        // Decoded, not regex-extracted: the regex recipe that used to live here
        // flattened General + Code + Cowork into one unheaded list, which is not what
        // the in-app popup shows — it shows the Code tab's General + Code notes grouped
        // as New / Improved / Fixed. `decodeClaudeDesktop` reproduces that, and says
        // where the reproduction is inferred. A parse miss falls back to embedding the
        // page.
        ChangelogRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            source: URL(string: "https://claude.com/docs/cowork/changelog.md")!,
            maxEntries: 20,
            structuredFormat: .claudeDesktopChangelog),
        ])
}
