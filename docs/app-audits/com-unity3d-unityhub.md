# Unity Hub

**这不是审计**：family `com-unity3d-unityhub`（`Recipes/com-unity3d-unityhub.swift`）里 Unity Hub `com.unity3d.unityhub` 的覆盖情况没有审过。这份文件只接收 recipe 的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/com-unity3d-unityhub.swift — 一键接上 `latest-mac.yml` 的 sha512（2026-10-07）

原先没挂 `checksumPattern`。查过 recipe 注释和引入它的 commit（`9a5e0889`，2026-08-16 vendor batch），没有写理由，也没有像 Signal 那样记过「feed 摘要对不上下载」；这次实测对得上，就接上了。格式是默认的 `.sha512Base64`。

实测（2026-10-07，GET `public-cdn.cloud.unity3d.com/hub/prod/latest-mac.yml`）：`version: 3.22.2`，`files:` 依次是 arm64 zip、x64 zip、arm64 dmg、x64 dmg 四项，键顺序都是 `url, sha512, size`；之后是顶层 `path:`（指 arm64 zip）和 `sha512:`。URL pattern 取到第一项 `3.22.2/UnityHubSetup-3.22.2-arm64.zip`。下载 `…/hub/prod/3.22.2/UnityHubSetup-3.22.2-arm64.zip`（222,152,452 B，等于该项的 `size`）后实算 base64 SHA-512 = `/O1VW7I/GSSt…uhITtA==`，与该项的 `sha512` 逐字相等（顶层 `sha512:` 也是同一个值，因为 `path:` 就是这个 zip）。与 Signal 不同：Signal 的 CDN 在出包后又 staple，下载比 `size` 大 2563 字节，摘要永远对不上；这里大小与摘要都一致。

生产路径（临时 Swift test，跑完已删）：`VendorProbeSource.probeDiagnostic` 对线上端点解析出 3.22.2、上面的下载 URL，`expectedSHA512` 等于该项摘要、`expectedSHA256` 为 nil、无 warning；把下载到的 zip 交给 `VendorInstaller.apply`，越过摘要闸进入 `extracting`；同一文件翻转一个字节后被拒为 `checksumMismatch`。
