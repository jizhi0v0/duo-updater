# Node.js 22 ChangeLog

<!--lint disable maximum-line-length no-literal-urls prohibited-strings-->

<table>
<tr>
<th>LTS 'Jod'</th>
<th>Current</th>
</tr>
<tr>
<td>
<a href="#22.23.4">22.23.4</a><br/>
<a href="#22.23.3">22.23.3</a><br/>
<a href="#22.23.2">22.23.2</a><br/>
<a href="#22.23.1">22.23.1</a><br/>
<a href="#22.23.0">22.23.0</a><br/>
<a href="#22.22.3">22.22.3</a><br/>
<a href="#22.22.2">22.22.2</a><br/>
<a href="#22.22.1">22.22.1</a><br/>
<a href="#22.22.0">22.22.0</a><br/>
<a href="#22.21.1">22.21.1</a><br/>
<a href="#22.21.0">22.21.0</a><br/>
<a href="#22.20.0">22.20.0</a><br/>
<a href="#22.19.0">22.19.0</a><br/>
<a href="#22.18.0">22.18.0</a><br/>
<a href="#22.17.1">22.17.1</a><br/>
<a href="#22.17.0">22.17.0</a><br/>
<a href="#22.16.0">22.16.0</a><br/>
<a href="#22.15.1">22.15.1</a><br/>
<a href="#22.15.0">22.15.0</a><br/>
<a href="#22.14.0">22.14.0</a><br/>
<a href="#22.13.1">22.13.1</a><br/>
<a href="#22.13.0">22.13.0</a><br/>
<a href="#22.12.0">22.12.0</a><br/>
<a href="#22.11.0">22.11.0</a><br/>
</td>
<td>
<a href="#22.10.0">22.10.0</a><br/>
<a href="#22.9.0">22.9.0</a><br/>
<a href="#22.8.0">22.8.0</a><br/>
<a href="#22.7.0">22.7.0</a><br/>
<a href="#22.6.0">22.6.0</a><br/>
<a href="#22.5.1">22.5.1</a><br/>
<a href="#22.5.0">22.5.0</a><br/>
<a href="#22.4.1">22.4.1</a><br/>
<a href="#22.4.0">22.4.0</a><br/>
<a href="#22.3.0">22.3.0</a><br/>
<a href="#22.2.0">22.2.0</a><br/>
<a href="#22.1.0">22.1.0</a><br/>
<a href="#22.0.0">22.0.0</a><br/>
</td>
</tr>
</table>

* Other Versions
  * [26.x](CHANGELOG_V26.md)
  * [25.x](CHANGELOG_V25.md)
  * [24.x](CHANGELOG_V24.md)
  * [23.x](CHANGELOG_V23.md)
  * [21.x](CHANGELOG_V21.md)
  * [20.x](CHANGELOG_V20.md)
  * [19.x](CHANGELOG_V19.md)
  * [18.x](CHANGELOG_V18.md)
  * [17.x](CHANGELOG_V17.md)
  * [16.x](CHANGELOG_V16.md)
  * [15.x](CHANGELOG_V15.md)
  * [14.x](CHANGELOG_V14.md)
  * [13.x](CHANGELOG_V13.md)
  * [12.x](CHANGELOG_V12.md)
  * [11.x](CHANGELOG_V11.md)
  * [10.x](CHANGELOG_V10.md)
  * [9.x](CHANGELOG_V9.md)
  * [8.x](CHANGELOG_V8.md)
  * [7.x](CHANGELOG_V7.md)
  * [6.x](CHANGELOG_V6.md)
  * [5.x](CHANGELOG_V5.md)
  * [4.x](CHANGELOG_V4.md)
  * [0.12.x](CHANGELOG_V012.md)
  * [0.10.x](CHANGELOG_V010.md)
  * [io.js](CHANGELOG_IOJS.md)
  * [Archive](CHANGELOG_ARCHIVE.md)

<a id="22.23.4"></a>

## 2026-10-21, Version 22.23.4 'Jod' (LTS), @aduh95

This is a security release.

### Notable Changes

