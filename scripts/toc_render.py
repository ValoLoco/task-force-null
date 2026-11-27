"""Terminal TOC rendering."""
from __future__ import annotations

import re
from typing import Any

import toc_config


def on_off(value: str) -> str:
    return "ON" if toc_config.as_bool(value) else "OFF"


def clip(text: str, width: int) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= width:
        return text
    return text[: width - 3] + "..."


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