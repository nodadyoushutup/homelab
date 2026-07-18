#!/usr/bin/env python3
"""
Compile GitHub release notes from a Jira Fix Version and publish a GitHub Release.

Flow:
    1. Query Jira for every issue tagged with a given Fix Version.
    2. Group issues by type (Features / Fixes / Chores / ...) into Markdown notes.
    3. Create (or update) a GitHub Release for a tag, using those notes as the body.

Designed to be driven by a Jira Automation "Version released" webhook (via a
Jenkins job) or run by hand. Uses only the Python standard library.

Auth (environment variables):
    JIRA_URL          e.g. https://your-org.atlassian.net
    JIRA_USERNAME     Atlassian account email (Cloud) — omit for a bare PAT (Server/DC)
    JIRA_API_TOKEN    Atlassian API token / PAT
    GITHUB_TOKEN      GitHub token with `contents: write` on the target repo
                      (GH_TOKEN is also accepted)

Example:
    python3 scripts/release/jira_github_release.py \
        --jira-project HOMELAB \
        --fix-version 1.4.0 \
        --github-repo nodadyoushutup/homelab \
        --dry-run
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from typing import Any
from urllib import error, parse, request

# Jira issue type -> release-notes section heading. Types not listed fall under
# DEFAULT_SECTION. Order here is the order sections appear in the notes.
TYPE_SECTIONS: list[tuple[str, tuple[str, ...]]] = [
    ("Breaking changes", ("breaking",)),
    ("Features", ("story", "new feature", "feature", "epic")),
    ("Improvements", ("improvement", "enhancement", "task")),
    ("Bug fixes", ("bug", "defect")),
    ("Chores", ("chore", "sub-task", "subtask")),
]
DEFAULT_SECTION = "Other"

JIRA_PAGE_SIZE = 100
HTTP_TIMEOUT = 30


def env(*names: str) -> str | None:
    """Return the first non-empty environment variable among names."""
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None


def http_json(
    method: str,
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    """Perform an HTTP request and decode a JSON response. Returns (status, body)."""
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = request.Request(url, data=data, method=method, headers=headers)
    try:
        with request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw else None)
    except error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            body: Any = json.loads(raw)
        except json.JSONDecodeError:
            body = raw
        return exc.code, body


def jira_headers(username: str | None, token: str) -> dict[str, str]:
    """Basic auth (email:token) for Cloud, bearer PAT when no username given."""
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if username:
        raw = f"{username}:{token}".encode("utf-8")
        headers["Authorization"] = "Basic " + base64.b64encode(raw).decode("ascii")
    else:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def fetch_issues(
    jira_url: str,
    headers: dict[str, str],
    project: str,
    fix_version: str,
) -> list[dict[str, Any]]:
    """Return all issues in project tagged with fix_version, paginated."""
    jql = (
        f'project = "{project}" AND fixVersion = "{fix_version}" '
        "ORDER BY issuetype ASC, key ASC"
    )
    base = jira_url.rstrip("/")
    issues: list[dict[str, Any]] = []
    start_at = 0
    while True:
        query = parse.urlencode(
            {
                "jql": jql,
                "startAt": start_at,
                "maxResults": JIRA_PAGE_SIZE,
                "fields": "summary,issuetype,status,assignee",
            }
        )
        status, body = http_json("GET", f"{base}/rest/api/2/search?{query}", headers)
        if status != 200:
            raise RuntimeError(f"Jira search failed (HTTP {status}): {body}")
        batch = body.get("issues", []) if isinstance(body, dict) else []
        issues.extend(batch)
        total = body.get("total", 0) if isinstance(body, dict) else 0
        start_at += len(batch)
        if not batch or start_at >= total:
            break
    return issues


def section_for(issue_type: str) -> str:
    """Map a Jira issue type name to a release-notes section heading."""
    normalized = issue_type.strip().lower()
    for heading, matches in TYPE_SECTIONS:
        if normalized in matches:
            return heading
    return DEFAULT_SECTION


def compile_notes(
    issues: list[dict[str, Any]],
    jira_url: str,
    project: str,
    fix_version: str,
) -> str:
    """Group issues by section and render Markdown release notes."""
    base = jira_url.rstrip("/")
    grouped: dict[str, list[str]] = {}
    for issue in issues:
        key = issue.get("key", "?")
        fields = issue.get("fields", {}) or {}
        summary = (fields.get("summary") or "").strip()
        issue_type = (fields.get("issuetype") or {}).get("name", "") or ""
        heading = section_for(issue_type)
        link = f"[{key}]({base}/browse/{key})"
        grouped.setdefault(heading, []).append(f"- {link} {summary}")

    order = [heading for heading, _ in TYPE_SECTIONS] + [DEFAULT_SECTION]
    lines: list[str] = []
    for heading in order:
        bullets = grouped.get(heading)
        if not bullets:
            continue
        lines.append(f"### {heading}")
        lines.extend(bullets)
        lines.append("")

    if not lines:
        lines.append(f"_No Jira issues found for fix version `{fix_version}`._")

    header = (
        f"## {project} {fix_version}\n\n"
        f"{len(issues)} issue(s) delivered in this release.\n"
    )
    return header + "\n" + "\n".join(lines).rstrip() + "\n"


def find_release(repo: str, tag: str, headers: dict[str, str]) -> dict[str, Any] | None:
    """Return an existing GitHub release for tag, or None."""
    url = f"https://api.github.com/repos/{repo}/releases/tags/{parse.quote(tag)}"
    status, body = http_json("GET", url, headers)
    if status == 200 and isinstance(body, dict):
        return body
    if status == 404:
        return None
    raise RuntimeError(f"GitHub release lookup failed (HTTP {status}): {body}")


def publish_release(
    repo: str,
    tag: str,
    name: str,
    body_md: str,
    target: str,
    draft: bool,
    prerelease: bool,
    headers: dict[str, str],
) -> dict[str, Any]:
    """Create a release, or update it in place if the tag already has one."""
    payload = {
        "tag_name": tag,
        "target_commitish": target,
        "name": name,
        "body": body_md,
        "draft": draft,
        "prerelease": prerelease,
    }
    existing = find_release(repo, tag, headers)
    if existing:
        release_id = existing["id"]
        url = f"https://api.github.com/repos/{repo}/releases/{release_id}"
        status, resp = http_json("PATCH", url, headers, payload)
        action = "updated"
    else:
        url = f"https://api.github.com/repos/{repo}/releases"
        status, resp = http_json("POST", url, headers, payload)
        action = "created"
    if status not in (200, 201):
        raise RuntimeError(f"GitHub release {action} failed (HTTP {status}): {resp}")
    resp = resp if isinstance(resp, dict) else {}
    resp["_action"] = action
    return resp


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jira-project", default=env("JIRA_PROJECT"), help="Jira project key (env JIRA_PROJECT)")
    parser.add_argument("--fix-version", default=env("FIX_VERSION"), help="Jira Fix Version name (env FIX_VERSION)")
    parser.add_argument("--github-repo", default=env("GITHUB_REPO"), help="owner/repo (env GITHUB_REPO)")
    parser.add_argument("--tag", default=env("RELEASE_TAG"), help="Git tag (default: v<fix-version>)")
    parser.add_argument("--name", default=env("RELEASE_NAME"), help="Release title (default: <project> <fix-version>)")
    parser.add_argument("--target", default=env("RELEASE_TARGET") or "main", help="Target commitish for a new tag (default: main)")
    parser.add_argument("--draft", action="store_true", help="Create the release as a draft")
    parser.add_argument("--prerelease", action="store_true", help="Mark the release as a pre-release")
    parser.add_argument("--dry-run", action="store_true", help="Print the notes and exit without touching GitHub")
    parser.add_argument("--output", help="Also write the compiled notes to this file")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    missing = [n for n, v in (("--jira-project", args.jira_project), ("--fix-version", args.fix_version)) if not v]
    if missing:
        print(f"[ERR] Missing required argument(s): {', '.join(missing)}", file=sys.stderr)
        return 2

    jira_url = env("JIRA_URL")
    jira_token = env("JIRA_API_TOKEN")
    if not jira_url or not jira_token:
        print("[ERR] JIRA_URL and JIRA_API_TOKEN must be set", file=sys.stderr)
        return 2
    jira_user = env("JIRA_USERNAME")

    print(f"[INFO] Querying Jira {args.jira_project} for fixVersion={args.fix_version!r}", file=sys.stderr)
    issues = fetch_issues(jira_url, jira_headers(jira_user, jira_token), args.jira_project, args.fix_version)
    print(f"[INFO] Found {len(issues)} issue(s)", file=sys.stderr)

    notes = compile_notes(issues, jira_url, args.jira_project, args.fix_version)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(notes)
        print(f"[INFO] Wrote notes to {args.output}", file=sys.stderr)

    tag = args.tag or f"v{args.fix_version}"
    name = args.name or f"{args.jira_project} {args.fix_version}"

    if args.dry_run:
        print(f"[INFO] --dry-run: would publish tag {tag!r} to {args.github_repo}", file=sys.stderr)
        print(notes)
        return 0

    if not args.github_repo:
        print("[ERR] --github-repo (or GITHUB_REPO) is required unless --dry-run", file=sys.stderr)
        return 2
    gh_token = env("GITHUB_TOKEN", "GH_TOKEN")
    if not gh_token:
        print("[ERR] GITHUB_TOKEN (or GH_TOKEN) must be set unless --dry-run", file=sys.stderr)
        return 2

    gh_headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {gh_token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
        "User-Agent": "homelab-jira-release",
    }
    release = publish_release(
        args.github_repo, tag, name, notes, args.target, args.draft, args.prerelease, gh_headers
    )
    print(f"[DONE] Release {release.get('_action')}: {release.get('html_url')}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
