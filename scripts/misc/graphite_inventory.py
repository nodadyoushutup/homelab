#!/usr/bin/env python3
"""
Enumerate all Graphite leaf metrics under a namespace (default: truenas.nas)
and write the sorted list to a file so operators can diff new datapoints over time.

Usage:
    python3 scripts/graphite_inventory.py \
        --base-url http://swarm-cp-0:8081 \
        --prefix truenas.nas \
        --output /tmp/truenas_metrics.txt
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from typing import Iterable
from urllib import error, parse, request


def fetch_nodes(base_url: str, query: str, timeout: int, verbose: bool = False, seq: int | None = None) -> Iterable[dict]:
    """Call /metrics/find for the query and yield the decoded JSON nodes."""
    params = parse.urlencode({"query": query, "format": "treejson"})
    url = f"{base_url.rstrip('/')}/metrics/find?{params}"
    if verbose:
        prefix = f"[INFO] query#{seq} " if seq is not None else "[INFO] "
        print(f"{prefix}GET {url}")
    with request.urlopen(url, timeout=timeout) as resp:
        return json.load(resp)


def inventory(
    base_url: str,
    prefix: str,
    timeout: int = 10,
    verbose: bool = False,
    log_every: int = 100,
) -> list[str]:
    """
    Walk the Graphite tree breadth-first and return every leaf metric.
    """
    start = f"{prefix}.*"
    queue = deque([start])
    visited: set[str] = set()
    leaves: set[str] = set()
    queries = 0

    def maybe_log(summary: str) -> None:
        if verbose:
            print(f"[INFO] {summary}")

    while queue:
        query = queue.popleft()
        if query in visited:
            continue
        visited.add(query)
        queries += 1

        try:
            nodes = fetch_nodes(base_url, query, timeout, verbose, queries if verbose else None)
        except error.URLError as exc:
            print(f"[WARN] Failed query {query}: {exc}", file=sys.stderr)
            continue

        maybe_log(f"query#{queries} returned {len(nodes)} nodes (queue={len(queue)})")

        for node in nodes:
            node_id = node.get("id")
            if not node_id:
                continue
            if node.get("leaf"):
                leaves.add(node_id)
            else:
                queue.append(f"{node_id}.*")

        if verbose and queries % log_every == 0:
            maybe_log(f"progress: {len(leaves)} leaves discovered so far")

    maybe_log(f"completed traversal ({queries} queries, {len(leaves)} leaves)")
    return sorted(leaves)


def main() -> int:
    parser = argparse.ArgumentParser(description="Enumerate Graphite metrics under a prefix.")
    parser.add_argument("--base-url", default="http://swarm-cp-0:8081",
                        help="Graphite HTTP endpoint (defaults to http://swarm-cp-0:8081).")
    parser.add_argument("--prefix", default="truenas.nas",
                        help="Metric namespace prefix to walk (default: truenas.nas).")
    parser.add_argument("--output", default="/tmp/truenas_metrics.txt",
                        help="Destination file for the sorted metrics list.")
    parser.add_argument("--timeout", type=int, default=10,
                        help="HTTP timeout in seconds for each Graphite request.")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Emit detailed progress logs while crawling.")
    parser.add_argument("--log-every", type=int, default=100,
                        help="When verbose, print a summary after this many queries (default: 100).")
    args = parser.parse_args()

    metrics = inventory(
        args.base_url,
        args.prefix,
        timeout=args.timeout,
        verbose=args.verbose,
        log_every=max(1, args.log_every),
    )
    try:
        with open(args.output, "w", encoding="utf-8") as handle:
            for metric in metrics:
                handle.write(f"{metric}\n")
    except OSError as exc:
        print(f"[ERROR] Unable to write {args.output}: {exc}", file=sys.stderr)
        return 1

    print(f"Wrote {len(metrics)} metrics to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
