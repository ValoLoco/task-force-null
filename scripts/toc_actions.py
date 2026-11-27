#!/usr/bin/env python3
"""Board task moves and operator telemetry for the web TOC (stdlib only)."""
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import toc_chat
import toc_mission
import toc_state

MAX_BOARD_POST_BYTES = 4096

ALLOWED_STATUS = frozenset(
    {
        "todo",
        "doing",
        "in_progress",
        "review",
        "done",
        "blocked",
        "complete",
        "closed",
        "active",
        "in progress",
    }
)

CYCLE_ORDER = ("todo", "in_progress", "review", "done")

DONE_STATUSES = frozenset({"done", "complete", "closed"})
BLOCKED_STATUS = "blocked"
ACTIVE_STATUSES = frozenset(
    {
        "todo",
        "doing",
        "in_progress",
        "review",
        "active",
        "in progress",
    }
)


def normalize_status_token(status: str) -> str:
    return status.strip().lower()


def status_valid(token: str) -> bool:
    return normalize_status_token(token) in ALLOWED_STATUS


def next_task_status(current: str) -> str:
    cur = normalize_status_token(current)
    if cur == BLOCKED_STATUS:
        return "in_progress"
    if cur in ("doing", "active", "in progress"):
        cur = "in_progress"
    if cur in DONE_STATUSES:
        return "todo"
    if cur == "in_progress":
        return "review"
    if cur == "review":
        return "done"
    if cur == "todo":
        return "in_progress"
    return "in_progress"


def _board_path(repo_root: Path, slug: str) -> Path:
    return repo_root / "missions" / slug / "board.md"


def _parse_board_header(board_text: str) -> tuple[list[str] | None, list[int]]:
    lines = board_text.replace("\r", "").splitlines()
    header: list[str] | None = None
    header_line_idx = -1
    skip_done_section = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("## "):
            skip_done_section = bool(
                re.match(r"^##\s+Done This Deployment\s*$", stripped, re.I)
            )
            header = None
            continue
        if skip_done_section:
            continue
        cells = toc_mission.split_row(line)
        if not cells:
            continue
        lowered = [cell.lower() for cell in cells]
        if "status" in lowered and "owner" in lowered:
            header = lowered
            header_line_idx = idx
            break
    return header, [header_line_idx]


def move_board_task(
    repo_root: Path,
    slug: str,
    task_id: str,
    target_status: str,
) -> tuple[str, int, dict[str, str] | None]:
    """Return (error_message, http_status, updated_task_dict)."""
    err, status = toc_chat.validate_mission_slug(repo_root, slug)
    if err:
        return err, status, None
    if not task_id or not isinstance(task_id, str):
        return "task_id required", 400, None
    task_id = task_id.strip()
    if not task_id:
        return "task_id required", 400, None
    if not status_valid(target_status):
        return "invalid status", 400, None
    norm = normalize_status_token(target_status)
    if norm == "in progress":
        target = "in progress"
    elif norm == "in_progress":
        target = "in_progress"
    elif norm == "active":
        target = "doing"
    else:
        target = norm

    board = _board_path(repo_root, slug)
    if not board.is_file():
        return "mission not found", 404, None
    text = board.read_text(encoding="utf-8", errors="replace")
    header, _ = _parse_board_header(text)
    if not header:
        return "board table missing", 404, None
    try:
        id_i = 0
        status_i = header.index("status")
        owner_i = header.index("owner")
        task_i = header.index("task") if "task" in header else 1
    except ValueError:
        return "board table missing", 404, None

    lines = text.replace("\r", "").splitlines(keepends=True)
    skip_done_section = False
    found = False
    updated: dict[str, str] | None = None
    new_lines: list[str] = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            skip_done_section = bool(
                re.match(r"^##\s+Done This Deployment\s*$", stripped, re.I)
            )
            new_lines.append(line)
            continue
        if skip_done_section:
            new_lines.append(line)
            continue
        cells = toc_mission.split_row(line)
        if cells and not found:
            row_id = cells[id_i] if len(cells) > id_i else ""
            if row_id == task_id:
                found = True
                while len(cells) <= status_i:
                    cells.append("")
                cells[status_i] = target
                owner = cells[owner_i] if len(cells) > owner_i else "-"
                name = cells[task_i] if len(cells) > task_i else "-"
                updated = {
                    "id": task_id,
                    "owner": owner or "-",
                    "status": target,
                    "name": name or "-",
                }
                new_line = "| " + " | ".join(cells) + " |"
                if line.endswith("\n"):
                    new_line += "\n"
                new_lines.append(new_line)
                continue
        new_lines.append(line)

    if not found:
        return "task not found", 404, None

    payload = "".join(new_lines)
    tmp = board.with_suffix(".board.md.tmp")
    try:
        tmp.write_text(payload, encoding="utf-8")
        os.replace(tmp, board)
    except OSError as exc:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return "board write failed: %s" % exc, 500, None

    return "", 200, updated


