# 自定义 GitHub 来源 V2 验收

事务与授权代码基线为 `b28db09c`，工作台视觉反馈修订为 `e52ddda0`。

## 样本和操作范围

- 物理机为 Apple Silicon Mac，macOS 27.3。正向样本使用 `jizhi0v0/duo-shot` 的正式 `v0.1` 和 `DuoShot.zip`。旧版是独立临时副本，营销版本改为 `0.0.9`，build 为 `1`，使用原 Developer ID 团队重新签名。候选是厂商发布的已公证原包，build 为 `202610092055`。
- 私库访问使用本机已获准访问 `jizhi0v0/duo-terminal` 的 gh 登录。生产客户端读取了该私库现有的 `v0.1.0`，按资产 ID 下载了 67,173,099 字节的 `DuoTerminal-0.1.0.zip`，通过 GitHub SHA-256 核对并解包，读回 `com.bobby.DuoTerminal` 0.1.0。本次安装样本来自 DuoShot 的公开仓库。
- 独立视觉验收使用 Apple Silicon macOS 27.2 VM 和 Developer ID 签名的 Release。QA 使用独立 Bundle ID、钥匙串服务、状态目录和安装目标。宿主 Mac 的日常安装副本不参与替换。

## 数据和磁盘行为

App 回归执行 397/397 项。Core 的个人来源和事务测试执行 14 项声明用例，其中事务用例包括 8 组文件状态。另在物理机通过 Release 配置下的真实 GitHub 流程复核授权代次、取消、替换和回读。

| 操作或故障 | 观测结果 |
|---|---|
| Release 配置下调用实际来源模型 | 真实下载并验证 ZIP，首次授权、撤销、再次授权后，用户操作可以替换临时副本，原路径回读 0.1。更新完成后未启动目标 App。 |
| 实机已有外部特权服务 | KeyRemap 的两个厂商签名包身份匹配，但机器上安装了关联的 LaunchDaemon，直接替换检查拒绝放行。 |
| 用户提交后，在准备任务开始前撤销并再次授权，或直接取消 | 旧任务均保留原件。再次授权具有独立的授权 ID，需重新点击更新。 |
| 小容量 HFS+ 镜像只剩约 2.8 MiB | 准备阶段实际遇到空间不足，安装路径和原件身份保持一致，没有已提交事务。 |
| 备份缺失、目标目录不可写、外部更新先换了目标 | 校验或写入失败，现存安装未被覆盖。 |
| 回放持久化记录，分别设置为尚未移动、原件移走、已装新版 | 恢复流程分别确认原件、恢复原件、确认新版，核验卷号、inode、签名、版本、build 和内容清单。 |
| 原件移走后内容损坏，仍可识别其 inode | 独占恢复经验证的备份，重新从原路径读取备份身份。 |
| 中断后在目标路径另外装入内容相同、inode 不同的 App | 恢复返回需要人工检查，外来副本保留。 |

磁盘中断测试在隔离目录中重建进程中止后会留下的文件状态，然后重新从磁盘加载事务。没有对物理机断电。测试入口见 [PersonalSourceReplacementTests](../../DuoUpdaterCore/Tests/DuoUpdaterCoreTests/PersonalSourceReplacementTests.swift)。默认使用 Xcode 附带的签名样本，真实厂商样本可通过 `DUO_TEST_PERSONAL_OLD` 和 `DUO_TEST_PERSONAL_NEW` 指定。磁盘满用例仅在指定准备好的 `DUO_TEST_PERSONAL_TIGHT_VOLUME` 时运行。

## 独立视觉验收

首次体验中，VM 的匿名 GitHub 配额耗尽。重置后同一个编辑器成功预览、保存 Stable 来源并下载验包。验包后可以在 Finder 查看文件，也可以打开发布页。首次授权对话框展示仓库、发布线和副本路径。撤销后带版本号的蓝色按钮消失，手动菜单保留。再次授权并点击更新后，侧栏和详情均显示 0.1。测试员在原路径复核了 build、签名和公证，并确认目标未启动。

测试员反馈首次授权藏在来源管理菜单里，授权后又出现两个形状相近的省略号。调整后的工作台在验包结果下直接显示「启用一键更新」，并用文字标明蓝色按钮旁的手动更新菜单。

视觉 agent 在最终签名 Release `e52ddda0` 上以干净副本复验。验包后可直接点击授权链接，撤权后链接重新出现。再次授权后，「Manual Updates」中有 Finder、发布页和当前安装位置三个入口。点击蓝色按钮后，侧栏和详情都显示 0.1；原路径 build 为 202610092055，`codesign --verify --deep --strict` 和 `spctl --assess` 均通过，目标进程没有启动。

[GitHub 发布预览](public-preview.png) · [验包后的授权入口](verified-enable.png) · [按副本授权](grant.png) · [更新与手动选项](authorized-manual.png) · [更新后回读](confirmed.png)
