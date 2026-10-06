# Wave Terminal

**这不是审计**：family `dev-commandline-waveterm`（`Recipes/dev-commandline-waveterm.swift`）里 Wave Terminal `dev.commandline.waveterm` 的覆盖情况没有审过。这份文件只接收 recipe 的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/dev-commandline-waveterm.swift — 一键接上 `latest-mac.yml` 的 sha512（2026-10-07）

原先没挂 `checksumPattern`。查过 recipe 注释和引入它的 commit（`9a5e0889`，2026-08-16 vendor batch），没有写理由，也没有像 Signal 那样记过「feed 摘要对不上下载」；这次实测对得上，就接上了。格式是默认的 `.sha512Base64`。

实测（2026-10-07，GET `dl.waveterm.dev/releases-w2/latest-mac.yml`）：`version: 0.14.5`，`files:` 共 10 项，第一项是 arm64 zip，之后 x64 zip 重复 3 次、arm64 dmg 重复 3 次、x64 dmg 重复 3 次（重复项内容相同），键顺序都是 `url, sha512, size`；之后是顶层 `path:`（指 arm64 zip）和 `sha512:`。URL pattern 取到第一项 `Wave-darwin-arm64-0.14.5.zip`。下载 `dl.waveterm.dev/releases-w2/Wave-darwin-arm64-0.14.5.zip`（192,631,777 B，等于该项的 `size`）后实算 base64 SHA-512 = `mFzBsQz8dWk5…aTgprg==`，与该项的 `sha512` 逐字相等（顶层 `sha512:` 也是同一个值）。与 Signal 不同：Signal 的 CDN 在出包后又 staple，下载比 `size` 大 2563 字节，摘要永远对不上；这里大小与摘要都一致。

生产路径（临时 Swift test，跑完已删）：`VendorProbeSource.probeDiagnostic` 对线上端点解析出 0.14.5、上面的下载 URL，`expectedSHA512` 等于该项摘要、`expectedSHA256` 为 nil、无 warning；把下载到的 zip 交给 `VendorInstaller.apply`，越过摘要闸进入 `extracting`；同一文件翻转一个字节后被拒为 `checksumMismatch`。