* (CVE-2026-105481) http: ensure agent data guard works without I/O (James M Snell)
* (CVE-2026-105482) dns: validate resolve inputs for null bytes (James M Snell)
* (CVE-2026-106069) tls: reject non-canonical IP addresses (Matteo Collina)
* (CVE-2026-106073) permission: check permission model in realpathSync (RafaelGSS)
* (CVE-2026-106074) crypto: reset random caches across snapshots (Filip Skokan)
* (CVE-2026-111497) src: expose `BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH` (Antoine du Hamel)
* (CVE-2026-111497) deps: brotli: cherry-pick 0ed4268a4401abcb44720963 (Evgenii Kliuchnikov)
* crypto: update root certificates to NSS 3.131.1 (Antoine du Hamel)
* deps: update c-ares to 1.34.9 (Node.js GitHub Bot)
* deps: update timezone to 2026e (Node.js GitHub Bot)
* deps: upgrade openssl sources to openssl-3.5.9 (Node.js GitHub Bot)
* deps: update sqlite to 3.53.4 (Node.js GitHub Bot)
* deps: update undici to 6.29.1 (Node.js GitHub Bot)

### Commits

* \[[`68fa0df6d6`](https://github.com/nodejs/node/commit/68fa0df6d6)] - **crypto**: update root certificates to NSS 3.131.1 (Antoine du Hamel) [#66877](https://github.com/nodejs/node/pull/66877)
* \[[`dd6b47573b`](https://github.com/nodejs/node/commit/dd6b47573b)] - **crypto**: reset random caches across snapshots (Filip Skokan) [nodejs-private/node-private#987](https://github.com/nodejs-private/node-private/pull/987)
* \[[`a62b7d5362`](https://github.com/nodejs/node/commit/a62b7d5362)] - **crypto**: harden X.509 conversion and formatting (Filip Skokan) [nodejs-private/node-private#966](https://github.com/nodejs-private/node-private/pull/966)
* \[[`ec9e5e4a3e`](https://github.com/nodejs/node/commit/ec9e5e4a3e)] - **crypto**: update root certificates to NSS 3.129 (Node.js GitHub Bot) [#66496](https://github.com/nodejs/node/pull/66496)
* \[[`a538a9515d`](https://github.com/nodejs/node/commit/a538a9515d)] - **deps**: update c-ares to 1.34.9 (Node.js GitHub Bot) [#66868](https://github.com/nodejs/node/pull/66868)
* \[[`67d294739f`](https://github.com/nodejs/node/commit/67d294739f)] - **deps**: brotli: cherry-pick 0ed4268a4401abcb44720963 (Evgenii Kliuchnikov) [nodejs-private/node-private#1002](https://github.com/nodejs-private/node-private/pull/1002)
* \[[`1ab9db8a74`](https://github.com/nodejs/node/commit/1ab9db8a74)] - **deps**: update timezone to 2026e (Node.js GitHub Bot) [#66419](https://github.com/nodejs/node/pull/66419)
* \[[`52b4bcab03`](https://github.com/nodejs/node/commit/52b4bcab03)] - **deps**: update timezone to 2026d (Node.js GitHub Bot) [#66333](https://github.com/nodejs/node/pull/66333)
* \[[`60f4833d41`](https://github.com/nodejs/node/commit/60f4833d41)] - **deps**: update archs files for openssl-3.5.9 (Node.js GitHub Bot) [#66396](https://github.com/nodejs/node/pull/66396)
* \[[`05470dc308`](https://github.com/nodejs/node/commit/05470dc308)] - **deps**: upgrade openssl sources to openssl-3.5.9 (Node.js GitHub Bot) [#66396](https://github.com/nodejs/node/pull/66396)
* \[[`47333fe4f4`](https://github.com/nodejs/node/commit/47333fe4f4)] - **deps**: update sqlite to 3.53.4 (Node.js GitHub Bot) [#64745](https://github.com/nodejs/node/pull/64745)
* \[[`98258b855f`](https://github.com/nodejs/node/commit/98258b855f)] - **deps**: update sqlite to 3.53.3 (Node.js GitHub Bot) [#64180](https://github.com/nodejs/node/pull/64180)
* \[[`a8349b6408`](https://github.com/nodejs/node/commit/a8349b6408)] - **deps**: update sqlite to 3.53.2 (Node.js GitHub Bot) [#63774](https://github.com/nodejs/node/pull/63774)
* \[[`e9e295bcc1`](https://github.com/nodejs/node/commit/e9e295bcc1)] - **deps**: cherry-pick e807d4e379 from SQLite (Junsu Han) [#63525](https://github.com/nodejs/node/pull/63525)
* \[[`512a9b61f0`](https://github.com/nodejs/node/commit/512a9b61f0)] - **deps**: update sqlite to 3.53.1 (Node.js GitHub Bot) [#63217](https://github.com/nodejs/node/pull/63217)
* \[[`e708247254`](https://github.com/nodejs/node/commit/e708247254)] - **deps**: update sqlite to 3.53.0 (Node.js GitHub Bot) [#62699](https://github.com/nodejs/node/pull/62699)
* \[[`857be5afa3`](https://github.com/nodejs/node/commit/857be5afa3)] - **deps**: update undici to 6.29.1 (Node.js GitHub Bot) [#66765](https://github.com/nodejs/node/pull/66765)
* \[[`19c5056002`](https://github.com/nodejs/node/commit/19c5056002)] - **dns**: validate resolve inputs for null bytes (James M Snell) [nodejs-private/node-private#984](https://github.com/nodejs-private/node-private/pull/984)
* \[[`e7b2985d59`](https://github.com/nodejs/node/commit/e7b2985d59)] - **http**: ensure agent data guard works without I/O (James M Snell) [nodejs-private/node-private#983](https://github.com/nodejs-private/node-private/pull/983)
* \[[`50ab804edc`](https://github.com/nodejs/node/commit/50ab804edc)] - **permission**: check permission model in realpathSync (RafaelGSS) [nodejs-private/node-private#973](https://github.com/nodejs-private/node-private/pull/973)
* \[[`a18ec92752`](https://github.com/nodejs/node/commit/a18ec92752)] - **src**: expose `BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH` (Antoine du Hamel) [nodejs-private/node-private#1002](https://github.com/nodejs-private/node-private/pull/1002)
* \[[`4342503fd8`](https://github.com/nodejs/node/commit/4342503fd8)] - **tls**: reject chains containing blocked public keys (Ulises Gascon) [#66871](https://github.com/nodejs/node/pull/66871)
* \[[`d7663560ac`](https://github.com/nodejs/node/commit/d7663560ac)] - **tls**: reject non-canonical IP addresses (Matteo Collina) [nodejs-private/node-private#982](https://github.com/nodejs-private/node-private/pull/982)
* \[[`beb4cd4cd3`](https://github.com/nodejs/node/commit/beb4cd4cd3)] - **tls**: match IPv6 hosts against IP-Address SANs (Pascal Garber) [#64145](https://github.com/nodejs/node/pull/64145)
* \[[`4b42e56aaf`](https://github.com/nodejs/node/commit/4b42e56aaf)] - **tools**: retry Gatekeeper check and stapling after notarization (Ryan Aslett) [#66855](https://github.com/nodejs/node/pull/66855)

<a id="22.23.3"></a>

## 2026-09-23, Version 22.23.3 'Jod' (LTS), @aduh95 prepared by @juanarbol

### Notable Changes

* \[[`fe2a6b2be8`](https://github.com/nodejs/node/commit/fe2a6b2be8)] - **crypto**: update root certificates to NSS 3.125 (Node.js GitHub Bot) [#64746](https://github.com/nodejs/node/pull/64746)
* \[[`871167ddfd`](https://github.com/nodejs/node/commit/871167ddfd)] - **deps**: update corepack to 0.36.0 (Node.js GitHub Bot) [#65653](https://github.com/nodejs/node/pull/65653)
* \[[`b816fc8958`](https://github.com/nodejs/node/commit/b816fc8958)] - **deps**: upgrade npm to 10.9.9 (npm team) [#64884](https://github.com/nodejs/node/pull/64884)
* \[[`e306521444`](https://github.com/nodejs/node/commit/e306521444)] - **deps**: update icu to 78.3 (Node.js GitHub Bot) [#62324](https://github.com/nodejs/node/pull/62324)
* \[[`a9cb31129f`](https://github.com/nodejs/node/commit/a9cb31129f)] - **deps**: update OpenSSL 3.5.8 (Node.js GitHub Bot) [#65542](https://github.com/nodejs/node/pull/65542)
* \[[`2a3548e51c`](https://github.com/nodejs/node/commit/2a3548e51c)] - **deps**: update Undici to 6.28.1 (mcollina) [#65790](https://github.com/nodejs/node/pull/65790)
* \[[`3909ff2c4a`](https://github.com/nodejs/node/commit/3909ff2c4a)] - **node-api**: support `SharedArrayBuffer` in `napi_create_typedarray` (Yilong Li) [#62710](https://github.com/nodejs/node/pull/62710)
* \[[`66de6349ad`](https://github.com/nodejs/node/commit/66de6349ad)] - **node-api**: add `napi_create_external_sharedarraybuffer` (Ben Noordhuis) [#62623](https://github.com/nodejs/node/pull/62623)

### Commits

* \[[`44cf27b8fa`](https://github.com/nodejs/node/commit/44cf27b8fa)] - **build**: update binary-upload to use correct tarball name (Stewart X Addison) [#65282](https://github.com/nodejs/node/pull/65282)
* \[[`fe2a6b2be8`](https://github.com/nodejs/node/commit/fe2a6b2be8)] - **crypto**: update root certificates to NSS 3.125 (Node.js GitHub Bot) [#64746](https://github.com/nodejs/node/pull/64746)
* \[[`71feba6b69`](https://github.com/nodejs/node/commit/71feba6b69)] - **crypto**: update root certificates to NSS 3.123.1 (Node.js GitHub Bot) [#63527](https://github.com/nodejs/node/pull/63527)
* \[[`871167ddfd`](https://github.com/nodejs/node/commit/871167ddfd)] - **deps**: update corepack to 0.36.0 (Node.js GitHub Bot) [#65653](https://github.com/nodejs/node/pull/65653)
* \[[`2a3548e51c`](https://github.com/nodejs/node/commit/2a3548e51c)] - **deps**: update undici to 6.28.1 (mcollina) [#65790](https://github.com/nodejs/node/pull/65790)
* \[[`59d853a4df`](https://github.com/nodejs/node/commit/59d853a4df)] - **deps**: update archs files for openssl-3.5.8 (Node.js GitHub Bot) [#65542](https://github.com/nodejs/node/pull/65542)
* \[[`a9cb31129f`](https://github.com/nodejs/node/commit/a9cb31129f)] - **deps**: upgrade openssl sources to openssl-3.5.8 (Node.js GitHub Bot) [#65542](https://github.com/nodejs/node/pull/65542)
* \[[`3376e27de2`](https://github.com/nodejs/node/commit/3376e27de2)] - **deps**: V8: cherry-pick a6eaf7574109 (Camillo Bruni) [#65402](https://github.com/nodejs/node/pull/65402)
* \[[`b816fc8958`](https://github.com/nodejs/node/commit/b816fc8958)] - **deps**: upgrade npm to 10.9.9 (npm team) [#64884](https://github.com/nodejs/node/pull/64884)
* \[[`4e4bd1b104`](https://github.com/nodejs/node/commit/4e4bd1b104)] - **deps**: update timezone to 2026c (Node.js GitHub Bot) [#64588](https://github.com/nodejs/node/pull/64588)
* \[[`7d82841b4e`](https://github.com/nodejs/node/commit/7d82841b4e)] - **deps**: update c-ares to 1.34.8 (Node.js GitHub Bot) [#64330](https://github.com/nodejs/node/pull/64330)
* \[[`01855a19d3`](https://github.com/nodejs/node/commit/01855a19d3)] - **deps**: c-ares: cherry-pick 8ba37af8e3fb (René) [#64110](https://github.com/nodejs/node/pull/64110)
* \[[`23fb398c3d`](https://github.com/nodejs/node/commit/23fb398c3d)] - **deps**: update corepack to 0.35.0 (Node.js GitHub Bot) [#63375](https://github.com/nodejs/node/pull/63375)
* \[[`5286330365`](https://github.com/nodejs/node/commit/5286330365)] - **deps**: update corepack to 0.34.7 (Node.js GitHub Bot) [#62810](https://github.com/nodejs/node/pull/62810)
* \[[`6d6c3c98b1`](https://github.com/nodejs/node/commit/6d6c3c98b1)] - **deps**: update timezone to 2026b (Node.js GitHub Bot) [#62962](https://github.com/nodejs/node/pull/62962)
* \[[`e306521444`](https://github.com/nodejs/node/commit/e306521444)] - **deps**: update icu to 78.3 (Node.js GitHub Bot) [#62324](https://github.com/nodejs/node/pull/62324)
* \[[`d9cb8468a3`](https://github.com/nodejs/node/commit/d9cb8468a3)] - **doc**: clarify `filter` option of `sqlite.database.applyChangeset` (Antoine du Hamel) [#63515](https://github.com/nodejs/node/pull/63515)
* \[[`c9c5662d91`](https://github.com/nodejs/node/commit/c9c5662d91)] - **doc**: add sxa GPG key (ed25519) (Stewart X Addison) [#64193](https://github.com/nodejs/node/pull/64193)
* \[[`37f21068c4`](https://github.com/nodejs/node/commit/37f21068c4)] - **fs**: restore fs patchability in ESM loader (Joyee Cheung) [#62835](https://github.com/nodejs/node/pull/62835)
* \[[`7c2df5dd96`](https://github.com/nodejs/node/commit/7c2df5dd96)] - **http2**: avoid uaf while receiving and sending rst\_stream (esgor) [#64166](https://github.com/nodejs/node/pull/64166)
* \[[`3909ff2c4a`](https://github.com/nodejs/node/commit/3909ff2c4a)] - **node-api**: support SharedArrayBuffer in napi\_create\_typedarray (Yilong Li) [#62710](https://github.com/nodejs/node/pull/62710)
* \[[`66de6349ad`](https://github.com/nodejs/node/commit/66de6349ad)] - **node-api**: add napi\_create\_external\_sharedarraybuffer (Ben Noordhuis) [#62623](https://github.com/nodejs/node/pull/62623)
* \[[`ce9139107f`](https://github.com/nodejs/node/commit/ce9139107f)] - **src**: escape Windows environment variables in task runner (Antoine du Hamel) [#65217](https://github.com/nodejs/node/pull/65217)
* \[[`839480a471`](https://github.com/nodejs/node/commit/839480a471)] - **test**: fix link-local dgram scope assertion (Filip Skokan) [#65629](https://github.com/nodejs/node/pull/65629)
* \[[`40eac4a32f`](https://github.com/nodejs/node/commit/40eac4a32f)] - **test**: account for varied OpenSSL CCM final behaviours (Filip Skokan) [#65542](https://github.com/nodejs/node/pull/65542)
* \[[`75098a9e8c`](https://github.com/nodejs/node/commit/75098a9e8c)] - **tools**: update gr2m/create-or-update-pull-request-action to v1.10.1 (Mike McCready) [#63065](https://github.com/nodejs/node/pull/63065)
* \[[`08b6ac0416`](https://github.com/nodejs/node/commit/08b6ac0416)] - **tools**: revert OpenSSL update workflow to ubuntu-latest (Richard Lau) [#62627](https://github.com/nodejs/node/pull/62627)
* \[[`02cafc479f`](https://github.com/nodejs/node/commit/02cafc479f)] - **tools**: fix commit linter for semver-major release proposals (Antoine du Hamel) [#62993](https://github.com/nodejs/node/pull/62993)
* \[[`6f6cd3768d`](https://github.com/nodejs/node/commit/6f6cd3768d)] - **tools**: sync mk-ca-bundle.pl with curl (Archkon) [#64753](https://github.com/nodejs/node/pull/64753)
* \[[`bc5753d438`](https://github.com/nodejs/node/commit/bc5753d438)] - **tools**: remove `envinfo` from our workflows (Antoine du Hamel) [#64259](https://github.com/nodejs/node/pull/64259)
* \[[`d68ee9f8a5`](https://github.com/nodejs/node/commit/d68ee9f8a5)] - **tools**: validate version number in release proposal commit message lint (Antoine du Hamel) [#64070](https://github.com/nodejs/node/pull/64070)
* \[[`38ee2e895f`](https://github.com/nodejs/node/commit/38ee2e895f)] - **tools**: avoid test/fixtures/wpt/README.md conflicts (Filip Skokan) [#63938](https://github.com/nodejs/node/pull/63938)
* \[[`fdc65e489f`](https://github.com/nodejs/node/commit/fdc65e489f)] - **tools**: use different branch for tool updates on staging branches (Antoine du Hamel) [#63110](https://github.com/nodejs/node/pull/63110)
* \[[`e5a6fde002`](https://github.com/nodejs/node/commit/e5a6fde002)] - **tools**: update gyp-next to 0.22.1 (Node.js GitHub Bot) [#62961](https://github.com/nodejs/node/pull/62961)
* \[[`5fbbad6e82`](https://github.com/nodejs/node/commit/5fbbad6e82)] - **url**: handle unparsable serialized URLs in setters (Matteo Collina) [#64651](https://github.com/nodejs/node/pull/64651)
* \[[`ed019e4854`](https://github.com/nodejs/node/commit/ed019e4854)] - **util**: preserve function names without source map names (Hiroki Osame) [#65108](https://github.com/nodejs/node/pull/65108)

