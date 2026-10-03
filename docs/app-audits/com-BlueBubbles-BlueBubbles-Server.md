# BlueBubbles Server

**这不是审计**：family `com-BlueBubbles-BlueBubbles-Server`（`Recipes/com-BlueBubbles-BlueBubbles-Server.swift`）里 BlueBubbles Server `com.BlueBubbles.BlueBubbles-Server` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### 2026-10-02：从只检测改为 Team ID 一键

[org-alacritty.md](org-alacritty.md) 里 2026-08-16 的共享说明把 `com.BlueBubbles.BlueBubbles-Server` 算进七个只检测 rule，理由是产物
「NOT a notarized Developer ID build」，`VendorInstaller` 会拒。两半都不对：

- **没有任何安装闸检查公证或 Gatekeeper 评估。** `SignatureVerifier.verifyInstallArtifact`
  依次是 gate 2 `verifyCodeSignature`（`SecStaticCodeCheckValidity`，flags 为
  `kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate`，
  requirement 传 `nil`）、gate 3 `verifyTeamIdentifierMatch`、gate 4
  `verifyBundleIdentifierMatch`、gate 5/5b 架构、gate 6 `LSMinimumSystemVersion`。
  `DuoUpdaterCore/Sources` 里没有 `SecAssessment*`、`spctl`、`stapler`、`notarization` 调用。
  另外六条在普通路线上被拒的真正原因是**没有 Team ID**：unsigned 挂在 gate 2，ad-hoc 挂在
  gate 3（`noTeamIdentifier`）（其中三条后来改走 digest-only，见 org-alacritty.md）。
- **BlueBubbles 是 Developer ID 签名的。** 实测 v1.9.9（`BlueBubbles-1.9.9-arm64.dmg`，
  300676880 字节，sha256 `fafd650c…2e862`，curl 下载、无 quarantine，`hdiutil attach
  -nobrowse -readonly` 挂载）：
  - `codesign -dv --verbose=4`：`Authority=Developer ID Application: Zachary Shames (WPV275H8W7)`，
    `TeamIdentifier=WPV275H8W7`，hardened runtime，`Mach-O thin (arm64)`
  - `codesign --verify --deep --strict`：valid on disk，退出码 0
  - `spctl -a -vvv -t exec`：`rejected` / `source=Unnotarized Developer ID`；`stapler validate`：无票据
  - Info.plist：`com.BlueBubbles.BlueBubbles-Server` / `1.9.9`（= tag `v1.9.9`）/ build `1.9.9` /
    `LSMinimumSystemVersion` `10.11.0`
  - 把 bundle `ditto` 出来，用临时 Swift test 直接跑生产的
    `SignatureVerifier.verifyInstallArtifact(downloadedApp:installedApp:)`（两边同一个 bundle）：**通过**。
  - 不带后缀的 `BlueBubbles-1.9.9.dmg`（306050865 字节）：同一 Team、同一 id/版本，strict 通过，
    `spctl` 同样 Unnotarized Developer ID，但 `Mach-O thin (x86_64)`——所以模式只锚 `-arm64`
    （DuoUpdater 只跑 arm64；装它等于降到 Rosetta，gate 5b 也会拒）。

  所以 2026-10-02 起它走普通的 Team ID 路线一键（`installTrust` 默认 `.developerID`，
  `Recipes/com-BlueBubbles-BlueBubbles-Server.swift`，`^BlueBubbles-[0-9.]+-arm64\.dmg$` + `.dmg`）；
  这条路线不要求 `digest`，1.9.9 的 digest 为 null 不影响。arm64 dmg 从 v1.9.8 起才有；stable rule 读
  `/releases/latest`，更早只有一个 dmg 的 release 不会被读到。该正则在全部非预发布 release
  里每个最多匹配一个资产（v1.9.3 没有资产）。

**未验证：换装后首次启动会不会弹 Gatekeeper。** 没有启动任何东西。依据只有：
`InPlaceSwap.replace` 在闸通过后、换装前跑 `stripQuarantine`（`xattr -drs com.apple.quarantine`）；
Apple 的 Platform Security Guide 把 Gatekeeper 的「identified developer + notarized」检查描述为针对
用户**下载**并打开的软件
（<https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web>），
没有正面写「无 quarantine 就不查公证」；明确这么写的是第三方 Eclectic Light
（<https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/>：没有 quarantine
标记的 app 公证照查，但无需用户操作即可运行）。XProtect 仍会在首次启动 / 文件变化后扫描
（<https://support.apple.com/guide/security/protecting-against-malware-sec469d47bd8/web>），那是恶意软件
特征扫描，不是公证门槛。
