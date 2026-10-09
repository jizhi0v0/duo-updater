# 符号化：把用户的崩溃 / 卡死报告还原成函数和行号

从 0.5.2 之后的第一个版本起，发布出去的 `DuoUpdater` 主二进制是**剥离过符号的**
（#1097：`App/project.yml` 里 Release 配置的 `DEPLOYMENT_POSTPROCESSING: YES`）。
所以用户发来的报告里，DuoUpdater 自己的帧只有地址：

```
???  (in DuoUpdater)  load address 0x1029f4000 + 0x7ff23c
```

要定位问题，必须拿**同一次构建**的 dSYM 去解析。两者靠 UUID 配对。重新构建会得到
新的 UUID，所以丢了的 dSYM 补不回来。每个版本的 dSYM 由 `publish-release.sh` 作为
release 资产 `DuoUpdater-<版本>-dSYM.zip` 上传（#1101）。上传前，它会核对 dSYM 的
UUID 和 zip 里的二进制一致。

0.5.2 及更早的版本没有剥离：报告里本来就有函数名，但没有行号，release 上也没有 dSYM。
（2026-10-09 实测：把 0.5.2 二进制的 UUID 改掉、让本机缓存认不出来以后，atos 只给出
`BlenderBuildInfo.read(bundleAt:) + 48`，没有行号。二进制里只有指向构建机 `.o` 的调试
映射，没有行号表。）
对它们执行下面的 `gh release download`，会得到 `No assets match the file pattern`。

---

## 一、拿到报告

两种报告都能用，解析方法相同：都是「二进制的 UUID + 加载地址 + 偏移」。

- **崩溃**：用户机器上的 `~/Library/Logs/DiagnosticReports/DuoUpdater-<时间>.ips`。
  报告**可能过一分多钟才写出来**。2026-10-09 实测两次：一次进程 13:44:02 崩溃，
  报告 13:45:13 才出现，晚了 71 秒；另一次只晚了 2 秒。所以等半分钟没看到报告，
  不能断定「没生成」。
- **卡死 / 慢**：`sample <pid> 5 -file out.txt` 的输出，或者系统的 spindump 卡死报告。

## 二、读出版本、UUID 和要解析的地址

先把下面三个变量换成手上的值：

```bash
IPS=DuoUpdater-2026-10-09-141424.ips   # 报告文件
REPO=jizhi0v0/duo-updater
WORK=$(mktemp -d)
```

`.ips` 的第一行是 JSON 头，后面是 JSON 正文。这段脚本打印版本、UUID、加载地址，
并把 DuoUpdater 自己的每一帧写成「线程号 绝对地址」：

```bash
python3 -I - "$IPS" > "$WORK/frames.txt" <<'EOF'
import json, sys
head, body = open(sys.argv[1]).read().split('\n', 1)
h, b = json.loads(head), json.loads(body)
i = next(n for n, m in enumerate(b['usedImages']) if m.get('name') == 'DuoUpdater')
img = b['usedImages'][i]
print(f"# version {h['app_version']} ({h['build_version']})  uuid {img['uuid']}  base {img['base']:#x}",
      file=sys.stderr)
for t, thread in enumerate(b['threads']):
    for f in thread['frames']:
        if f['imageIndex'] == i:
            print(t, hex(img['base'] + f['imageOffset']))
EOF
BASE=$(python3 -I -c 'import json,sys; b=json.loads(open(sys.argv[1]).read().split("\n",1)[1]); print(hex(next(m["base"] for m in b["usedImages"] if m.get("name")=="DuoUpdater")))' "$IPS")
VER=$(head -1 "$IPS" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["app_version"])')
```

`sample` 或 spindump 的文本报告里，每帧已经写成 `load address <基址> + <偏移>`。直接取
偏移，第四节用 `--offset` 解析即可：

```bash
grep -oE '\(in DuoUpdater\)  load address 0x[0-9a-f]+ \+ 0x[0-9a-f]+' out.txt | awk '{print $NF}' | sort -u > "$WORK/offsets.txt"
```

## 三、取 dSYM，核对 UUID

正式版本从 release 上下载：

```bash
gh release download "v$VER" -R "$REPO" -p "DuoUpdater-$VER-dSYM.zip" -D "$WORK"
```

