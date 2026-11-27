"""Mission board, AAR, and markdown table parsing for TOC."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any


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