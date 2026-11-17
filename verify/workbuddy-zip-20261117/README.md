# WorkBuddy AI ZIP 与夜扫验证（2026-11-17）

本次修复的验证记录。基于 `16e436c2c91cb73f87e398d8f0e92645b00d3a95`；
[candidate.patch](candidate.patch) 固定了测试的 recipe、fixture 与 golden 变化。
生产代码仅在国际版两条 recipe 复用已有 `installsZip: true`，沿用国内版的 ZIP 路径。
CLI 在 Mac 本地构建后传入 VM，没有在 VM 编译诊断程序。
对照 CLI 来自先前的 `525711a7` 构建，WorkBuddy recipe、安装与巡检代码和基准 main 相同。

## VM 结果

Apple Silicon，macOS 27.2。使用隔离的测试应用路径和 `DUO_STATE_DIR`。

- 真实 5.9.4 副本经过旧规则安装：`applied: false`、`checksum didn't match`。
  失败前后的 plist inode / mtime / size 相同。
- 同一路径经过 ZIP 候选安装：`applied: true`、`outcome: installed`，
  下载 **475,192,215 B**，盘上版本变为 **5.11.4**。
- `codesign --verify --deep --strict` 成功，Bundle ID `com.workbuddy.workbuddy-ai`，
  Team `FN2V63AD2J`，arm64；Gatekeeper 为 `accepted / Notarized Developer ID`。
- 通过 LaunchServices 启动，8 秒后真实主进程仍在。随后结束测试副本的进程，移除测试应用。
- arm64 / x64 的实际 ZIP SHA-256 均等于各自实时更新响应的 `sha256hash`。
  x64 仅做下载摘要核对，没有在 Apple Silicon VM 声称完成 x64 安装或启动。
- `.zip.blockmap` 与 `.dmg.blockmap` 两架构均 HTTP 404；真实包无 `app-update.yml`，
  响应 `supportsFastUpdate: false`。这次验证的是全量 ZIP，没有差分下载收益的证据。

原始安装 JSON、元数据、签名/启动结果及摘要在 [vm/](vm/)。没有测试运行中替换、登录或业务功能。

## 历史边界补查

[11 月 10 日的完整安装巡检](https://github.com/jizhi0v0/duo-updater/actions/runs/42731456094)
于 01:32:02 UTC 生成报告，实际下载国际版 5.9.4 的 DMG：arm64 408,500,901 B、x64 439,693,678 B，均为 `ok`，
身份仍为 `com.workbuddy.workbuddy-ai` / `FN2V63AD2J`。
[保留的原始条目](scheduled-42731456094-workbuddy.json) 证明此前 DMG 路线确实成功，而非从首次接入起一直失败。
该报告没有保留完整 API 原文和解析后的预期摘要，不能用它重建每一版的摘要字段；也没有 5.10.x / 5.11.x 所有版本的逐版记录，
因此目前只能确认“5.9.4 曾成功、5.11.4 当前摘要对应 ZIP”，不能确定变化首次发生在哪一版。

## 夜扫告警延迟（15:06 UTC 调查时点）

普通 `duo verify` 只看 feed 和 URL。安装包摘要另由 `Install verify` 工作流的
`duo verify-install` 检查，WorkBuddy 的 Vendor registry 已被自动枚举。

1. [定时 run 43992623527](https://github.com/jizhi0v0/duo-updater/actions/runs/43992623527)
   于 01:03:50 UTC 启动，01:12:09 UTC 报告仍读到 **5.9.4**；因为版本、URL 和上次干净结果相同，
   arm64 跳过下载。此行不是对 5.11.4 包的成功验证。
   [保留的 WorkBuddy 行](scheduled-43992623527-workbuddy.json)。
2. 下一次 [定时 run 44107997500](https://github.com/jizhi0v0/duo-updater/actions/runs/44107997500)
   于 **14:53:03 UTC** 启动，实际启动间隔约 **13 小时 49 分**，而配置是每天四次。
   15:06 UTC 查询时仍在执行巡检，未到 reconcile；GitHub 调度间隔的具体原因未确定。
3. `Baseline.actionableThreshold` 是 **2**。一次失败记入报告和 baseline，但还不自动开 issue。
   verifier 的退出码 1 是有 findings 的正常执行结果，工作流仍继续 reconcile，所以 Actions 绿色
   本身不代表每个安装包都健康。

没有缺失 WorkBuddy 监控项的证据；已有检查能看到错误，自动告警存在采样与连续两轮门槛的延迟。
另有普通夜扫已开的 [#2076](https://github.com/jizhi0v0/duo-updater/issues/2076)，
它报告 changelog 仍为 5.9.4、落后于检测版本 5.11.4，不能当作摘要告警。

## 用同一夜扫命令复核

在 VM 使用生产 CLI，限定 `--only com.workbuddy.workbuddy-ai --full`，使用原始
identity / baseline 的私有副本；没有修改仓库监控状态、重置锚点或添加豁免，也没有执行 reconcile。

- 旧规则：[nightly-control.json](vm/nightly-control.json) 返回 arm64 `failed / checksum`，
  下载 405,771,057 B 的 DMG；finding 为 `broken / install.checksum`。
  [baseline](vm/baseline-control.json) 的 `consecutiveActionable` 从 0 到 1。
- 候选规则：[nightly-zip.json](vm/nightly-zip.json) 返回 arm64 `ok`，
  下载 475,192,215 B 的 ZIP，Bundle ID / Team 与既有身份锚一致。
  x64 按支持宿主范围跳过，不算安装包验证通过。
- [scoped-tests.log](scoped-tests.log)：WorkBuddy recipe 与 recipe golden 共 **22 项通过**。
  另通过 app-audit、recipe snapshot、prose-claim 检查和 `git diff --check`。

没有发布、部署或更改夜扫配置。

## 本地脚本检查限制

提交前额外运行 `make test-scripts`，在既有
`PinnedScript.test_a_failed_download_is_an_error_not_an_empty_path` 用例失败：
预期错误文本包含 `could not download`，本机输出却继续到缺失 ZIP 的 `shasum`。
独立重跑同一测试仍失败；`scripts/pinned-xcodegen.sh`、其测试与 Makefile 均和基准 main 相同，
本 PR 不修改这些文件。相关 WorkBuddy/Golden 测试及前述三项审计检查已通过；完整必需检查以 PR CI 结果为准。
