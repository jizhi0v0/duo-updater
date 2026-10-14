"""pipe-merge.py <run dir>: concatenate stage transcripts into transcript.jsonl (for score.py's
command/violation audit) with one synthetic result event summing cost and turns, and write
costs.json: per stage, per model cost; models seen per layer (main vs subagent)."""
import json, sys, os
R = sys.argv[1]
stages = [s for s in ("plan", "exec", "review", "fix") if os.path.exists(f"{R}/{s}.jsonl")]
out = open(f"{R}/transcript.jsonl", "w")
tot_cost = tot_turns = 0; costs = {}
for s in stages:
    res = None; layers = {"main": set(), "subagent": set()}; spawned = 0
    for line in open(f"{R}/{s}.jsonl"):
        if not line.startswith("{"): continue
        e = json.loads(line)
        if e.get("type") == "result":
            res = e; continue
        out.write(line if line.endswith("\n") else line + "\n")
        m = e.get("message")
        if e.get("type") == "assistant" and isinstance(m, dict) and m.get("model"):
            layers["subagent" if e.get("parent_tool_use_id") else "main"].add(m["model"])
    res = res or {}
    tot_cost += res.get("total_cost_usd") or 0; tot_turns += res.get("num_turns") or 0
    st = res.get("subagent_stats") or {}
    costs[s] = dict(total=round(res.get("total_cost_usd") or 0, 3), turns=res.get("num_turns"),
                    subtype=res.get("subtype"),
                    by_model={k: round(v.get("costUSD", 0), 3) for k, v in (res.get("modelUsage") or {}).items()},
                    models_seen={k: sorted(v) for k, v in layers.items()},
                    subagents_spawned=st.get("spawned"), subagents_completed=st.get("completed"),
                    minutes=round((int(open(f"{R}/{s}.t1").read()) - int(open(f"{R}/{s}.t0").read())) / 60, 1))
out.write(json.dumps(dict(type="result", subtype="success", total_cost_usd=tot_cost, num_turns=tot_turns,
                          usage={}, synthetic=True)) + "\n")
json.dump(costs, open(f"{R}/costs.json", "w"), indent=1)
print(json.dumps(costs, indent=1))
