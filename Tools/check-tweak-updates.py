#!/usr/bin/env python3
"""Report which of the repository's tweaks lag behind their upstream repositories.

The tweak set comes from the Makefile (TWEAK_REGISTRY plus PAYLOAD_TWEAKS), the
upstream URLs and branches from .gitmodules, the installed versions from each
tweak's control file. Three kinds of tweaks are distinguished:

  submodule  a git submodule pinned to a commit - the update is a new gitlink
  payload    a prebuilt .deb downloaded by the Makefile (YTPlus, Gonerino)
  vendored   code that lives in this repository and has no upstream

Upstream versions are read from raw.githubusercontent.com and git ls-remote, so
the check needs no API token and does not touch the GitHub API rate limit. Used
by .github/workflows/update-tweaks.yml and by the local web UI (``--json``).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "uYouEnhanced-check-tweak-updates"
NETWORK_TIMEOUT = 8
GIT_TIMEOUT = 25
WORKERS = 8


def die(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(cmd, cwd=None, timeout=GIT_TIMEOUT):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


# ---------------------------------------------------------------------------
# Local repository state
# ---------------------------------------------------------------------------

def parse_makefile(text):
    """Return the variables the Makefile sets.

    The first plain assignment wins, `+=` lines extend it - that is how the tweaks
    added through the app are layered on from Tweaks/custom.mk.
    """
    joined = re.sub(r"\\\r?\n[ \t]*", " ", text)
    variables = {}
    for line in joined.splitlines():
        match = re.match(r"^([A-Za-z0-9_\-]+)\s*(\+?[:?]?=)\s*(.*)$", line)
        if not match:
            continue
        name, operator, value = match.group(1), match.group(2), match.group(3).strip()
        if operator == "+=" and name in variables:
            variables[name] = f"{variables[name]} {value}".strip()
        elif name not in variables:
            variables[name] = value
    return variables


def submodule_urls(repo):
    """Return {path: {"url": ..., "branch": ...}} from .gitmodules."""
    out = run(["git", "config", "-f", ".gitmodules", "--get-regexp",
               r"^submodule\..*\.(path|url|branch)$"], cwd=repo)
    if out.returncode != 0:
        return {}
    modules = {}
    for line in out.stdout.splitlines():
        key, _, value = line.partition(" ")
        match = re.match(r"submodule\.(.*)\.(path|url|branch)$", key)
        if not match:
            continue
        name, field = match.groups()
        modules.setdefault(name, {})[field] = value
    return {m["path"]: m for m in modules.values() if "path" in m}


def gitlink(repo, path):
    """The commit a submodule is pinned to (works without the submodule checked out)."""
    fields = run(["git", "ls-tree", "HEAD", "--", path], cwd=repo).stdout.split()
    return fields[2][:8] if len(fields) > 2 and fields[1] == "commit" else None


def control_version(path):
    control = Path(path) / "control"
    if not control.is_file():
        return None
    match = re.search(r"^Version:\s*(.+)$", control.read_text(errors="replace"), re.M)
    return match.group(1).strip() if match else None


# ---------------------------------------------------------------------------
# Upstream state
# ---------------------------------------------------------------------------

class Offline(Exception):
    pass


def fetch_text(url, token=None):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=NETWORK_TIMEOUT) as response:
            return response.read().decode("utf8", "replace")
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return None
        raise Offline(f"HTTP {err.code} for {url}") from err
    except Exception as err:  # URLError, timeout, ...
        raise Offline(f"{err} for {url}") from err


def fetch_release(slug, token=None):
    text = fetch_text(f"https://api.github.com/repos/{slug}/releases/latest", token)
    if text is None:
        return None
    try:
        return json.loads(text)
    except ValueError as err:
        raise Offline(f"invalid JSON for {slug}") from err


def remote_head(url):
    """Return (branch, commit) of a remote's default branch in a single call."""
    out = run(["git", "ls-remote", "--symref", url, "HEAD"])
    if out.returncode != 0:
        raise Offline(out.stderr.strip() or f"could not reach {url}")
    branch, commit = None, None
    for line in out.stdout.splitlines():
        if line.startswith("ref:"):
            branch = line.split()[1].removeprefix("refs/heads/")
        elif line.strip():
            commit = line.split()[0][:8]
    return branch, commit