还没发布的 CI 构建，dSYM 在 release-build 那次 run 的 artifact 里，保留 90 天：

```bash
gh run download <run-id> -R "$REPO" --name DuoUpdater-dSYM --dir "$WORK"
```

解压后核对 UUID。它**必须**和第二节打印的 UUID 相同（大小写不同不要紧）。atos 自己
不检查 UUID：2026-10-09 实测，拿今天 CI 构建的 dSYM 去解析 0.5.2 的地址，3 个地址里
2 个被解析成别的函数（`CapCutChannel.resolveCurrent` 变成了
`assignWithTake for AppcastHTMLChangelogParser.Piece`），1 个函数名碰巧对上但行号是 0。
三次都是 exit 0，没有任何警告。

```bash
ditto -x -k "$WORK"/DuoUpdater-*dSYM.zip "$WORK/dsym"
DSYM="$WORK/dsym/DuoUpdater.app.dSYM"
dwarfdump --uuid "$DSYM"
```

## 四、解析

`.ips` 报告（绝对地址 + 基址）：

```bash
awk '{print $2}' "$WORK/frames.txt" | xargs atos -o "$DSYM" -arch arm64 -l "$BASE" -i
```

`sample` / spindump 报告（偏移）：

```bash
xargs atos -o "$DSYM" -arch arm64 -i --offset < "$WORK/offsets.txt"
```

`-i` 会把被内联的函数也逐层展开，最内层排在最前。输出形如：

```
static CapCutChannel.resolveCurrent() (in DuoUpdater) (CapCutChannel.swift:113)
```

zsh 下不要写 `atos … $ADDRS`：zsh 不会按空格拆分变量，所有地址会被当成一个参数。
上面用 `xargs` 就是为了避开这个问题。

## 五、怎么读结果

2026-10-09 在 CI 构建（`3a556e39`，run 37891815215）上做过一次完整核对：运行这份构建，
让它真实崩溃一次，再在启动扫描期间采样，把解析出的每个行号拿回 `3a556e39` 的源码
逐条比对。**带行号、落在本仓库代码里的 494 帧，没有一条对不上源码**。但有几种情况
要会读：

| 现象 | 含义 | 怎么办 |
|---|---|---|
| `foo() (Bar.swift:123)` | 函数和行号都准 | 直接看 |
| 函数名是外层函数，行号却在它调用的另一个函数里（例：`GitHubReleasesSource.latestVersion` 却指向 `resolve()` 里的第 1398 行） | 被调用的 async 函数被内联了，调试信息里没留下内联帧 | **以行号为准**，函数名只说明是从哪里调进来的 |
| 行号上方紧挨着一个别的 `func` | 那是嵌套的局部函数，或者这一行是 `defer`，或者是属性默认值（在 `init` 里执行） | 往外看大括号范围，行号是对的 |
| `(… .swift:0)` / `<compiler-generated>:0` | 编译器生成的 thunk 或协议见证 | 看上下相邻的帧 |
| `<deduplicated_symbol>` | 链接器把内容完全相同的函数合并成了一份，有没有 dSYM 都看不出是哪个 | 用 `atos --dedup`（**不要同时加 `-i`**，加了就不展开）列出候选，再结合相邻帧判断。实测一个地址展开出 8 个以上候选 |
| `foo + 24`，没有行号 | 多半是标准库的泛型特化，或者合成代码（如 Codable 的 `init(from:)`） | 看调用它的那一帧 |

**本机缓存会掩盖问题。** 系统的 `coresymbolicationd` 会按 UUID 缓存符号化结果。2026-10-09，
在这台机器上把构建机的 `.o` 移走后，0.5.2 的地址照样解析出了行号；只有改掉二进制的 UUID，
才不再出现行号。这份缓存最初从哪读到的行号没有查明。所以要判断「别人的机器上能看到什么」，
不能拿本机的 atos 结果当证据。

那次采样一共 1022 个地址：494 帧带本仓库代码的行号，403 帧没有行号（主要是上表最后
两行的情况），46 帧行号为 0，20 帧来自第三方包。这是一次性测量，不是持续跟踪的指标。
