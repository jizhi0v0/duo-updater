# HTTP 与自动更新仿真

本改动先搭建可重复仿真，再以实验发现的问题修正生产网络与自动更新逻辑。测试调用实际网络、下载、续传和自动更新核心函数，记录响应状态、请求次数、请求头、文件内容与调度判定。

测试通过表示观察结果符合用例断言。名称或注释标为当前行为的用例不等于认可其产品策略，尤其是统一的 24 小时冷却、3 次失败后放弃，以及服务端等待要求的处理。

## 生产修复

- Retry-After 支持秒数和三种 HTTP-date；内联重试与下一次实际等待比较，长等待结束本轮。版本 feed 和厂商安装地址探测在同一进程、同一 session 的后续轮次保留端点冷却，到期前不发网络、不占扫描槽长睡。按 endpoint、GET/HEAD 方法及标准显式凭据隔离；条件、Range 和 trace 头变化不能绕过冷却。GitHub API 保留专用限流 gate。
- 旧片段不再让 403、429、5xx、证书或磁盘错误获得一次额外重发。只有明确无法使用的旧片段范围或对象 validator 变化才可有界从零恢复。
- HTML 错误页恢复和断线续传共用最多 5 次获取请求预算；HTML 重取有可取消的退避，最终错误页删除并以内容错误拒绝。预算指 data task 初始 GET，安全重定向的每一跳不另占一次。
- 下载拒绝携带有效未来 Retry-After 时保留 typed deadline，公开诊断仍得到原 HTTP code。自动获取的恢复时间取默认 24 小时与服务端截止时间的较晚者。
- 自动更新只在有同步、单调的阶段证据时恢复暂时性获取错误；获取失败使用独立、最多 3 次失败的预算。拒绝访问、内容/完整性、TLS、本地错误及获取之后的失败暂停同一 offered version，手动操作仍可尝试。新版本清新策略的暂停；既有账本和拒绝退出的历史约束保持兼容。
- 失败与拒绝退出按本次实际 attempted version 记账，防止安装前复查换版本后下一轮误清暂停。阶段跨 Task/Dispatch 保留，fallback 回到下载状态也不能清掉已经验证/安装的证据。

## 生产修复验证与审查（2026-11-12）

生产实现提交：`7c131ab395cff792764fb3abd9cd380081fffa75`。在 Apple Silicon、macOS 27.3、Swift 6.4.2 上执行：

- `scripts/test-http-simulation.sh`：106 个测试、5 个 suite，通过；参数化展开 391 个场景。覆盖真实 loopback 获取、重定向、ZIP 解包、文件写入/删除以及生产自动失败捕获器。
- 新仿真与相关旧测试（另含 InstallURLTransient、InstallRedirectDeferral）：251 个测试、19 个 suite，通过。
- `swift test --package-path CLI --scratch-path DuoUpdaterCore/.build --disable-automatic-resolution --jobs 4`：699 个测试、78 个 suite，通过。GUI 与 CLI 共用的下载和公开 HTTP 诊断保持可编译、可执行。
- `xcodebuild` 对真正的 `DuoUpdater` scheme、Debug、arm64、禁用签名执行 build：`BUILD SUCCEEDED`。这实际编译了 AppListModel；AppTests target 不包含它，未用 AppTests 冒充 App 构建。
- 移除单调获取/安装阶段保护：新测试以 7 个断言失败抓到越界后恢复权限；移除跨轮冷却：6 个断言失败抓到额外请求；恢复旧片段拒绝盲重发：35 个断言失败抓到错误重试。三个变异均已恢复，生产源码与审查提交一致。

独立 Astra medium 对该实现进行只读对抗审查，未发现可确认的 blocking defect：

- data-loss：核查 partial/HTML 删除、预算耗尽、取消清理，只操作续传 lease 或自身 workDir。
- trust / secrets：未放宽签名、摘要、证书或重定向守卫；冷却状态无 raw URL、凭据或响应 body，标准凭据/session/方法隔离。
- process-control：核查 InstallJobs 的 TaskLocal 继承、创建回调时捕获 Attempt、单调阶段、退出后暂停、取消与手动入口边界。
- 审查员亲自核对仿真和 App build 日志，未自行构建或执行测试。

验证范围：原生 Core 集成仿真与 App 编译，不等于完整 AppListModel 的运行时调度、真实应用退出/重开或真实 TLS/CDN 的端到端验证。普通端点冷却是进程内状态，不跨重启持久化；自定义账号头保守共享冷却；GitHub API 继续使用既有专用 gate。无法进一步区分的 after-quit Deferred 保持既有退避，而非新增重试权限。

## 运行

在仓库根目录运行：

```sh
scripts/test-http-simulation.sh
```

