#!/usr/bin/env python3
"""Shared TOC state collection and terminal rendering for Task Force Null."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import toc_render
import toc_state

OPERATORS = toc_state.OPERATORS


def collect_state(*args, **kwargs):
    return toc_state.collect_state(*args, **kwargs)


def render_terminal(state):
    return toc_render.render_terminal(state)


def watch_paths(repo: Path):
    return toc_state.watch_paths(repo)


def safe_under_repo(repo: Path, candidate: Path):
    return toc_state.safe_under_repo(repo, candidate)


def discover_operator_logs(repo: Path):
    return toc_state.discover_operator_logs(repo)


def cmd_render(args: argparse.Namespace) -> int:
    state = collect_state(
        Path(args.repo_root),
        mutate=bool(args.mutate),
        delegation_raw=args.delegation or "",
        autonomous_set=args.autonomous or "",
        toggle=bool(args.toggle),
        watch_interval=args.watch_interval,
        watching=bool(args.watching),
    )
    sys.stdout.write(render_terminal(state))
    return 0


def cmd_json(args: argparse.Namespace) -> int:
    state = collect_state(Path(args.repo_root))
    json.dump(state, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Task Force Null TOC library")
    sub = parser.add_subparsers(dest="command", required=True)

    p_render = sub.add_parser("render", help="Print terminal dashboard")
    p_render.add_argument("--repo-root", required=True)
    p_render.add_argument("--mutate", action="store_true")
    p_render.add_argument("--delegation", default="")
    p_render.add_argument("--autonomous", default="")
    p_render.add_argument("--toggle", action="store_true")
    p_render.add_argument("--watching", action="store_true")
    p_render.add_argument("--watch-interval", default="30")
    p_render.set_defaults(func=cmd_render)

    p_json = sub.add_parser("json", help="Print JSON state snapshot")
    p_json.add_argument("--repo-root", required=True)
    p_json.set_defaults(func=cmd_json)

    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())