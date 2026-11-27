#!/usr/bin/env python3
"""Mission-scoped commander chat JSONL helpers (stdlib only)."""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MISSION_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
CHAT_FILENAME = "commander-chat.jsonl"
MAX_TEXT_BYTES = 8192
DEFAULT_FETCH_LIMIT = 200
MAX_FETCH_LIMIT = 500
ALLOWED_SENDERS = frozenset(
    ("user", "command", "lead", "recon", "builder", "medic-qa", "comms")
)


def slug_syntax_ok(slug: str) -> bool:
    if not slug or not isinstance(slug, str):
        return False
    if ".." in slug or "/" in slug or "\\" in slug:
        return False
    return MISSION_SLUG_RE.match(slug) is not None


def mission_exists(repo: Path, slug: str) -> bool:
    return (repo / "missions" / slug / "mission.md").is_file()


def validate_mission_slug(repo: Path, slug: str) -> tuple[str, int]:
    """Return (error_message, http_status). Empty error means ok."""
    if not slug_syntax_ok(slug):
        return "invalid mission slug", 400
    if not mission_exists(repo, slug):
        return "mission not found", 404
    return "", 0


def chat_log_path(repo: Path, slug: str) -> Path:
    return repo / "missions" / slug / "logs" / CHAT_FILENAME


def utc_now_z() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_limit(raw: str | None) -> int:
    if not raw:
        return DEFAULT_FETCH_LIMIT
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return DEFAULT_FETCH_LIMIT
    if value < 1:
        return DEFAULT_FETCH_LIMIT
    return min(value, MAX_FETCH_LIMIT)


def parse_jsonl_messages(path: Path, limit: int) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    lines: list[dict[str, Any]] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    for raw in text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(row, dict):
            continue
        if not all(k in row for k in ("ts", "mission", "sender", "text")):
            continue
        lines.append(row)
    if len(lines) > limit:
        lines = lines[-limit:]
    return lines


def read_messages(repo: Path, slug: str, limit: int) -> list[dict[str, Any]]:
    path = chat_log_path(repo, slug)
    return parse_jsonl_messages(path, limit)


def validate_post_body(body: dict[str, Any]) -> tuple[str, int, str, str]:
    """Return (error, status, slug, text) or empty error on success."""
    mission = body.get("mission", "")
    if not isinstance(mission, str):
        return "mission must be a string", 400, "", ""
    text = body.get("text", "")
    if not isinstance(text, str):
        return "text must be a string", 400, "", ""
    text = text.strip()
    if not text:
        return "text must not be empty", 400, "", ""
    if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
        return "text too large", 413, "", ""
    sender = body.get("sender", "user")
    if not isinstance(sender, str):
        return "sender must be a string", 400, "", ""
    if sender not in ALLOWED_SENDERS:
        return "invalid sender", 400, "", ""
    return "", 0, mission, text


def append_message(
    repo: Path, slug: str, sender: str, text: str
) -> dict[str, Any]:
    logs_dir = repo / "missions" / slug / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    entry = {
        "ts": utc_now_z(),
        "mission": slug,
        "sender": sender,
        "text": text,
    }
    line = json.dumps(entry, separators=(",", ":")) + "\n"
    path = chat_log_path(repo, slug)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(line)
    return entry