# Qoder CN IDE

审计 2026-09-22。

> ⚠️ 「Qoder」这个名字下有四个 macOS app，全表见 [com-qodercn-app.md](com-qodercn-app.md)。
> 这份是**国内版 IDE**：和 [Qoder IDE](com-qoder-ide.md)（`com.qoder.ide`）同源、同一版本同一个
> commit，但 bundle id、Team、更新服务器、说明页全部分开，不能合并成一个 recipe。

## 基本信息

- Bundle ID: `com.aliyun.lingma.ide`（改名前的产品叫 Lingma，bundle id 沿用至今）
- App 名: `Qoder CN IDE.app`（`CFBundleName` 是 `Qoder CN`，主程序 `Contents/MacOS/Qoder CN`）
- Team ID: `9DFNGU9AK5` — Developer ID Application: Hangzhou Yundian Technology Company Limited
  （与 Qoder CN 相同，与国际版 IDE 的 `T27K5A5ZWD` 不同）
- 观测版本: `1.31.1`、`1.31.2`（short == build），`LSMinimumSystemVersion` 12.0，arm64
- 底座: **VS Code fork**。`product.json`：`nameShort = QoderCN`、`version = 1.106.3`（上游 VS Code，
  **不是**产品版本）、`productVersion = 1.31.1`、`quality = stable`、
  `updateUrl = https://lingma-api.tongyi.aliyun.com/algo`，没有 `app-update.yml`，没有 `SUFeedURL`
- 分发: 官网 `qoder.cn/download`（= `qoder.com.cn/download`）给
  `qoder-ide-cn.oss-cn-hangzhou.aliyuncs.com/qoder/release/lastest/Qoder-CN-IDE-darwin-arm64.dmg`
  （`lastest` 是厂商自己的拼写）。页面 HTML 里不写这个地址，是点击后拿到的。
- Homebrew: 没查

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | — | 没查 | 没查 | — | ✓ |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.aliyun.lingma.ide` | 单一渠道 | — | — | ✓ |

`/api/qodercn/update/darwin-arm64/insider/latest` 是 404（2026-09-22）。

## 更新检测

- 源: `https://lingma-api.tongyi.aliyun.com/algo/api/qodercn/update/darwin-arm64/stable/latest?machineId=<本机 id>`
- 路径来自 app 自己的流量（用户抓包，2026-09-22）：
  `GET /algo/api/qodercn/update/darwin-arm64/stable/1.31.2?machineId=…&umid=…&os=27.0.0`，已是最新时回 204。
  和 VS Code 协议早期的形态有两处不同：多一段 `qodercn`，末段是**已装版本号**而不是 commit
  （国际版现在也发版本号，见 [Qoder IDE](com-qoder-ide.md)）。不带 `machineId` / `umid` / `os` 也照常回答，但见下面的灰度。
- 响应（节选）:
  ```json
  {"url":"https://ide.qoder.com.cn/qoder/release/lastest/QoderCN-darwin-arm64.zip",
   "name":"QoderCN","version":"fcfc0175…","productVersion":"1.31.2",
   "timestamp":1790004402000,"sha256hash":"e32e2218…"}
  ```
- 取 `productVersion`。`name` 是产品名，`version` 是 commit。
- `timestamp` 是毫秒，1.31.2 那条是 2026-09-21 15:26:42 UTC，与 `release/1.31.2/QoderCN-darwin-arm64.zip`
  的 `Last-Modified` 差一秒，当发布时间用（`publishedAtPattern`）。
- ⚠️ **不要用 VS Code 原路径** `/algo/api/update/darwin-arm64/stable/<commit>`：那是 Lingma 的旧表，
  不认识的 commit（包括 `latest`、全 0、国际版 1.31.2 的 commit）一律回答
  `Lingma 0.11.4`（`lingma-ide.oss-rg-china-mainland.aliyuncs.com/release/0.11.4/Lingma-darwin-arm64.zip`）。
- ⚠️ **按 `machineId` 灰度**，机制同 [Qoder IDE](com-qoder-ide.md)（那份写了 id 怎么来、为什么只读不算、
  读不到为什么不造）。不带 id 时每个请求重新随机分桶，同一请求连打 15 次：`latest` 是 9 次 1.31.2 / 6 次 1.31.1，
  `1.31.1` 是 7 次 1.31.2 / 8 次 204——这就是接入时看到的「逐请求抖动」。recipe 带
  `~/Library/Application Support/QoderCN/User/globalStorage/storage.json` 的 `telemetry.machineId`，
  拿到的就是 app 自己的更新器拿到的答案。`umid` 不参与分桶，不发。
- `/darwin/stable/latest`（不带架构）回答的是 x64 zip；`darwin-x64` 是 404。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 未知 | 无 | 不能 |
| 证据 | — | 响应只有一个整包 zip | — |

## Changelog

- 来源: recipe，`https://docs.qoder.cn/product-overview/qoder-cn-ide-update-log`（「Qoder CN IDE 更新日志」）
- 同一套 docs 构建，共用 `ChangelogRecipeRegistry.qoderEntryPattern`；版本是裸的 `1.31.0`，日期是中文。
- 说明页在发布之后才写，会落后：2026-09-22 最新一条是 `1.31.0`，而 1.31.1、1.31.2 都已发布。

## 一键安装

- 状态: **支持**（zip）
- 地址按解析出的版本拼：`https://ide.qoder.com.cn/qoder/release/{version}/QoderCN-darwin-arm64.zip`
  （`versionTemplate`）。
