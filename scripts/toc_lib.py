#!/usr/bin/env python3
"""Shared TOC state collection and terminal rendering for Task Force Null."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

OPERATORS = ("command", "lead", "recon", "builder", "medic-qa", "comms")

KEYS = (
    "DELEGATE_BLOCKERS",
    "DELEGATE_EXTERNAL",
    "AUTONOMOUS_MODE",
    "MIN_AARS_FOR_DELEGATION",
    "MIN_COMPLETED_MISSIONS_FOR_DELEGATION",
)
DEFAULTS = {
    "DELEGATE_BLOCKERS": "false",
    "DELEGATE_EXTERNAL": "false",
    "AUTONOMOUS_MODE": "false",
    "MIN_AARS_FOR_DELEGATION": "5",
    "MIN_COMPLETED_MISSIONS_FOR_DELEGATION": "3",
}


def parse_config(text: str) -> dict[str, str]:
    vals = dict(DEFAULTS)
    for line in text.splitlines():
        bare = line.replace("\r", "").strip()
        if not bare or bare.startswith("#"):
            continue
        if "=" not in bare:
            continue
        key, value = bare.split("=", 1)
        key = key.strip()
        if key in DEFAULTS:
            vals[key] = value.strip().lower()
    return vals


def load_config(repo: Path) -> dict[str, str]:
    config_path = repo / "brain" / "toc-config.md"
    if config_path.is_file():
        return parse_config(config_path.read_text(encoding="utf-8"))
    return dict(DEFAULTS)


def write_config(repo: Path, vals: dict[str, str]) -> None:
    config_path = repo / "brain" / "toc-config.md"
    if config_path.is_file():
        lines = config_path.read_text(encoding="utf-8").splitlines()
    else:
        lines = ["# TOC Config", ""]
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        bare = line.replace("\r", "")
        stripped = bare.strip()
        replaced = False
        for key in KEYS:
            if stripped.startswith(key + "="):
                out.append("%s=%s" % (key, vals[key]))
                seen.add(key)
                replaced = True
                break
        if not replaced:
            out.append(bare)
    missing = [key for key in KEYS if key not in seen]
    if missing:
        if out and out[-1].strip():
            out.append("")
        for key in missing:
            out.append("%s=%s" % (key, vals[key]))
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")


def as_bool(value: str) -> bool:
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def norm_bool(value: str, label: str) -> str:
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on"):
        return "true"
    if text in ("0", "false", "no", "off"):
        return "false"
    print("toc: invalid %s value: %s" % (label, value), file=sys.stderr)
    sys.exit(2)


def prompt_value(label: str, current: str) -> str:
    question = "%s is %s. New value [true/false/keep]: " % (label, current)
    if sys.stdin.isatty():
        try:
            ans = input(question).strip().lower()
        except EOFError:
            ans = ""
    else:
        ans = sys.stdin.readline()
        if ans == "":
            ans = "keep"
        else:
            ans = ans.strip().lower()
    if ans in ("", "keep"):
        return current
    return norm_bool(ans, label)


def active_env_files(repo: Path) -> list[Path]:
    missions = repo / "missions"
    found: list[Path] = []
    if not missions.is_dir():
        return found
    for env in sorted(missions.glob("*/squad.env")):
        if env.parent.name.startswith("_"):
            continue
        text = env.read_text(encoding="utf-8", errors="replace").replace("\r", "")
        for line in text.splitlines():
            if re.match(r"^ACTIVE=1\s*$", line.strip()):
                found.append(env)
                break
    return found


def set_env_key(path: Path, key: str, value: str) -> None:
    if path.is_file():
        lines = path.read_text(encoding="utf-8").replace("\r", "").splitlines()
    else:
        lines = []
    out: list[str] = []
    found = False
    for line in lines:
        if line.startswith(key + "="):
            out.append("%s=%s" % (key, value))
            found = True
        else:
            out.append(line)
    if not found:
        out.append("%s=%s" % (key, value))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")


def apply_mutations(
    repo: Path,
    vals: dict[str, str],
    delegation_raw: str,
    autonomous_set: str,
    toggle: bool,
) -> dict[str, str]:
    changed = False
    if delegation_raw:
        for token in delegation_raw.split():
            if "=" not in token:
                print("toc: expected key=true|false, got %s" % token, file=sys.stderr)
                sys.exit(2)
            key, value = token.split("=", 1)
            key = key.strip().lower()
            mapped = {
                "blockers": "DELEGATE_BLOCKERS",
                "external": "DELEGATE_EXTERNAL",
            }.get(key)
            if not mapped:
                print("toc: unknown delegation key: %s" % key, file=sys.stderr)
                sys.exit(2)
            vals[mapped] = norm_bool(value, key)
            changed = True
    if autonomous_set:
        vals["AUTONOMOUS_MODE"] = norm_bool(autonomous_set, "autonomous")
        changed = True
    if toggle:
        vals["DELEGATE_BLOCKERS"] = prompt_value(
            "DELEGATE_BLOCKERS", vals["DELEGATE_BLOCKERS"]
        )
        vals["DELEGATE_EXTERNAL"] = prompt_value(
            "DELEGATE_EXTERNAL", vals["DELEGATE_EXTERNAL"]
        )
        vals["AUTONOMOUS_MODE"] = prompt_value(
            "AUTONOMOUS_MODE", vals["AUTONOMOUS_MODE"]
        )
        changed = True
    if changed:
        write_config(repo, vals)
        if autonomous_set or toggle:
            targets = active_env_files(repo)
            if not targets:
                fallback = repo / "missions" / "setup-mission" / "squad.env"
                if fallback.is_file():
                    targets = [fallback]
            for env in targets:
                set_env_key(env, "AUTONOMOUS_MODE", vals["AUTONOMOUS_MODE"])
    return vals


def split_row(line: str) -> list[str] | None:
    text = line.strip()
    if not text.startswith("|"):
        return None
    cells = [cell.strip() for cell in text.strip("|").split("|")]
    if not cells or all(
        re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) or cell == "" for cell in cells
    ):
        if cells and all(
            set(cell) <= set("-: ") and "-" in cell for cell in cells if cell
        ):
            return None
    if cells and all(re.fullmatch(r"[-: ]+", cell or "-") for cell in cells):
        return None
    return cells


def parse_tasks(board_text: str) -> list[dict[str, str]]:
    tasks: list[dict[str, str]] = []
    header: list[str] | None = None
    skip_done_section = False
    for line in board_text.replace("\r", "").splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            skip_done_section = bool(
                re.match(r"^##\s+Done This Deployment\s*$", stripped, re.I)
            )
            header = None
            continue
        if skip_done_section:
            continue
        cells = split_row(line)
        if not cells:
            if line.startswith("#"):
                header = None
            continue
        lowered = [cell.lower() for cell in cells]
        if "status" in lowered and "owner" in lowered:
            header = lowered
            continue
        if not header:
            continue
        try:
            id_i = 0
            owner_i = header.index("owner")
            status_i = header.index("status")
            task_i = header.index("task") if "task" in header else 1
        except ValueError:
            continue
        task_id = cells[id_i] if len(cells) > id_i else ""
        if not task_id or task_id.lower() == "id":
            continue
        owner = cells[owner_i] if len(cells) > owner_i else ""
        status = cells[status_i] if len(cells) > status_i else ""
        name = cells[task_i] if len(cells) > task_i else ""
        tasks.append(
            {
                "id": task_id,
                "owner": owner or "-",
                "status": status or "-",
                "name": name or "-",
            }
        )
    return tasks


def objective_of(mission_md: Path) -> str:
    if not mission_md.is_file():
        return "(no mission.md)"
    text = mission_md.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\*\*Objective:\*\*\s*(.+)", text)
    if not match:
        match = re.search(r"^Objective:\s*(.+)", text, re.M)
    if not match:
        return "(objective not stated)"
    obj = re.sub(r"\s+", " ", match.group(1)).strip()
    if len(obj) > 96:
        obj = obj[:93] + "..."
    return obj


def is_active(env_path: Path) -> bool:
    if not env_path.is_file():
        return False
    text = env_path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
    return any(re.match(r"^ACTIVE=1\s*$", line.strip()) for line in text.splitlines())


def env_bindings(env_path: Path) -> list[str]:
    rows: list[str] = []
    if not env_path.is_file():
        return rows
    for line in (
        env_path.read_text(encoding="utf-8", errors="replace").replace("\r", "").splitlines()
    ):
        if line.startswith("MODEL_BIND_") and "=" in line:
            key, value = line.split("=", 1)
            if value.strip():
                rows.append("%s=%s" % (key, value.strip()))
    return rows


def count_aars(path: Path) -> int:
    if not path.is_file():
        return 0
    text = path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
    chunks = re.split(r"```", text)
    visible = []
    for index, chunk in enumerate(chunks):
        if index % 2 == 0:
            visible.append(chunk)
    count = 0
    for line in "\n".join(visible).splitlines():
        if re.match(r"^## .+\bmission:", line.strip()):
            count += 1
    return count


def parse_aar_entries(aar_path: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    if not aar_path.is_file():
        return entries
    text = aar_path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
    parts = re.split(r"```", text)
    visible = "\n".join(parts[i] for i in range(0, len(parts), 2))
    current: dict[str, str] | None = None
    for line in visible.splitlines():
        if re.match(r"^## .+\bmission:", line.strip()):
            current = {"head": line.strip()[3:], "outcome": "", "friction": "", "fix": ""}
            entries.append(current)
        elif current and line.startswith("- Outcome:"):
            current["outcome"] = line.split(":", 1)[1].strip()
        elif current and line.startswith("- Friction:"):
            current["friction"] = line.split(":", 1)[1].strip()
        elif current and line.startswith("- Fix:"):
            current["fix"] = line.split(":", 1)[1].strip()
    return entries


def mission_rows(repo: Path) -> list[dict[str, Any]]:
    missions = repo / "missions"
    rows: list[dict[str, Any]] = []
    if not missions.is_dir():
        return rows
    for mission_md in sorted(missions.glob("*/mission.md")):
        slug = mission_md.parent.name
        if slug.startswith("_"):
            continue
        board = mission_md.parent / "board.md"
        tasks = (
            parse_tasks(board.read_text(encoding="utf-8", errors="replace"))
            if board.is_file()
            else []
        )
        done = sum(
            1
            for task in tasks
            if task["status"].strip().lower() in ("done", "complete", "closed")
        )
        total = len(tasks)
        if total == 0:
            pct = 0
        else:
            pct = (100 * done + total // 2) // total
        completed = total > 0 and done == total
        rows.append(
            {
                "slug": slug,
                "objective": objective_of(mission_md),
                "active": is_active(mission_md.parent / "squad.env"),
                "tasks": tasks,
                "done": done,
                "total": total,
                "pct": pct,
                "completed": completed,
            }
        )
    return rows


def section_tables(models_text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current = ""
    for line in models_text.replace("\r", "").splitlines():
        if line.startswith("## "):
            current = line[3:].strip().lower()
            sections[current] = []
            continue
        if current:
            sections[current].append(line)
    return sections


def table_rows(lines: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    header: list[str] | None = None
    for line in lines:
        cells = split_row(line)
        if not cells:
            continue
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if all(re.fullmatch(r"[-: ]+", cell or "-") for cell in cells):
            continue
        padded = cells + [""] * (len(header) - len(cells))
        rows.append(dict(zip(header, padded)))
    return rows


def on_off(value: str) -> str:
    return "ON" if as_bool(value) else "OFF"


def clip(text: str, width: int) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= width:
        return text
    return text[: width - 3] + "..."


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
    sections = section_tables(models_path.read_text(encoding="utf-8", errors="replace"))
    harness = ""
    for row in table_rows(sections.get("harness", [])):
        if row.get("field", "").strip() == "harness":
            harness = row.get("value", "").strip()
    routing["harness"] = harness or "(not bootstrapped)"
    for row in table_rows(sections.get("inventory", [])):
        mid = (row.get("model_id") or "").strip()
        if mid and mid not in ("|", "(no models detected)"):
            routing["inventory"].append(
                {"model_id": mid, "provider": (row.get("provider") or "").strip()}
            )
    for row in table_rows(sections.get("learned overrides", [])):
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
            for item in env_bindings(env):
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
    vals = load_config(repo)
    if mutate:
        vals = apply_mutations(repo, vals, delegation_raw, autonomous_set, toggle)

    min_aars = int(vals.get("MIN_AARS_FOR_DELEGATION") or "5")
    min_missions = int(vals.get("MIN_COMPLETED_MISSIONS_FOR_DELEGATION") or "3")
    aar_path = repo / "brain" / "aar-log.md"
    aar_count = count_aars(aar_path)
    missions = mission_rows(repo)
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
                "blockers": as_bool(vals["DELEGATE_BLOCKERS"]),
                "external": as_bool(vals["DELEGATE_EXTERNAL"]),
            },
            "autonomous": as_bool(vals["AUTONOMOUS_MODE"]),
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
        "aars": parse_aar_entries(aar_path),
        "routing": collect_routing(repo),
        "armory": collect_armory(repo),
        "operator_logs": discover_operator_logs(repo),
    }


def render_terminal(state: dict[str, Any]) -> str:
    vals = state["config"]
    strip = state["status_strip"]
    mat = strip["maturity"]
    aar_count = mat["aar_count"]
    min_aars = mat["min_aars"]
    completed = mat["completed_missions"]
    min_missions = mat["min_missions"]
    pushback = mat["pushback"]
    now = strip["utc"]
    watching = strip.get("watching", False)
    interval = strip.get("watch_interval") or "30"
    missions = state["missions"]
    entries = state["aars"]
    routing = state["routing"]
    armory = state["armory"]

    lines: list[str] = []
    bar = "=" * 72
    dash = "-" * 72

    lines.append(bar)
    lines.append(" TASK FORCE NULL  TOC")
    lines.append(" %s" % now)
    if watching:
        lines.append(" watch: every %ss" % interval)
    lines.append(
        " DELEGATION: blockers=%s external=%s | AUTONOMOUS: %s | MATURITY: %s/%s AARs, %s/%s missions (%s)"
        % (
            on_off(str(vals["DELEGATE_BLOCKERS"]).lower()),
            on_off(str(vals["DELEGATE_EXTERNAL"]).lower()),
            on_off(str(vals["AUTONOMOUS_MODE"]).lower()),
            aar_count,
            min_aars,
            completed,
            min_missions,
            pushback,
        )
    )
    lines.append(bar)

    lines.append(" ACTIVE MISSIONS")
    lines.append(dash)
    if not missions:
        lines.append(" (no missions)")
    else:
        for row in missions:
            st = "ACTIVE" if row["active"] else "INACTIVE"
            lines.append(
                " %s  %s  %s%%  (%s/%s done)"
                % (row["slug"], st, row["pct"], row["done"], row["total"])
            )
            lines.append("   %s" % row["objective"])
    lines.append("")

    lines.append(" TASK OWNERSHIP")
    lines.append(dash)
    any_task = False
    for row in missions:
        if not row["tasks"]:
            continue
        any_task = True
        lines.append(" %s" % row["slug"])
        for task in row["tasks"]:
            lines.append(
                "   %-6s %-10s %-8s %s"
                % (
                    task["id"],
                    clip(task["owner"], 10),
                    clip(task["status"], 8),
                    clip(task["name"], 42),
                )
            )
    if not any_task:
        lines.append(" (no tasks)")
    lines.append("")

    lines.append(" RECENT AARS")
    lines.append(dash)
    if not entries:
        lines.append(" (none recorded)")
    else:
        for entry in entries[-3:][::-1]:
            lines.append(" %s" % clip(entry["head"], 70))
            if entry["outcome"]:
                lines.append("   outcome: %s" % clip(entry["outcome"], 64))
            if entry["friction"]:
                lines.append("   friction: %s" % clip(entry["friction"], 63))
            if entry["fix"]:
                lines.append("   fix: %s" % clip(entry["fix"], 68))
    lines.append("")

    lines.append(" MODEL ROUTING")
    lines.append(dash)
    if routing["harness"] == "(models.md missing)":
        lines.append(" harness: (models.md missing)")
        lines.append(" inventory: (none)")
        lines.append(" learned overrides: (none)")
    else:
        lines.append(" harness: %s" % routing["harness"])
        inventory = routing["inventory"]
        if inventory:
            inv_txt = "; ".join(
                "%s (%s)" % (r["model_id"], r["provider"]) for r in inventory[:6]
            )
            lines.append(" inventory: %s" % clip(inv_txt, 68))
        else:
            lines.append(" inventory: (none)")
        overrides = routing["learned_overrides"]
        if overrides:
            ov_txt = "; ".join(
                "%s -> %s" % (r["task_pattern"], r["model_id"]) for r in overrides[:4]
            )
            lines.append(" learned overrides: %s" % clip(ov_txt, 60))
        else:
            lines.append(" learned overrides: (none)")
    bindings = routing["bindings"]
    if bindings:
        bind_txt = "; ".join("%s %s" % (b["mission"], b["bind"]) for b in bindings[:6])
        lines.append(" bindings: %s" % clip(bind_txt, 64))
    else:
        lines.append(" bindings: (none)")
    lines.append("")

    lines.append(" ARMORY")
    lines.append(dash)
    lines.append(
        " armory/ecc: %s" % ("present" if armory["present"] else "missing")
    )
    lines.append(" PINNED_SHA: %s" % armory["pinned_sha"])
    lines.append(bar)

    return "\n".join(lines) + "\n"


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