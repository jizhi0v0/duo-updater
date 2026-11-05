#!/usr/bin/env python3
"""Route pure scan-state changes to data validation without running PR code."""
import argparse
import datetime
import json
import os
import re
import subprocess

from check_codex_review import api, is_nightly_state, nightly_files

STATE_FILES = {"verify/baseline.json", "verify/identities.json", "verify/install-baseline.json"}
SHA = re.compile(r"[0-9a-f]{40}")
COUNTERS = {"consecutiveActionable", "consecutiveInfra", "consecutiveInstallTransient", "sweepsSinceComment"}
BASE_DATES = {"lastGoodAt", "infraSince", "closedAt", "installTransientSince", "lastCommentedAt"}
BASE_STRINGS = {"lastGoodVersion", "lastSignature", "previousSignature", "triagedSignature"}
IDENTITY = {"bundleIdentifier", "signedIdentifier", "teamIdentifier", "packageTeamIdentifier", "sparklePublicKey"}
IDENTITY_STRINGS = IDENTITY | {"firstSeenVersion", "lastSeenVersion", "lastSeenURLSHA256"}


def plan(repo, event_name, event, head):
    if not SHA.fullmatch(head) or event.get("repository", {}).get("full_name") != repo:
        return None
    if event_name == "pull_request":
        if (event.get("pull_request", {}).get("head", {}).get("sha") != head
                or type(event.get("number")) is not int):
            return None
        pr = api(f"repos/{repo}/pulls/{event['number']}")
        if pr.get("head", {}).get("sha") != head or not nightly_files(pr, repo):
            return None
        base = pr.get("base", {}).get("sha", "")
    elif event_name == "push":
        default = event["repository"].get("default_branch")
        if (not default or event.get("ref") != f"refs/heads/{default}"
                or event.get("after") != head):
            return None
        base = event.get("before", "")
        # A protected-main push qualifies only through the actual merged scan
        # PR. Manual identity corrections on ordinary branches keep full CI.
        candidates = api(f"repos/{repo}/commits/{head}/pulls")
        pr = next((p for p in candidates
                   if p.get("merged_at") and p.get("merge_commit_sha") == head
                   and p.get("base", {}).get("ref") == default and nightly_files(p, repo)), None)
        if pr is None:
            return None
        pr = api(f"repos/{repo}/pulls/{pr['number']}")
        if not pr.get("merged") or pr.get("merge_commit_sha") != head:
            return None
    else:
        return None
    if not isinstance(base, str) or not SHA.fullmatch(base) or base == "0" * 40:
        return None
    comparison = api(f"repos/{repo}/compare/{base}...{head}")
    merge_base = comparison.get("merge_base_commit", {}).get("sha", "")
    if not isinstance(merge_base, str) or not SHA.fullmatch(merge_base):
        return None
    if event_name == "push" and merge_base != base:
        return None
    files = comparison.get("files", [])
    if not is_nightly_state(pr, repo, files):
        return None
    # A PR is judged against its merge base, not unrelated updates that landed
    # on main since it branched. A main push is checked against its before SHA.
    return {"base": merge_base, "head": head, "files": [f["filename"] for f in files]}


def unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("duplicate JSON key")
        out[key] = value
    return out


def invalid_constant(value):
    raise ValueError("non-finite JSON number")


def decode(raw):
    return json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object,
                      parse_constant=invalid_constant)


def date(value):
    if not isinstance(value, str):
        raise ValueError("timestamp must be a string")
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")


def integer(value, minimum=0):
    if type(value) is not int or not minimum <= value <= 2**63 - 1:
        raise ValueError("invalid integer")


