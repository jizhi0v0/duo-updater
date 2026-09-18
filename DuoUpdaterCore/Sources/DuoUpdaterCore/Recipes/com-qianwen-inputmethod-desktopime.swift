import Foundation

enum com_qianwen_inputmethod_desktopime {
    static let set = AppRecipeSet(
        family: "com-qianwen-inputmethod-desktopime",
        probes: [
        // History: docs/app-audits/com-qianwen-inputmethod-desktopime.md#历史与实测
        // 千问输入法 (QianwenIME) — Alibaba's input method, installed from
        // `ime.qianwen.com` into `/Library/Input Methods` (scanned by AppScanner
        // like the other three IMEs). Nothing in the priority chain answered: no
        // `SUFeedURL` and no electron-builder config (`feed-discover` reports
        // `no Sparkle and no electron-builder update config`), no MAS receipt, and
        // no cask — the `qianwen` cask ships `Qianwen.app`, the unrelated Qwen chat
        // client, the same trap the `doubao` cask sets for DoubaoIme.
        //
        // ITS OWN UPDATE CHECK IS UNREADABLE, which is why we read the site's
        // instead. `QianwenIMEService` POSTs a Quark PUDS protobuf to
        // `puds.qianwen.com/upgrade/index.xhtml?from=pb_query`, with the request
        // body encrypted by WSG and the reply decrypted the same way — its own log
        // strings spell it out (`failed to encrypt Quark PUDS request with WSG`,
        // `official update PUDS encrypted payload`). There is no plaintext shape to
        // regex, and forging one would mean reimplementing Alibaba's security
        // guard. That endpoint is also the per-device allocation channel; what we
        // read below deliberately is not (see the bottom of this comment).
        //
        // So the probe reads the endpoint the official download button reads. The
        // site's own JS builds it (`/pcdownload/qwenimemac`, from the "buwang" SDK
        // chunk behind `ime.qianwen.com/download/mac`) and it answers, e.g.:
        //
        //   {"success":true,"code":"OK","data":{
        //     "fp":"dapi-<uuid>",
        //     "url":"https://umcdn.qianwen.com/download/37317/qwenimemac/
        //            pcqwenime@homepage_official/
        //            QwenimeMac_V1.2.26.41_mac_pf8002_(zh-cn)_release_(Build3192975).dmg"},
        //    "msg":"","timestamp":…,"traceId":…}
        //
        // `ch` IS LOAD-BEARING — it selects which build is named, and dropping it
        // is not "the default, which is fine": the server falls back to
        // `pcqwenime@default`, which names a build from the previous version
        // scheme. The pinned value is not borrowed from one machine; it is the
        // vendor's own homepage channel, and it is what every bundle downloaded
        // from that page carries in its Info.plist as `QianwenChannelId` /
        // `QianwenPackageChannelId`.
        //
        // The fallback is SILENT, which is the fragility to know about here: an
        // unrecognised `ch` is not an error, it is `@default` — `pcqwenime@beta`
        // and `pcqwenime@inner` answer exactly like the bare request, so neither
        // is a real track. If the vendor ever retires `@homepage_official`, this
        // probe keeps returning 200 and names that same old build. The failure is
        // loud rather than quiet: a version below every real install is what
        // `duo verify` reports as `remote is BEHIND the installed copy`. History
        // has the per-`ch` answers.
        //
        // `fp` is a per-request download fingerprint the endpoint mints fresh on
        // every call (three calls, three different uuids). It is not read here and
        // must never be pinned into a recipe or a fixture.
        //
        // VERSION SCHEME. The filename's `V1.2.26.41` is exactly the installed
        // bundle's `CFBundleVersion`; its `CFBundleShortVersionString` is the
        // three-part `1.2.26`. So `versionIsBuild` compares build to build —
        // respins that move only the fourth segment stay visible — while
        // `displayVersionPattern` keeps the row showing `1.2.26`, which is what the
        // app calls itself. The pattern requires all four segments and
        // `_release_`, so a scheme change or a non-release artifact resolves
        // nothing at all rather than half a number.
        //
        // DO NOT READ `ime.qianwen.com/api/download-config` INSTEAD. It looks like
        // the obvious version source and is a trap on three counts. Its `mac`
        // entry states a `version` that disagrees with the version in its own
        // `url`; its `updatedAt` is frozen; and the page that serves it IGNORES
        // that entry altogether — `normalizePlatformConfig` returns an empty url
        // for mac/windows whenever `buwang.enabled` is true, which it is, and the
        // button goes to `/download/<platform>` and thence to the endpoint above.
        // A recipe on it would report a version below every real install. History
        // has the captured entry.
        //
        // NO CHANGELOG. The vendor publishes no release-notes page (`/changelog`,
        // `/release-notes`, `/updatelog` and `/help` all 404 on `ime.qianwen.com`);
        // the notes ride inside the encrypted PUDS payload and surface only as the
        // app's own "updated" notification. `changelogURL` is omitted rather than
        // pointed at the marketing page, the same call as DoubaoIme.
        //
        // WHAT THIS READS: the newest build published on the official homepage
        // download channel — byte for byte what a person gets by clicking 下载 on
        // `ime.qianwen.com`. Not this machine's allocation; that is PUDS, above,
        // and it is unreadable. The GA argument is Claude's `/latest`, not CapCut's
        // beta track: there is a manual route to this exact artifact.
        //
        // ONE-CLICK, and the thing that decides it is which of this vendor's two
        // scripts is the UPDATE. Read only the installer's and you conclude the
        // opposite of the truth, which is the trap the WeType comment warns about
        // from the other side.
        //
        //   * `macos_install_core.sh`, inside the installer stub, is FIRST INSTALL:
        //     `rm -rf "$INSTALL_ROOT"/QianwenIME*.app`, `chown -R root:staff`,
        //     `chmod -R 775`, `mv -f`, de-quarantine, then force the text-input
        //     subsystem to rescan so the source registers.
        //   * `Contents/Resources/update.sh`, shipped INSIDE the installed bundle
        //     and named in `QianwenIMEService`'s own integrity check, is the
        //     UPDATE — and it is a `Contents` rotation:
        //
        //         CONTENTS_UPDATE="$DESTINATION/Contents_update"
        //         mv "$PAYLOAD_APP/Contents" "$CONTENTS_UPDATE"
        //         "$ATOMIC_SWAP_HELPER" --current "$DESTINATION/Contents" \
        //                               --next    "$CONTENTS_UPDATE"
        //         chown -R root:staff "$DESTINATION"; chmod -R 775 "$DESTINATION"
        //
        //     `QianwenIMEAtomicSwap` imports `renameatx_np` and nothing else of
        //     interest: it takes two directories and exchanges them (`RENAME_SWAP`).
        //     The outer `.app`, its inode and the input-source registration are
        //     left alone — update.sh never touches TIS — and the staging directory
        //     is called `Contents_update`, the same name DoubaoIme's updater uses.
        //
        // So `InPlaceSwap.rotateContents`, which this path gets automatically
        // because `usesContentsRotation` matches on `/Library/Input Methods`, is
        // the SAME shape as the vendor's own update, not a substitute for it. The
        // unprivileged branch matches too: update.sh's non-root path
        // (`update_normally`) is exactly the rotation, and the root path only adds
        // an ownership fix-up first.
        //
        // The artifact takes one extra step, the DoubaoIme one. The DMG's only root
        // app is the installer stub `com.qianwen.inputmethod.desktopime.installer`
        // (Team 8T9NQJXDU3, the installed app's Team), and the real `QianwenIME.app`
        // sits at `Contents/Resources/QianwenIME.zip` — sealed by the stub's own
        // signature, which `VendorInstaller` verifies before reading the payload
        // out of it, after which every gate (signature, Team, bundle id,
        // architecture) runs again on the payload. Without the unwrap the bundle-id
        // gate would refuse the stub, correctly.
        //
        // No `checksumPattern`: the response carries no digest at all, and the
        // `PayloadSHA256` in the stub's `QianwenInstallerMetadata.plist` is both the
        // wrong hash (SHA-256, not base64 SHA-512) and in the wrong place — it
        // describes the nested zip, not the download. Deliberately absent rather
        // than mis-declared, the same call WeType's `zip_download_md5` got.
        //
        // User data is not in the bundle — `~/Library/Application Support/QianwenIME`
        // and the `com.qianwen.inputmethod.desktopime[.*]` preference plists — and
        // `InputMethodDataBackup` finds all of it generically, by bundle name and
        // by bundle-id prefix, so there is nothing to register here.
        VendorProbeRecipe(
            bundleID: "com.qianwen.inputmethod.desktopime",
            url: URL(string: "https://download.qianwen.com/pcdownload/qwenimemac"
                + "?ch=pcqwenime@homepage_official&platform=mac")!,
            mode: .responseBody,
            versionPattern:
                #""url"\s*:\s*"https://[^"]*/QwenimeMac_V([0-9]+(?:\.[0-9]+){3})"#
                + #"_mac_[^"/]*_release_[^"/]*\.dmg""#,
            downloadURL: URL(string: "https://ime.qianwen.com/"),
            versionIsBuild: true,
            displayVersionPattern:
                #""url"\s*:\s*"https://[^"]*/QwenimeMac_V([0-9]+(?:\.[0-9]+){2})\.[0-9]+_mac_"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://[^"]+/QwenimeMac_V[0-9]+(?:\.[0-9]+){3}"#
                    + #"_mac_[^"]*_release_[^"]*\.dmg)""#),
                kind: .dmg,
                nestedArchivePath: "Contents/Resources/QianwenIME.zip")),
        ])
}
