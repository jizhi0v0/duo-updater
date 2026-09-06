# Qoder（桌面 app，非 IDE）

> ⚠️ 先读这段：**「Qoder」是两个 app。** 这份写的是官网叫 "the all-new Qoder" 的那个
> 独立桌面 app（`com.qoder.app`）；写代码的那个是 `com-qoder-ide.md`
> （`com.qoder.ide`）。官方论坛（forum.qoder.com/t/qdoer-qoder-qoder-ide/12088，
> 2026-09-06 读）原话："Qoder IDE 用来代码，Qoder 是国际版 QoderWork 的迭代，CN 版的
> QoderWork 整合进 QwenWork"。**不是合并，是并存。**

## 基本信息
- Bundle ID: `com.qoder.app`
- Team ID: `B6U242QL73`（Developer ID Application: BRIGHT ZENITH PRIVATE LIMITED）
  —— **和 IDE 的 `T27K5A5ZWD` 不是一个**
- 观测版本: `0.1.8`（short == build；被换掉的旧版是 `0.1.6`）
- 架构: arm64-only
- `LSMinimumSystemVersion`: 12.0
- 分发: 官网 `qoder.com/download` → `download.qoder.com/qoder-app/releases/`
- Homebrew: 无 cask

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (无 cask) | — | — | ✓ |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.qoder.app` | 单一渠道 | — | — | ✓ |

## 更新检测
- 源: `https://download.qoder.com/qoder-app/releases/latest/manifest.json`
  —— 1,365 字节，厂商发给自己的安装器读的清单。**无条件**（不像 IDE 那条）。
  ```json
  { "schemaVersion": 1, "version": "0.1.8",
    "artifacts": [ { "id": "mac-arm64",
                     "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip",
                     "sha256": "8f71bf38…" }, … ] }
  ```
- `versionPattern` 取顶层 `"version"`。**不会被 `"schemaVersion"` 满足**：key 连着自己的
  左引号一起匹配，而且 `schemaVersion` 的值是**不带引号的整数**——两个独立理由，任一足够。
- 版本方案: manifest 的 `version` == 包的 short == build，同构。

### 其他被否掉的版本面（记下来省得再查）
- `Qoder-Installer-mac-arm64.zip` 的 **HTTP 响应头**里直接带
  `x-oss-meta-version: 0.1.8` 和 `x-oss-meta-source-object: …/0.1.8/…`——很干净，但
  `VendorProbeRecipe.Mode` 没有"读响应头"这一档，**没用**。
- `qoder.com/changelog?type=app`：同 IDE 那份的理由，RSC payload，不用。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 未知 | 无 | 不能 |
| 证据 | — | manifest 每个平台只有一个整包条目（2026-09-06） | — |

## Changelog
- 来源: **`https://docs.qoder.com/release-notes/qoder`**（页面标题
  "Qoder Release Notes"），与 IDE 那页同一套 docs 构建，**共用同一个 entry pattern**
  （`ChangelogRecipeRegistry.qoderEntryPattern`）。
- 唯一差别：这页的版本串写成 `Qoder 0.1.8`，IDE 那页是裸的 `1.28.0`。共享 pattern 把
  `Qoder ` 前缀做成可选，而不是把 recipe 拆成两份——两页出自一次构建，只修一边会让两个
  产品悄悄不一致。
- 实测（2026-09-06）: **7 条**（`0.1.8` → `0.1.0`），`0.1.8` 有 8 个 items
  （1 Features + 3 Improvements + 4 Fixes，三个 `<h4>` 下的三个 `<ul>`）。

## 一键安装
- 状态: **支持**
- 格式: zip —— `Qoder-mac-arm64.zip`（238,177,792 bytes）
- ⚠️ **不装下载页给人的那个包。** 下载页给的是
  `Qoder-Installer-mac-arm64.zip`：一个 238 MB 的**安装器壳**，自己的 bundle id 是
  `com.qoder.installer`，真 app 在它的
  `Contents/Resources/payload/Qoder-<version>-mac-arm64.zip` 里——正是
  `nestedArchivePath`（豆包输入法那条）存在的形状。这里**不需要**它：同一个 release
  另有一份不套壳的 `Qoder-mac-arm64.zip`，manifest 指的就是它。何况那个 payload 路径
  **带版本号**，本来也没法写成固定的 `nestedArchivePath`。
- ⚠️ **主机分裂，刻意跟随而不改写**: manifest 由 `download.qoder.com` 提供，里面的
  artifact URL 指向 `download.qoder.com.cn`。两个都是阿里云 OSS，HEAD 回同一个对象、
  字节数一致（2026-09-06），而且厂商自己的安装器下的就是 `.cn` 那个。所以 install
  pattern **两个主机都接**，而不是钉死我们碰巧取 manifest 的那个。
- 校验和: manifest 给 sha256 hex；`checksumPattern` 要 base64 SHA-512，**没接**。
- 包验（2026-09-06，真实下载解包）: `Qoder.app` / `com.qoder.app` /
  short == build == `0.1.8` == manifest 的 `version` / arm64 /
  `Developer ID Application: BRIGHT ZENITH PRIVATE LIMITED (B6U242QL73)` /
  notarized——与本机装的 0.1.6 同 Team，swap 过闸。
- 两个 Team 分开这件事是**厂商自己声明的**，不是某一次构建的巧合：安装器壳的
  `installer-manifest.json` 里并列着 `expectedIdeTeamIdentifier: "T27K5A5ZWD"` 和
  `expectedQoderTeamIdentifier: "B6U242QL73"`。

## 已知问题
- 版本线还很早（0.1.x），厂商发布节奏密（0.1.0→0.1.8 用了不到两周），路径约定改动的
  风险高于成熟产品。失效表现为 unknown，不会误报。
- manifest 里 `mac-x64` 是同场兄弟，install pattern 锚死 `mac-arm64`；同一数组里还有
  `.exe`/.deb/.rpm，测试里拿 `win-x64-user` 当反例。

## 如何复验
```
# GET https://download.qoder.com/qoder-app/releases/latest/manifest.json → "version": "0.1.8"
# 解包它指的 Qoder-mac-arm64.zip → Qoder.app / com.qoder.app / B6U242QL73 / notarized
duo verify --only qoder.app
```

## 建议下一步
- 无。