def remote_branch(url, branch):
    fields = run(["git", "ls-remote", url, branch]).stdout.split()
    return fields[0][:8] if fields else None


def github_slug(url):
    match = re.match(r"https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/|$)", url or "")
    return f"{match.group(1)}/{match.group(2)}" if match else None


def control_version_text(text):
    if not text:
        return None
    match = re.search(r"^Version:\s*(.+)$", text, re.M)
    return match.group(1).strip() if match else None


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def local_entry(repo, tweak_id, makefile, modules, payloads):
    subproject = makefile.get(f"{tweak_id}_SUBPROJECT")
    path = next((p for p in modules if subproject and (subproject == p or subproject.startswith(p + "/"))),
                subproject or f"Tweaks/{tweak_id}")
    entry = {
        "id": tweak_id,
        "path": path,
        "kind": None,
        "url": None,
        "ref": None,
        "local_version": None,
        "upstream_version": None,
        "local_commit": None,
        "upstream_commit": None,
        "outdated": None,
        "note": None,
    }
    if tweak_id in payloads:
        entry["kind"] = "payload"
        entry["url"] = makefile.get(f"{tweak_id.upper()}_URL")
        entry["local_version"] = makefile.get(f"{tweak_id.upper()}_VERSION")
    elif path in modules:
        entry["kind"] = "submodule"
        entry["url"] = modules[path].get("url")
        entry["ref"] = modules[path].get("branch")
        entry["local_version"] = control_version(repo / path)
        entry["local_commit"] = gitlink(repo, path)
    else:
        entry["kind"] = "vendored"
        entry["local_version"] = control_version(repo / path)
        entry["outdated"] = False
        entry["note"] = "lives in this repository"
    return entry


def support_entry(path, modules):
    """A header/library submodule the tweaks build against (no control file)."""
    module = modules.get(path) or {}
    return {
        "id": path,
        "path": path,
        "kind": "support",
        "url": module.get("url"),
        "ref": module.get("branch"),
        "local_version": None,
        "upstream_version": None,
        "local_commit": None,
        "upstream_commit": None,
        "outdated": None,
        "note": None,
    }


def fill_upstream(entry, token, state):
    """Add the upstream version/commit. Runs in a worker, must not raise."""
    try:
        if entry["kind"] in ("submodule", "support"):
            url, branch = entry["url"], entry["ref"]
            if not url:
                entry["note"] = "no .gitmodules entry"
                return
            commit = remote_branch(url, branch) if branch else None
            if branch is None:
                branch, commit = remote_head(url)
            slug = github_slug(url)
            entry["ref"] = branch
            entry["upstream_commit"] = commit
            entry["upstream_version"] = control_version_text(
                fetch_text(f"https://raw.githubusercontent.com/{slug}/{branch}/control", token)) if slug else None
            # A support module has no control file of its own to compare against,
            # so only the pinned commit decides whether it is behind.
            if entry["kind"] == "support":
                entry["outdated"] = bool(entry["local_commit"] and commit and entry["local_commit"] != commit)
            else:
                entry["outdated"] = bool(
                    (entry["local_commit"] and commit and entry["local_commit"] != commit)
                    or (entry["upstream_version"] and entry["local_version"] != entry["upstream_version"]))
        elif entry["kind"] == "payload":
            slug = github_slug(entry["url"])
            if not slug:
                entry["note"] = "outside GitHub - update it manually"
                return
            entry["url"] = f"https://github.com/{slug}"
            release = fetch_release(slug, token)
            if not release:
                entry["note"] = "no GitHub release"
                return
            latest = (release.get("tag_name") or "").lstrip("v")
            entry["upstream_version"] = latest or None
            entry["outdated"] = bool(latest and latest != entry["local_version"])
    except Offline as err:
        state["offline"] = True
        entry["note"] = f"offline ({err})"
    except subprocess.TimeoutExpired:
        state["offline"] = True
        entry["note"] = "offline (git timed out)"


