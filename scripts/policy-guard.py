#!/usr/bin/python3
"""policy-guard: may this pull request merge without the owner's approval?

The `policy-guard` required check. It enforces, independently of
.github/renovate.json5, which pull requests may merge without a human:

- PRs opened by an approver (the repository owner by default) pass.
- PRs opened by Renovate pass when they only bump a pinned version or
  digest, patch level at most, in the files Renovate maintains (ALLOWED).
- Everything else needs an approver's approval of the PR's head commit.

It reads the PR through the GitHub API only and never checks out or runs
the PR's code, so it can run with pull_request_target.

Env: GH_TOKEN, REPO (owner/name), PR (number),
     APPROVERS (comma-separated logins; default: the repository owner)
"""

import json
import os
import re
import sys
import urllib.request

RENOVATE = "renovate[bot]"

# Files Renovate may change without review (globs; ** crosses directories).
ALLOWED = [
    "images/base/upstream.env",
    "**/*.container",
    "scripts/lib.sh",
    "flake.lock",
]
# Always need an approval, whoever opens the PR and whatever ALLOWED says.
PROTECTED = [
    ".github/**",
    "keys/**",
    "security/**",
    "lib/factory/**",
    "**/cis-exceptions.txt",
    "factory.yaml",
]
# Lines whose change always needs an approval: images that run inside the
# gates (a compromised one could make a gate lie). Matches .github/renovate.json5.
REVIEW_ONLY = re.compile(r"^(TRIVY_IMAGE|IMAGE_BUILDER_IMAGE)=")

# Changed lines Renovate may produce. A removed/added line pair passes when
# both match the same shape and differ only in the named "ver"/"pin" parts.
SHAPES = [
    # An image pinned by tag and digest: Image=..., FOO_IMAGE=..., KEY=...
    re.compile(
        r"^(?P<pre>.*?[=\s])(?P<name>[a-z0-9][a-z0-9./_-]*):(?P<ver>[\w.+-]+)"
        r"@(?P<pin>sha256:[0-9a-f]{64})(?P<post>\s*)$"
    ),
    # A `# renovate:` annotated tool version: ACTIONLINT_VERSION=v1.7.12
    re.compile(r"^(?P<pre>[A-Z][A-Z0-9_]*_VERSION=)(?P<ver>v?\d+\.\d+\.\d+)(?P<post>\s*)$"),
    # flake.lock input pins
    re.compile(r'^(?P<pre>\s*"rev": ")(?P<pin>[0-9a-f]{40})(?P<post>",?)$'),
    re.compile(r'^(?P<pre>\s*"narHash": ")(?P<pin>sha256-[A-Za-z0-9+/]{43}=)(?P<post>",?)$'),
    re.compile(r'^(?P<pre>\s*"lastModified": )(?P<pin>\d+)(?P<post>,?)$'),
]
SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def glob_match(pattern, path):
    """Match a path against a glob where * stays in one directory, ** doesn't."""
    rx = re.escape(pattern).replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*")
    rx = rx.replace(r"\*", "[^/]*")
    return re.fullmatch(rx, path) is not None


def matches_any(patterns, path):
    return any(glob_match(p, path) for p in patterns)


def line_pairs(patch):
    """Pair removed with added lines per change block of a unified diff.

    Returns (pairs, problem); problem is set when a block adds or removes
    lines instead of replacing them one for one.
    """
    pairs, removed, added = [], [], []

    def flush():
        if len(removed) != len(added):
            return f"{len(removed)} line(s) removed, {len(added)} added"
        pairs.extend(zip(removed, added))
        removed.clear()
        added.clear()
        return None

    for line in patch.splitlines():
        if line.startswith("\\"):  # "\ No newline at end of file"
            continue
        if line.startswith("-"):
            if added:  # a new -/+ block starts
                if problem := flush():
                    return pairs, problem
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
        elif problem := flush():  # context line or @@ hunk header
            return pairs, problem
    return pairs, flush()


