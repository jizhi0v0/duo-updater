"""Print tool calls (and their results) whose command matches a regex.

usage: grep_tx.py <transcript.jsonl> <regex> [max_result_chars]
"""
import json, re, sys

path, pat = sys.argv[1], re.compile(sys.argv[2])
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 600
pending = {}
for line in open(path):
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") == "assistant":
        for b in ev["message"]["content"]:
            if b.get("type") == "tool_use":
                cmd = b["input"].get("command") or ""
                if pat.search(cmd):
                    pending[b["id"]] = cmd
    elif ev.get("type") == "user":
        content = ev["message"].get("content")
        if not isinstance(content, list):
            continue
        for b in content:
            if b.get("type") == "tool_result" and b.get("tool_use_id") in pending:
                out = b.get("content")
                if isinstance(out, list):
                    out = " ".join(x.get("text", "") for x in out if isinstance(x, dict))
                print("$", pending.pop(b["tool_use_id"])[:700])
                print("→", str(out)[:limit].replace("\n", "\n  "))
                print("-" * 60)