def collect(repo, only=None, token=None):
    # Tweaks added through the app live in Tweaks/custom.mk, which the Makefile
    # includes - read both so the report covers them.
    text = (repo / "Makefile").read_text(errors="replace")
    custom_tweaks = repo / "Tweaks/custom.mk"
    if custom_tweaks.is_file():
        text += "\n" + custom_tweaks.read_text(errors="replace")
    makefile = parse_makefile(text)
    registry = (makefile.get("TWEAK_REGISTRY") or "").split()
    payloads = set((makefile.get("PAYLOAD_TWEAKS") or "").split())
    modules = submodule_urls(repo)
    tweaks = [local_entry(repo, id_, makefile, modules, payloads)
              for id_ in registry + sorted(payloads)
              if not only or id_ in only]
    # Header/library submodules the tweaks include from Tweaks/ - a tweak that
    # moves upstream usually needs these to move with it.
    support = [support_entry(p, modules)
               for p in (makefile.get("SUPPORT_SUBMODULES") or "").split()
               if p in modules]
    for entry in support:
        entry["local_commit"] = gitlink(repo, entry["path"])
        entry["local_version"] = control_version(repo / entry["path"])
    state = {"offline": False}
    with ThreadPoolExecutor(max_workers=min(WORKERS, max(len(tweaks) + len(support), 1))) as pool:
        list(pool.map(lambda entry: fill_upstream(entry, token, state), tweaks + support))
    return {
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "offline": state["offline"],
        "registry": registry,
        "defaults": (makefile.get("DEFAULT_TWEAKS") or "").split(),
        "custom": (makefile.get("CUSTOM_TWEAKS") or "").split(),
        "tweaks": tweaks,
        "outdated": [t["id"] for t in tweaks if t["outdated"]],
        "support": support,
        "outdated_support": [s["path"] for s in support if s["outdated"]],
    }


def print_report(report):
    for tweak in report["tweaks"]:
        if tweak["outdated"]:
            status = "OUTDATED"
            detail = f"{tweak['local_version']} -> {tweak['upstream_version']}"
        elif tweak["outdated"] is False:
            status, detail = "ok", str(tweak["local_version"] or "-")
        else:
            status, detail = "unknown", tweak["note"] or "-"
        location = tweak["url"] or tweak["note"] or ""
        if tweak["ref"]:
            location = f"{location} @ {tweak['ref']}"
        print(f"  {status:9} {tweak['id']:24} {detail:22} {location}")
    for entry in report.get("support", []):
        if entry["outdated"]:
            print(f"  OUTDATED  {entry['id']:24} {'shared module':22} "
                  f"{entry['local_commit']} -> {entry['upstream_commit']}")
    if report["offline"]:
        print("\nnetwork unreachable - upstream versions could not be checked")
        return
    parts = []
    if report["outdated"]:
        parts.append(f"{len(report['outdated'])} outdated: {' '.join(report['outdated'])}")
    if report.get("outdated_support"):
        parts.append(f"shared modules behind: {' '.join(report['outdated_support'])}")
    print("\n" + " · ".join(parts) if parts else "\nall tweaks up to date")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]),
                        help="repository root (default: the parent of this script's directory)")
    parser.add_argument("--only", default="", help="comma/space separated tweak ids to check")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"),
                        help="GitHub token, only used to raise the API rate limit (default: $GITHUB_TOKEN)")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    if not (repo / "Makefile").is_file():
        die(f"{repo} does not look like the repository root (no Makefile)")

    only = {id_ for id_ in re.split(r"[\s,]+", args.only) if id_}
    report = collect(repo, only=only, token=args.token)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)


if __name__ == "__main__":
    main()