def check_pair(old, new):
    """None if old -> new is a pin or patch bump, else the reason it isn't."""
    if REVIEW_ONLY.match(old) or REVIEW_ONLY.match(new):
        return "gate tool image (always reviewed)"
    for shape in SHAPES:
        a, b = shape.match(old), shape.match(new)
        if not (a and b):
            continue
        fixed = [k for k in shape.groupindex if k not in ("ver", "pin")]
        if any(a[k] != b[k] for k in fixed):
            return "changes more than a version or digest"
        if "ver" in shape.groupindex and a["ver"] != b["ver"]:
            va, vb = SEMVER.match(a["ver"]), SEMVER.match(b["ver"])
            if not (va and vb):
                return f"tag change {a['ver']} -> {b['ver']} is not semver"
            if va.groups()[:2] != vb.groups()[:2]:
                return f"{a['ver']} -> {b['ver']} is more than a patch"
        return None
    return "not a version or digest line"


def check_files(files):
    """Reasons a Renovate PR needs review; empty if it may merge alone."""
    reasons = []
    for f in files:
        path = f["filename"]
        if matches_any(PROTECTED, path):
            reasons.append(f"{path}: protected path")
            continue
        if not matches_any(ALLOWED, path):
            reasons.append(f"{path}: not in the Renovate allowlist")
            continue
        if f.get("status") != "modified" or f.get("previous_filename"):
            reasons.append(f"{path}: {f.get('status')}, not modified in place")
            continue
        if "patch" not in f:
            reasons.append(f"{path}: no diff available (binary or too large)")
            continue
        pairs, problem = line_pairs(f["patch"])
        if problem:
            reasons.append(f"{path}: {problem}")
        for old, new in pairs:
            if why := check_pair(old, new):
                reasons.append(f"{path}: {why}: {new.strip()[:100]}")
    return reasons


def approved(reviews, approvers, head_sha):
    """True if an approver's latest verdict is an approval of head_sha."""
    latest = {}
    for r in reviews:  # chronological
        login = (r.get("user") or {}).get("login")
        if login in approvers and r["state"] in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[login] = r
    return any(r["state"] == "APPROVED" and r["commit_id"] == head_sha for r in latest.values())


def decide(pr, files, reviews, approvers):
    """Return (passed, explanation lines)."""
    author, head = pr["user"]["login"], pr["head"]["sha"]
    if author in approvers:
        return True, [f"Opened by approver {author}."]
    if approved(reviews, approvers, head):
        return True, [f"Approved by an approver at {head[:12]}."]
    if author != RENOVATE:
        return False, [f"Opened by {author}: needs an approval from {', '.join(sorted(approvers))}."]
    reasons = check_files(files)
    if not reasons:
        return True, ["Renovate pin/digest/patch bump within the allowlist."]
    return False, ["Renovate change needs an approval:"] + [f"- {r}" for r in reasons]


def api(path):
    """GET every page of a GitHub REST API list (or a single object)."""
    url, items = f"https://api.github.com/{path}", []
    while url:
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.load(resp)
            if not isinstance(data, list):
                return data
            items += data
            nxt = re.search(r'<([^>]+)>;\s*rel="next"', resp.headers.get("Link", ""))
            url = nxt[1] if nxt else None
    return items


def main():
    repo, number = os.environ["REPO"], os.environ["PR"]
    approvers = {a.strip() for a in os.environ.get("APPROVERS", repo.split("/")[0]).split(",") if a.strip()}
    pr = api(f"repos/{repo}/pulls/{number}")  # fresh: the event payload may be stale
    files = api(f"repos/{repo}/pulls/{number}/files?per_page=100")
    reviews = api(f"repos/{repo}/pulls/{number}/reviews?per_page=100")
    passed, lines = decide(pr, files, reviews, approvers)
    report = "\n".join([f"policy-guard: {'PASS' if passed else 'NEEDS APPROVAL'}", *lines])
    print(report)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as fh:
            fh.write(report.replace("\n", "\n\n") + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
