"""TOC state aggregation from repo files."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import toc_config
import toc_mission

OPERATORS = ("command", "lead", "recon", "builder", "medic-qa", "comms")


def safe_under_repo(repo: Path, candidate: Path) -> Path | None:
    try:
        resolved = candidate.resolve()
        repo_resolved = repo.resolve()
        resolved.relative_to(repo_resolved)
        if resolved.is_symlink():
            target = resolved.resolve()
            target.relative_to(repo_resolved)
        return resolved
    except (ValueError, OSError):
        return None


def operator_roster(
    repo: Path, missions: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    roster: list[dict[str, Any]] = []
    for op_id in OPERATORS:
        profile_path = repo / "profiles" / ("%s.md" % op_id)
        title = op_id
        if profile_path.is_file():
            first = profile_path.read_text(encoding="utf-8", errors="replace").splitlines()
            if first and first[0].startswith("# "):
                title = first[0][2:].strip()
        owned: list[dict[str, str]] = []
        for row in missions:
            slug = row["slug"]
            for task in row.get("tasks") or []:
                owner = (task.get("owner") or "").strip().lower()
                if owner == op_id:
                    owned.append(
                        {
                            "mission": slug,
                            "id": task.get("id", ""),
                            "status": task.get("status", ""),
                            "name": task.get("name", ""),
                        }
                    )
        roster.append({"id": op_id, "title": title, "tasks": owned})
    return roster


def collect_routing(repo: Path) -> dict[str, Any]:
    models_path = repo / "brain" / "models.md"
    routing: dict[str, Any] = {
        "harness": "(models.md missing)",
        "inventory": [],
        "learned_overrides": [],
        "bindings": [],
    }
    if not models_path.is_file():
        return routing
    sections = toc_mission.section_tables(
        models_path.read_text(encoding="utf-8", errors="replace")
    )
    harness = ""
    for row in toc_mission.table_rows(sections.get("harness", [])):
        if row.get("field", "").strip() == "harness":
            harness = row.get("value", "").strip()
    routing["harness"] = harness or "(not bootstrapped)"
    for row in toc_mission.table_rows(sections.get("inventory", [])):
        mid = (row.get("model_id") or "").strip()
        if mid and mid not in ("|", "(no models detected)"):
            routing["inventory"].append(
                {"model_id": mid, "provider": (row.get("provider") or "").strip()}
            )
    for row in toc_mission.table_rows(sections.get("learned overrides", [])):
        pattern = (row.get("task_pattern") or "").strip()
        model_id = (row.get("model_id") or "").strip()
        if pattern and model_id:
            routing["learned_overrides"].append(
                {"task_pattern": pattern, "model_id": model_id}
            )
    missions_dir = repo / "missions"
    if missions_dir.is_dir():
        for env in sorted(missions_dir.glob("*/squad.env")):
            if env.parent.name.startswith("_"):
                continue
            for item in toc_mission.env_bindings(env):
                routing["bindings"].append({"mission": env.parent.name, "bind": item})
    return routing


def collect_armory(repo: Path) -> dict[str, Any]:
    armory = repo / "armory" / "ecc"
    pinned = armory / "PINNED_SHA"
    out: dict[str, Any] = {
        "present": armory.is_dir(),
        "pinned_sha": "(missing)",
    }
    if pinned.is_file():
        sha = pinned.read_text(encoding="utf-8", errors="replace").strip().splitlines()
        out["pinned_sha"] = sha[0].strip() if sha else "(empty)"
    return out


def discover_operator_logs(repo: Path) -> list[dict[str, str]]:
    logs: list[dict[str, str]] = []
    missions = repo / "missions"
    if not missions.is_dir():
        return logs
    for log_path in sorted(missions.glob("*/logs/*.log")):
        if log_path.parent.parent.name.startswith("_"):
            continue
        safe = safe_under_repo(repo, log_path)
        if not safe or not safe.is_file():
            continue
        rel = str(safe.relative_to(repo.resolve()))
        slug = log_path.parent.parent.name
        logs.append(
            {
                "mission": slug,
                "name": log_path.name,
                "path": rel,
            }
        )
    return logs


def watch_paths(repo: Path) -> list[Path]:
    paths: list[Path] = [
        repo / "brain" / "toc-config.md",
        repo / "brain" / "aar-log.md",
        repo / "brain" / "models.md",
    ]
    missions = repo / "missions"
    if missions.is_dir():
        for mission_md in sorted(missions.glob("*/mission.md")):
            if mission_md.parent.name.startswith("_"):
                continue
            slug_dir = mission_md.parent
            for name in ("mission.md", "board.md", "squad.env"):
                p = slug_dir / name
                if p.is_file():
                    paths.append(p)
            log_dir = slug_dir / "logs"
            if log_dir.is_dir():
                for log_file in sorted(log_dir.glob("*.log")):
                    safe = safe_under_repo(repo, log_file)
                    if safe:
                        paths.append(safe)
    pinned = repo / "armory" / "ecc" / "PINNED_SHA"
    if pinned.is_file():
        paths.append(pinned)
    return paths


def collect_state(
    repo: Path,
    mutate: bool = False,
    delegation_raw: str = "",
    autonomous_set: str = "",
    toggle: bool = False,
    watch_interval: str | None = None,
    watching: bool = False,
) -> dict[str, Any]:
    repo = repo.resolve()
    vals = toc_config.load_config(repo)
    if mutate:
        vals = toc_config.apply_mutations(
            repo, vals, delegation_raw, autonomous_set, toggle
        )

    min_aars = int(vals.get("MIN_AARS_FOR_DELEGATION") or "5")
    min_missions = int(vals.get("MIN_COMPLETED_MISSIONS_FOR_DELEGATION") or "3")
    aar_path = repo / "brain" / "aar-log.md"
    aar_count = toc_mission.count_aars(aar_path)
    missions = toc_mission.mission_rows(repo)
    completed = sum(1 for row in missions if row["completed"])
    pushback = (
        "pushback ready"
        if aar_count >= min_aars and completed >= min_missions
        else "pushback active"
    )
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    return {
        "generated_at": now,
        "status_strip": {
            "utc": now,
            "delegation": {
                "blockers": toc_config.as_bool(vals["DELEGATE_BLOCKERS"]),
                "external": toc_config.as_bool(vals["DELEGATE_EXTERNAL"]),
            },
            "autonomous": toc_config.as_bool(vals["AUTONOMOUS_MODE"]),
            "maturity": {
                "aar_count": aar_count,
                "min_aars": min_aars,
                "completed_missions": completed,
                "min_missions": min_missions,
                "pushback": pushback,
            },
            "watching": watching,
            "watch_interval": watch_interval,
        },
        "config": vals,
        "missions": missions,
        "operators": operator_roster(repo, missions),
        "aars": toc_mission.parse_aar_entries(aar_path),
        "routing": collect_routing(repo),
        "armory": collect_armory(repo),
        "operator_logs": discover_operator_logs(repo),
    }