def validate_document(path, doc, previous):
    if path not in STATE_FILES or not isinstance(doc, dict):
        raise ValueError("invalid state document")
    if type(doc.get("schemaVersion")) is not int or doc["schemaVersion"] != 1:
        raise ValueError("unsupported state schema")
    entries = doc.get("entries")
    if not isinstance(entries, dict):
        raise ValueError("entries must be an object")
    old = previous.get("entries", {})
    if old and not entries:
        raise ValueError("scan state unexpectedly emptied")
    identity = path == "verify/identities.json"
    root = {"schemaVersion", "entries", "lastFullPassAt" if identity else "updatedAt"}
    if doc.keys() - root:
        raise ValueError("unknown state fields")
    stamp = "lastFullPassAt" if identity else "updatedAt"
    if not identity or doc.get(stamp) is not None:
        current_date = date(doc.get(stamp))
        if previous.get(stamp) is not None and current_date < date(previous[stamp]):
            raise ValueError("state timestamp moved backwards")
    elif previous.get(stamp) is not None:
        raise ValueError("full-pass timestamp was lost")
    for key, entry in entries.items():
        if not key or not isinstance(entry, dict):
            raise ValueError("invalid state entry")
        if identity:
            allowed = IDENTITY_STRINGS | {"architectures", "firstSeenAt", "lastSeenAt"}
            if entry.keys() - allowed:
                raise ValueError("unknown identity fields (raw URLs must not be committed)")
            architectures = entry.get("architectures")
            if not isinstance(architectures, list) or any(not isinstance(a, str) for a in architectures):
                raise ValueError("invalid architectures")
            if date(entry.get("lastSeenAt")) < date(entry.get("firstSeenAt")):
                raise ValueError("identity seen before its first observation")
            for field in IDENTITY_STRINGS:
                if entry.get(field) is not None and not isinstance(entry[field], str):
                    raise ValueError("invalid identity string")
            digest = entry.get("lastSeenURLSHA256")
            if digest is not None and not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("invalid URL digest")
            if key in old:
                for field in IDENTITY | {"firstSeenAt", "firstSeenVersion"}:
                    if entry.get(field) != old[key].get(field):
                        raise ValueError("existing installer identity/provenance changed")
                if not set(old[key]["architectures"]).issubset(architectures):
                    raise ValueError("existing identity lost an architecture")
                if date(entry["lastSeenAt"]) < date(old[key]["lastSeenAt"]):
                    raise ValueError("identity timestamp moved backwards")
        else:
            if entry.keys() - (COUNTERS | BASE_DATES | BASE_STRINGS | {"lastGoodEntryCount", "issueNumber"}):
                raise ValueError("unknown baseline fields")
            for field in COUNTERS:
                integer(entry.get(field))
            for field in {"lastGoodEntryCount", "issueNumber"}:
                if entry.get(field) is not None:
                    integer(entry[field], 1 if field == "issueNumber" else 0)
            for field in BASE_DATES:
                if entry.get(field) is not None:
                    date(entry[field])
            for field in BASE_STRINGS:
                if entry.get(field) is not None and not isinstance(entry[field], str):
                    raise ValueError("invalid baseline string")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def read_document(sha, path):
    # Raw blobs do not apply attributes/filters or follow a symlink in PR data.
    tree = git("ls-tree", sha, "--", path).decode().split()
    if len(tree) != 4 or tree[0:2] != ["100644", "blob"] or tree[3] != path:
        raise ValueError("state must be a regular non-executable file")
    return decode(git("cat-file", "blob", f"{sha}:{path}"))


def validate(change):
    for sha in {change["base"], change["head"]}:
        git("fetch", "--no-tags", "--depth=1", "origin", sha)
    for path in change["files"]:
        validate_document(path, read_document(change["head"], path), read_document(change["base"], path))
        print(f"Validated {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as handle:
        event = json.load(handle)
    change = plan(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_EVENT_NAME"],
                  event, os.environ["NIGHTLY_HEAD_SHA"])
    if args.validate:
        if change is None:
            raise ValueError("run no longer qualifies for data-only CI")
        validate(change)
    else:
        print(f"nightly_only={'true' if change else 'false'}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        # Never include raw state or command output: vendor input can contain secrets.
        raise SystemExit("Nightly data check failed; inspect schema, identity and pinned-diff constraints.")