- ⚠️ **不用响应里的 `url`**：它是会移动的 `release/lastest/…` 别名。2026-09-22 响应已答 1.31.2 时，
  `ide.qoder.com.cn` 的 CDN 边缘仍把 `lastest` 当 1.31.1 下发（ETag `AEDC6FF4…`，280,960,669 字节，
  与 `release/1.31.1/` 相同）；源站 `qoder-ide-cn.oss-cn-hangzhou.aliyuncs.com` 的 `lastest`、以及加随机
  查询串绕过缓存的 CDN 请求，都已是 1.31.2（ETag `C9448E6C…`，282,186,278 字节，与 `release/1.31.2/` 相同）。
  照 `url` 下载会在 1.31.2 的标签下装上 1.31.1。
- 校验和: 响应给 sha256 hex；`checksumPattern` 要 base64 SHA-512，没接。
- 包验: 见「历史与实测」。没有跑 `--install` 实装。

## 已知问题

- 按设备灰度期间，DuoUpdater 与 IDE 自己同步，不会更早提示。手动装了更新版本的机器（如接入时的开发机：
  装着 1.31.2，本机 id 仍在 1.31.1 的桶）上 `duo verify` 会报 remote BEHIND，直到放量到这台机器。
- 没装或没打开过这个 IDE 的机器（包括扫描机）跳过这条 recipe。
- 说明页落后于发布。

## 如何复验

```bash
# 1. 不带 id 连打 10 次会在两版间跳；带一个固定 id 就不跳（id 随便造一个，只用于这个实验）
for i in $(seq 1 10); do curl -s https://lingma-api.tongyi.aliyun.com/algo/api/qodercn/update/darwin-arm64/stable/latest | grep -o '"productVersion":"[^"]*"'; done | sort | uniq -c
ID=$(openssl rand -hex 32); for i in $(seq 1 5); do curl -s "https://lingma-api.tongyi.aliyun.com/algo/api/qodercn/update/darwin-arm64/stable/latest?machineId=$ID" | grep -o '"productVersion":"[^"]*"'; done | sort | uniq -c

# 2. 版本化 zip 与 lastest 是否同一对象
curl -sI https://ide.qoder.com.cn/qoder/release/1.31.2/QoderCN-darwin-arm64.zip | grep -i etag

# 3. fixture
swift test --package-path DuoUpdaterCore --filter QoderRecipeTests
duo verify --only lingma
```

## 历史与实测

### 2026-09-22 接入时的测量

**dmg（1.31.1）。** `qoder-ide-cn.oss-cn-hangzhou.aliyuncs.com/qoder/release/lastest/Qoder-CN-IDE-darwin-arm64.dmg`，
276,629,207 字节，只读挂载：`Qoder CN IDE.app`，`com.aliyun.lingma.ide`，`1.31.1` / `1.31.1`，
`LSMinimumSystemVersion` 12.0，`lipo -archs` = `arm64`，`spctl` accepted（Notarized Developer ID，
Hangzhou Yundian Technology Company Limited (9DFNGU9AK5)）；`product.json` 的 `commit` 是
`345a1f8694551bfb9dc892ac08198b54c6a7a961`，与国际版 Qoder IDE 1.31.1 相同。同日 03:54 UTC `lastest`
换成 1.31.2（276,872,093 字节，ETag 与 `release/1.31.2/…dmg` 相同）。CN 安装器壳里的
`installer-manifest.json` 那时仍写着 `ideArtifact.version = 1.31.0`。

**zip（1.31.2）。** `ide.qoder.com.cn/qoder/release/1.31.2/QoderCN-darwin-arm64.zip`（282,186,278 字节）
用 HTTP Range 只读目录和两个条目：顶层只有 `Qoder CN IDE.app`；`Info.plist` 是 `com.aliyun.lingma.ide`，
`1.31.2` / `1.31.2`；主程序 `Contents/MacOS/Qoder CN` 的 `codesign -dv` 是
`Identifier=com.aliyun.lingma.ide`、`TeamIdentifier=9DFNGU9AK5`、Timestamp 2026-09-21。公证没有查（要整个 bundle）。

**端点。** 按版本号问 `/api/qodercn/update/darwin-arm64/stable/<v>`，每个 15 次：

```
1.31.1   7× 200 1.31.2 / 8× 204
1.31.0  10× 200 1.31.1 / 5× 200 1.31.2
1.30.1   8× 200 1.31.1 / 7× 200 1.31.2
0.0.0    5× 200 1.31.1 / 10× 200 1.31.2
latest   6× 200 1.31.1 / 9× 200 1.31.2
```

旧路径 `/api/update/darwin-arm64/stable/<x>`：`latest`、全 0、`fcfc0175…`（国际版 1.31.2）、
`c039f2d1…`（Lingma 0.11.4 自己）都答 `Lingma 0.11.4`；`345a1f86…`（1.31.1）和 `68cf4c38…`（国际版 1.28.0）是 204。

**changelog。** 44 个 `update-label`，共享 pattern 匹配 44 条（`1.31.0` → `0.3.0`），没有无 `<li>` 的条目；
`1.31.0` 8 条 item，`1.30.1` 5 条。

### 2026-09-22 按 `machineId` 灰度（同日稍后）

带固定的随机 `machineId`：20 个 id × 4 次，20/20 恒定（6 新 / 14 旧）；同一 `machineId` 配 4 个不同 `umid`
答案不变，只带 `umid` 仍然跳。空字符串等同不带；`0`、`a`、`test`、64 个 `0` 都固定在 1.31.1，64 个 `f`
固定在 1.31.2——任何非空值都会被分桶。app 的 `main.log` 里发出去的 `machineId` 与
`storage.json` 的 `telemetry.machineId` 相同。删掉这一项后重启 app，3 秒内写回同一个值（按 en0 MAC 重算，
en0 当前是私有地址，与硬件地址不同）。本机真实 id 问 `latest` 4 次都是 1.31.1、问 `1.31.1` 3 次都是 204。
