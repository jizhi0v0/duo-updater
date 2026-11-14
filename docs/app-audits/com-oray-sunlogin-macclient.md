# AweSun（向日葵，Oray）

**这不是审计**：family `com-oray-sunlogin-macclient`（`Recipes/com-oray-sunlogin-macclient.swift`）里 AweSun `com.oray.sunlogin.macclient` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-oray-sunlogin-macclient.swift — ChangelogRecipe（`.sunLoginSoftwareLogs`）

转引自 recipe 注释，未复测。整段原文；代码里只留下「与 VendorProbeRecipe 用同一个 JSON 接口，形状见 `sunLoginSoftwareLogs` 的文档注释」。

AweSun (Oray) — same JSON API as the VendorProbeRecipe (verified live
2026-08-21: GET returns 200/~15KB; the earlier "50 bytes" observation
that prompted a re-check did not reproduce and the endpoint/logic are
both healthy — see `sunLoginSoftwareLogs`'s doc comment for the shape).

## PKG helper 专项验证（2026-11-14，非完整审计）

国内版 16.6.0（32198）在 VM 中通过实验 helper 安装；16.5.0（30905）启动后
资源签名失效，被 helper 拒绝。更关键的是，官方海外版和国内版 16.6 使用相同
Bundle ID、Team `ZBNMDRTU32`、版本和安装位置，海外版完整签名也有效。两版
preinstall 的 `CURRENT_OVERSEAS` 不同；跨区分支会在有控制台用户时删除该用户的
AweSun 配置目录，没有备份。未执行删除测试。

因此**本轮不加入 helper 白名单**，保留系统 Installer。当前 recipe 的国内端点
不能证明海外副本的正确路由；需先解决地域版本识别。两端当前同版本，不代表
已观察到今天实际向海外版提供跨区更新。

[凭据与限制](../../verify/pkg-helper-coverage-20261114/README.md)。
