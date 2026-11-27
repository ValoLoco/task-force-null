#!/usr/bin/env python3
"""Lean task router: maps description to operator role and model tier. Stdlib only."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROLES = ("command", "lead", "recon", "builder", "medic-qa", "comms")

# Order matters: first match wins within each tier scan
RULES: list[tuple[str, tuple[str, ...]]] = [
    ("command", ("portfolio", "multi-squad", "deconflict", "colonel", "orchestrat")),
    ("comms", ("publish", "communicate", "email", "pr description", "readme", "external", "draft message")),
    ("medic-qa", ("verify", "test", "qa", "aar", "regression", "validate", "lint", "audit")),
    ("recon", ("research", "intel", "map", "investigate", "unknown", "risk", "explore", "source")),
    ("builder", ("implement", "build", "fix", "code", "script", "refactor", "deploy code", "create file")),
    ("lead", ("route", "assign", "prioritize", "go/no-go", "plan", "decompose", "board")),
]

DEFAULT_ROLE = "builder"
DEFAULT_TIER = "standard"

TIER_BY_ROLE = {
    "command": "heavy",
    "lead": "standard",
    "recon": "light",
    "builder": "standard",
    "medic-qa": "standard",
    "comms": "light",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def load_tier_overrides(root: Path) -> dict[str, str]:
    """Optional MISSION_SLUG/squad.env tier overrides."""
    overrides: dict[str, str] = {}
    slug = os.environ.get("MISSION_SLUG", "")
    if not slug:
        env_path = root / "missions" / "example-mission" / "squad.env"
        if env_path.is_file():
            slug = "example-mission"
        else:
            return overrides
    env_file = root / "missions" / slug / "squad.env"
    if not env_file.is_file():
        return overrides
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.strip(), val.strip()
        if key.startswith("MODEL_TIER_") and val:
            role_key = key.replace("MODEL_TIER_", "").lower().replace("_", "-")
            if role_key == "default":
                overrides["_default"] = val
            else:
                overrides[role_key] = val
    return overrides


def route_task(description: str) -> tuple[str, str]:
    text = description.lower()
    for role, keywords in RULES:
        for kw in keywords:
            if kw in text:
                tier = TIER_BY_ROLE.get(role, DEFAULT_TIER)
                return role, tier
    return DEFAULT_ROLE, DEFAULT_TIER


def apply_overrides(role: str, tier: str, overrides: dict[str, str]) -> str:
    role_key = role.replace("_", "-")
    if role_key in overrides:
        return overrides[role_key]
    if f"model_tier_{role_key}" in overrides:
        return overrides[f"model_tier_{role_key}"]
    # env keys like MODEL_TIER_RECON -> recon
    for k, v in overrides.items():
        if k.replace("_", "-") == role_key:
            return v
    return overrides.get("_default", tier)


def append_routing_log(root: Path, entry: dict) -> None:
    log_dir = root / "brain"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "routing-log.jsonl"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Route task to SF operator role")
    parser.add_argument("task", nargs="?", default="", help="Task description")
    parser.add_argument("--log", action="store_true", help="Append JSON line to brain/routing-log.jsonl")
    parser.add_argument("--json", action="store_true", help="Print JSON only (default)")
    args = parser.parse_args()

    task = args.task.strip() or " ".join(sys.argv[1:]).strip()
    if not task:
        parser.error("task description required")

    root = repo_root()
    overrides_raw = load_tier_overrides(root)
    role, tier = route_task(task)
    tier = apply_overrides(role, tier, overrides_raw)

    mission = os.environ.get("MISSION_SLUG", "")
    if not mission:
        for p in (root / "missions").glob("*/squad.env"):
            text = p.read_text(encoding="utf-8")
            if re.search(r"^ACTIVE=1\s*$", text, re.MULTILINE):
                mission = p.parent.name
                break

    payload = {
        "role": role,
        "model_tier": tier,
        "mission_slug": mission or None,
        "task_excerpt": task[:200],
    }

    print(json.dumps(payload, indent=2))

    if args.log:
        entry = {
            **payload,
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        append_routing_log(root, entry)

    return 0


if __name__ == "__main__":
    sys.exit(main())