入口先构建并枚举测试，确认五个 suite 均存在，再执行 `HTTP.*SimulationTests`。缺少 suite 或用例失败都会返回非零退出码。`DUO_STATE_DIR` 指向本次运行的临时目录，退出后清理；不启动 DuoUpdater，不执行真实应用安装或退出，不修改代理与用户设置。

| Suite | 负责的路径 |
| --- | --- |
| `HTTPDownloadStatusSimulationTests` | `Downloader` 的状态码、文件响应、Range、传输失败与重定向 |
| `HTTPVersionSourceSimulationTests` | 版本 feed、GitHub 与 Vendor source 的响应解析、缓存、凭据和重试 |
| `HTTPRetryAfterSimulationTests` | 服务端等待要求、厂商下载地址解析与可达性探测 |
| `HTTPAutomaticUpdateSimulationTests` | 固定时间下的检查间隔、失败账本、取消、退出和提交边界 |
| `HTTPAutomaticUpdateFailureSimulationTests` | 生产失败捕获器、单调阶段、获取预算、暂停与账本迁移 |

状态码矩阵采用 [IANA 登记表](https://www.iana.org/assignments/http-status-codes) 的 2025-09-15 快照（本次核对于 2026-11-12）：覆盖全部 59 个已登记的最终状态码（2xx–5xx），包括仅用于验证默认处理的 unused/obsolete 项；另有 499、599 与版本 feed 的 701 非标准输入。下载的 200/206 使用真实文件断言，其余最终状态通过合成响应验证拒绝；feed helper 的矩阵验证返回值及有界请求次数。

loopback 连接验证 100/102/103/104 中间响应后继续处理最终的 200 或 403。104 只验证解析，不验证上传恢复；101 协议升级不在此下载模拟范围。各码的通用矩阵不能代替每个厂商接口的业务约定验证。

## 隔离与解释范围

- URLProtocol 的 HTTPS URL 是合成地址，响应由严格的脚本提供，不经过 DNS、代理或 TLS 握手。脚本外的请求必须失败，不能默认补一个成功响应。
- 真实 socket 用例只监听 loopback，验证 Foundation 的 HTTP 重定向分派；这不验证真实互联网、TLS 证书链或厂商 CDN。
- 下载文件、续传片段、事件数据库与缓存使用临时目录。并行用例通过独立脚本身份隔离，不能共享一个可被另一用例消费的响应队列。
- 固定时间直接驱动生产调度与账本函数，避免等待真实 24 小时。生产安装 hook 使用计数器或临时目标验证边界，不操作已安装应用。
- Core 模型与 hook 的验证不等于整个 `AppListModel`、WebKit、Homebrew、MAS 或第三方更新器的端到端验证。
- 安装文件通过 HTTP 获取成功后仍需要后续格式、完整性、签名和身份校验。HTTP 仿真不会把 `200` 自动当作可安全安装。

## 策略评审的基准

1. 分开记录检查元数据、重复请求、恢复文件下载与重跑安装，避免把它们统称为一次重试。
2. 对无副作用的获取操作检查有限次数、取消和等待要求；对授权或安装副作用检查重复执行条件。
3. 保留所有校验与安全拒绝，不能通过绕过 HTTPS、凭据隔离或完整性检查让实验成功。
4. 将确证的代码行为、已复现的缺口和待决定的产品策略分别记录。

标准参考：[RFC 9110 的幂等请求与重试](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2)、[Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3)、[GitHub 限流处理](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately)。

## 测试设施阶段记录（生产修复前）

2026-11-12，Apple Silicon / macOS 27.3 / Swift 6.4.2：

- `scripts/test-http-simulation.sh`：退出码 0；`Test run with 59 tests in 4 suites passed`，参数化展开共 254 个案例。
- 新仿真与既有 GatewayRetry、VendorArchiveHTMLRetry、DownloaderTraffic、DownloaderCancellation、ResumableDownloadStore、RunningAppAutoUpdate、AutomaticInstall、RunningAppQuitBeforeApply、GitHubRateLimitGate/Wiring、GitHubTokenRejection、GitHubConditionalCache 测试合跑：退出码 0；`Test run with 188 tests in 16 suites passed`。
- 临时移除 `versionFeedData` 的 GET/HEAD 方法保护：对应新测试以 8 个断言失败抓到 POST/PUT/PATCH/DELETE 重发；恢复原实现。
- 临时移除 Downloader 的跨主机凭据剥离：对应新测试以 3 个断言失败抓到 Authorization/Cookie/Proxy-Authorization 保留；恢复原实现。
- 独立 review 发现原取消用例的假通过：临时移除取消桥后，原用例等到请求超时仍以 CancellationError 通过（本次观察为 61.041 秒）。补强为取消后放行正确尾段，再做相同变异，取消用例以“错误完成下载”和“出现最终文件”两个断言失败；同夹具正常下载的完整 49,152 字节对照通过。恢复生产实现后，全部仿真通过。这里没有以墙钟上界判断取消是否正确。
- 用假 `swift` 只提供一个 suite 验证运行入口：返回 1，明确报告缺失 suite，未进入测试执行步骤。
- 最终生产源码与基线一致。这一轮增加测试设施与证据，没有修改自动更新策略。

相关回归命令（实际运行时另以临时 `DUO_STATE_DIR` 隔离）：

```sh
swift test --package-path DuoUpdaterCore --skip-build \
  --filter '(HTTP.*SimulationTests|GatewayRetryTests|VendorArchiveHTMLRetryTests|DownloaderTrafficTests|DownloaderCancellationTests|ResumableDownloadStoreTests|RunningAppAutoUpdateTests|AutomaticInstallTests|RunningAppQuitBeforeApplyTests|GitHubRateLimitGateTests|GitHubRateLimitGateWiringTests|GitHubTokenRejectionTests|GitHubConditionalCacheTests)'
```

## 仿真发现的原行为（生产修复前）

| 实验 | 当前观察 | 解释 |
| --- | --- | --- |
| 新下载遇到 403/429/5xx | 一次请求即报错，错误页不成为最终文件 | 与版本 feed 的 gateway 重试不同 |
| 恢复旧片段时遇到 403/404/416/429/503 | 丢弃片段后再发一次从零请求 | 该回退不限于片段范围错误 |
| 429 要求等待 3000 秒 | redirect 解析停止在首个 HEAD | 保留可检测版本，未给出安装计划 |
| 429 要求等待 2 秒 | 仍准入下一步；配置的下一步暂停为 0.7 秒 | 验证请求顺序与配置，未作墙钟延迟合规断言 |
| 503 携带长 Retry-After | redirect 解析仍发 3 次 HEAD；feed helper 仍进行一次 gateway 重试 | 这些路径未按该 header 推迟到期时间 |
| Retry-After 为 HTTP-date | Vendor parser 返回 nil | 仅 parser 入口验证；不是完整日期调度仿真 |
| GitHub 429 关闭匿名预算 | 下一匿名请求在发出前被拒绝，token 预算仍可单独请求 | 固定 gate 时钟验证 120 秒截止时间 |
| 安装失败账本 | 5 分钟检查不解除 24 小时冷却；第 3 次失败后保持 gaveUp | 直接驱动账本；HTTP 错误到该账本的 App 映射未做整条仿真 |
| offered version 字符串变化 | 清失败次数/gaveUp，保留冷却截止时间 | `!=` 判断不等于版本大小比较 |
| 下载错误或摘要错误 | 不执行计划退出；目标文件保持旧内容 | 协调器注入终端 HTTP 错误、实际 Vendor 摘要验证入口 |
| 权限撤销、真正取消任务、应用拒绝退出 | 不进入临时目标交换 | 实际 permission/quit/commit hook；未退出真实应用 |
| 冷却到期且权限允许 | 可执行一次模拟退出和一次临时目录交换 | 到期只解除账本阻拦，不能推导真实 App 必然立即重试 |

完整 AppListModel 编排、真实设置持久化、真实应用退出/重开、安装后崩溃恢复、101 升级、真实 TLS 和厂商线上端点仍未由本环境验证。这里没有声称所有现有产品策略均正确。

## 测试设施阶段的独立 review（2026-11-12）

实现由三名 Sol xhigh 按下载、版本源、自动更新边界分工完成，再由独立上下文的 Astra medium 只读审查。

- 初轮实现 `643f5de2`：发现 1 个 P2，即取消桥被移除后测试仍可能靠请求超时得到 CancellationError 并假通过。通过实际变异复现，随后修复。
- 修复实现 `8ce3360dc5a0688ac80dbf02a3c9d480ee090b34`：Astra 复核两文件改动及原始日志，确认取消变异被抓到、正常完成对照通过、全部仿真与相关回归通过，blocking findings 归零。
- 审查员未自行运行构建或测试；执行与变异由主 agent 统一完成。审查范围仍受上面的仿真边界约束。

提交 PR 前，将本轮三个提交移到最新 `main`（`f9aff3dab`）之上，排除已 squash 合并的父分支历史。七个本轮文件的内容未变。Astra medium 对新实现 head `193ffdc5f2fd494d778e8ad793f04e8b2f8e8120` 再次复核：diff 仍仅含这七个文件，相关生产上下文的清理不改变结论，blocking findings 仍为 0。
