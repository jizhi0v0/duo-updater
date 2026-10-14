"""Read-only progress view over the benchmark run directories."""
import json, os, sys, time, glob

B = os.path.join(os.environ.get("BENCH_ROOT") or os.path.expanduser("~/duo-updater-bench"), "runs")
for d in sorted(glob.glob(B + "/*")):
    name = os.path.basename(d)
    try:
        t0 = int(open(d + "/t0").read())
    except Exception:
        t0 = None
    t1 = None
    if os.path.exists(d + "/t1"):
        t1 = int(open(d + "/t1").read())
    status = open(d + "/status").read().strip() if os.path.exists(d + "/status") else "running"
    last, n, result = None, 0, None
    tp = d + "/transcript.jsonl"
    if os.path.exists(tp):
        for line in open(tp):
            n += 1
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") == "assistant":
                for b in ev["message"]["content"]:
                    if b.get("type") == "tool_use":
                        last = "tool " + str(b["input"])[:140]
                    elif b.get("type") == "text":
                        last = "text " + b["text"][:140]
            elif ev.get("type") == "result":
                result = ev
    mins = ((t1 or int(time.time())) - t0) // 60 if t0 else "?"
    extra = ""
    if result:
        extra = " cost=$%.2f turns=%s" % (result.get("total_cost_usd") or 0, result.get("num_turns"))
    print("== %-18s %3s min  events=%-4d %s%s" % (name, mins, n, status, extra))
    if not result:
        print("     ", (last or "").replace("\n", " "))