def validate_board_move_body(body: dict[str, Any]) -> tuple[str, int, str, str, str]:
    """Return (error, status, slug, task_id, status_token)."""
    if not isinstance(body, dict):
        return "body must be a json object", 400, "", "", ""
    mission = body.get("mission", "")
    if not isinstance(mission, str):
        return "mission must be a string", 400, "", "", ""
    task_id = body.get("task_id", "")
    if not isinstance(task_id, str):
        return "task_id must be a string", 400, "", "", ""
    status = body.get("status", "")
    if not isinstance(status, str):
        return "status must be a string", 400, "", "", ""
    if not task_id.strip():
        return "task_id required", 400, "", "", ""
    if not status_valid(status):
        return "invalid status", 400, "", "", ""
    return "", 0, mission, task_id.strip(), status.strip()


def _status_class(status: str) -> str:
    s = normalize_status_token(status)
    if s in DONE_STATUSES:
        return "done"
    if s == BLOCKED_STATUS:
        return "blocked"
    if s in ACTIVE_STATUSES or s == "doing":
        return "active"
    return "active"


def _count_log_lines(log_path: Path) -> tuple[int, str | None]:
    if not log_path.is_file():
        return 0, None
    try:
        text = log_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0, None
    lines = [ln for ln in text.splitlines() if ln.strip()]
    last_ts: str | None = None
    mtime = datetime.fromtimestamp(log_path.stat().st_mtime, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    if lines:
        last_ts = mtime
    return len(lines), last_ts


def compute_operator_telemetry(
    repo_root: Path,
    slug: str,
    snapshot: dict[str, Any] | None = None,
) -> tuple[str, int, dict[str, Any] | None]:
    err, status = toc_chat.validate_mission_slug(repo_root, slug)
    if err:
        return err, status, None
    if snapshot is None:
        snapshot = toc_state.collect_state(repo_root)
    mission_row: dict[str, Any] | None = None
    for row in snapshot.get("missions") or []:
        if row.get("slug") == slug:
            mission_row = row
            break
    if mission_row is None:
        return "mission not found", 404, None

    tasks = mission_row.get("tasks") or []
    per_op: dict[str, dict[str, Any]] = {}
    for op_id in toc_state.OPERATORS:
        per_op[op_id] = {
            "operator": op_id,
            "active_tasks": 0,
            "done_tasks": 0,
            "blocked_tasks": 0,
            "total_tasks": 0,
            "log_lines": 0,
            "last_log_ts": None,
            "health": "idle",
        }

    for task in tasks:
        owner = (task.get("owner") or "").strip().lower()
        if owner not in per_op:
            continue
        st = normalize_status_token(task.get("status") or "")
        bucket = _status_class(st)
        per_op[owner]["total_tasks"] += 1
        if bucket == "done":
            per_op[owner]["done_tasks"] += 1
        elif bucket == "blocked":
            per_op[owner]["blocked_tasks"] += 1
        else:
            per_op[owner]["active_tasks"] += 1

    logs_dir = repo_root / "missions" / slug / "logs"
    if logs_dir.is_dir():
        for log_file in sorted(logs_dir.glob("*.log")):
            stem = log_file.stem.lower()
            if stem not in per_op:
                continue
            count, last_ts = _count_log_lines(log_file)
            per_op[stem]["log_lines"] = count
            if last_ts:
                per_op[stem]["last_log_ts"] = last_ts

    summary = {
        "active_tasks": 0,
        "done_tasks": 0,
        "blocked_tasks": 0,
        "total_tasks": len(tasks),
    }
    operators: list[dict[str, Any]] = []
    for op_id in toc_state.OPERATORS:
        row = per_op[op_id]
        summary["active_tasks"] += row["active_tasks"]
        summary["done_tasks"] += row["done_tasks"]
        summary["blocked_tasks"] += row["blocked_tasks"]
        if row["blocked_tasks"] > 0:
            row["health"] = "blocked"
        elif row["active_tasks"] > 0 or row["log_lines"] > 0:
            row["health"] = "active"
        else:
            row["health"] = "idle"
        operators.append(row)

    payload = {
        "mission": slug,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "operators": operators,
        "summary": summary,
    }
    return "", 200, payload


def telemetry_json(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")