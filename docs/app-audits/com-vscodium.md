# VSCodium

**这不是审计**：family `com-vscodium`（`Recipes/com-vscodium.swift`）里 stable
`com.vscodium` 的覆盖情况没有审过。同一个 family 的另一个 app——VSCodium Insiders
`com.vscodium.VSCodiumInsiders`——审过，见 [com-vscodium-VSCodiumInsiders.md](com-vscodium-VSCodiumInsiders.md)。

这份文件存在，是因为 recipe 注释里迁出的历史按 family 落地：`Recipes/com-vscodium.swift`
的历史回链必须指向 `docs/app-audits/com-vscodium.md`（`scripts/check_app_audits.py` 按 family
文件名检查），两个 app 的历史都进这里。
