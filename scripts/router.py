#!/usr/bin/env python3
"""Task router: operator role plus best-fit-first model selection. Stdlib only."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
import unittest
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROLES = ("command", "lead", "recon", "builder", "medic-qa", "comms")

RULES: list[tuple[str, tuple[str, ...]]] = [
    ("command", ("portfolio", "multi-squad", "deconflict", "colonel", "orchestrat")),
    ("comms", ("publish", "communicate", "email", "pr description", "readme", "external", "draft message")),
    ("medic-qa", ("verify", "test", "qa", "aar", "regression", "validate", "lint", "audit")),
    ("recon", ("research", "intel", "map", "investigate", "unknown", "risk", "explore", "source")),
    ("builder", ("implement", "build", "fix", "code", "script", "refactor", "deploy code", "create file")),
    ("lead", ("route", "assign", "prioritize", "go/no-go", "plan", "decompose", "board")),
]

DEFAULT_ROLE = "builder"

ROLE_CAPS: dict[str, set[str]] = {
    "command": {"reasoning", "long_context"},
    "lead": {"reasoning", "tool_use"},
    "recon": {"fast_qa", "tool_use"},
    "builder": {"code", "tool_use"},
    "medic-qa": {"fast_qa", "reasoning"},
    "comms": {"fast_qa"},
}

COMPLEXITY_KEYWORDS = {
    "simple": ("lint", "typo", "format", "rename", "quick"),
    "moderate": ("implement", "refactor", "integrate", "update", "add feature"),
    "complex": ("architect", "security", "migrate", "multi-file", "performance"),
    "frontier": ("novel", "prove", "research", "unknown", "formal"),
}

CAPABILITY_KEYWORDS = {
    "code": ("code", "implement", "refactor", "bug", "compile", "python", "bash"),
    "reasoning": ("plan", "design", "analyze", "decide", "strategy", "decompose"),
    "tool_use": ("tool", "api", "mcp", "cli", "script", "grep", "search"),
    "long_context": ("entire repo", "large file", "full codebase", "thousand"),
    "vision": ("screenshot", "image", "ui", "pixel", "diagram photo"),
    "fast_qa": ("verify", "quick", "smoke", "sanity", "lint", "check"),
}


@dataclass
class ModelRow:
    model_id: str
    provider: str
    capabilities: set[str]
    context_tokens: int
    cost_tier: int
    latency_note: str
    reliability_note: str


@dataclass
class LearnedOverride:
    task_pattern: str
    model_id: str
    outcome: str
    notes: str


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def parse_md_table(lines: list[str], header_marker: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    in_table = False
    headers: list[str] = []
    for line in lines:
        if header_marker in line and "|" in line:
            in_table = True
            headers = [h.strip().lower().replace(" ", "_") for h in line.split("|")[1:-1]]
            continue
        if not in_table:
            continue
        if not line.strip().startswith("|"):
            in_table = False
            continue
        if re.match(r"^\|\s*[-:]+\s*\|", line):
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        if len(cells) != len(headers):
            continue
        row = dict(zip(headers, cells))
        rows.append(row)
    return rows


def load_models_md(path: Path) -> tuple[list[ModelRow], list[LearnedOverride], bool]:
    if not path.is_file():
        return [], [], False
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    inv_raw = parse_md_table(lines, "model_id")
    inventory: list[ModelRow] = []
    bootstrapped = False
    for r in inv_raw:
        mid = (r.get("model_id") or "").strip()
        if not mid or mid.startswith("(") or mid == "" or "pending" in mid.lower():
            continue
        caps = {c.strip() for c in (r.get("capabilities") or "").split(",") if c.strip()}
        try:
            ctx = int(re.sub(r"[^0-9]", "", r.get("context_tokens", "0") or "0") or "0")
        except ValueError:
            ctx = 0
        try:
            cost = int(r.get("cost_tier", "3") or "3")
        except ValueError:
            cost = 3
        inventory.append(
            ModelRow(
                model_id=mid,
                provider=r.get("provider", ""),
                capabilities=caps,
                context_tokens=ctx or 32000,
                cost_tier=cost,
                latency_note=r.get("latency_note", ""),
                reliability_note=r.get("reliability_note", ""),
            )
        )
        bootstrapped = True
    ovr_raw = parse_md_table(lines, "task_pattern")
    overrides: list[LearnedOverride] = []
    for r in ovr_raw:
        pat = (r.get("task_pattern") or "").strip()
        mid = (r.get("model_id") or "").strip()
        if not pat or not mid:
            continue
        overrides.append(
            LearnedOverride(
                task_pattern=pat,
                model_id=mid,
                outcome=(r.get("outcome") or "").strip().lower(),
                notes=r.get("notes", ""),
            )
        )
    return inventory, overrides, bootstrapped


def load_squad_env(root: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    slug = os.environ.get("MISSION_SLUG", "")
    if not slug:
        for p in (root / "missions").glob("*/squad.env"):
            if re.search(r"^ACTIVE=1\s*$", p.read_text(encoding="utf-8"), re.MULTILINE):
                slug = p.parent.name
                break
    if not slug:
        return env
    env_file = root / "missions" / slug / "squad.env"
    if not env_file.is_file():
        return env
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.strip(), val.strip()
        if key.startswith("MODEL_BIND_") and val:
            role = key.replace("MODEL_BIND_", "").lower().replace("_", "-")
            env[role] = val
        if key.startswith("MODEL_TIER_") and val:
            role = key.replace("MODEL_TIER_", "").lower().replace("_", "-")
            env[f"tier:{role}"] = val
    return env


def route_task(description: str) -> str:
    text = description.lower()
    for role, keywords in RULES:
        for kw in keywords:
            if kw in text:
                return role
    return DEFAULT_ROLE


def infer_complexity(description: str) -> str:
    text = description.lower()
    scores = {k: 0 for k in COMPLEXITY_KEYWORDS}
    for level, words in COMPLEXITY_KEYWORDS.items():
        for w in words:
            if w in text:
                scores[level] += 1
    order = ("frontier", "complex", "moderate", "simple")
    for level in order:
        if scores[level] > 0:
            return level
    length = len(description.split())
    if length > 40:
        return "complex"
    if length > 15:
        return "moderate"
    return "simple"


def required_capabilities(description: str, role: str) -> set[str]:
    caps = set(ROLE_CAPS.get(role, set()))
    text = description.lower()
    for cap, words in CAPABILITY_KEYWORDS.items():
        for w in words:
            if w in text:
                caps.add(cap)
    return caps


def estimate_tokens(description: str) -> int:
    return max(500, len(description.split()) * 40)


def complexity_min_caps(complexity: str) -> set[str]:
    return {
        "simple": {"fast_qa"},
        "moderate": {"code", "tool_use"},
        "complex": {"code", "reasoning", "tool_use"},
        "frontier": {"reasoning", "long_context", "tool_use"},
    }.get(complexity, set())


def learned_adjustment(task: str, model_id: str, overrides: list[LearnedOverride]) -> float:
    adj = 0.0
    for o in overrides:
        if fnmatch.fnmatch(task.lower(), o.task_pattern.lower()):
            if o.model_id == model_id:
                if o.outcome == "success":
                    adj += 15.0
                elif o.outcome == "fail":
                    adj -= 20.0
                elif o.outcome == "partial":
                    adj += 5.0
    return adj


def score_model(
    model: ModelRow,
    needed: set[str],
    est_tokens: int,
    complexity: str,
    task: str,
    overrides: list[LearnedOverride],
) -> float:
    if not model.model_id:
        return -1.0
    cap_score = len(model.capabilities & needed) * 10.0
    min_caps = complexity_min_caps(complexity)
    cap_score += len(model.capabilities & min_caps) * 8.0
    if est_tokens <= model.context_tokens:
        cap_score += 12.0
    elif est_tokens <= model.context_tokens * 2:
        cap_score += 4.0
    else:
        cap_score -= 25.0
    for cap in needed:
        if cap in model.capabilities:
            cap_score += 3.0
    if complexity in ("complex", "frontier") and "reasoning" in model.capabilities:
        cap_score += 6.0
    if complexity == "simple" and "fast_qa" in model.capabilities:
        cap_score += 6.0
    cap_score += learned_adjustment(task, model.model_id, overrides)
    return cap_score


def select_model(
    inventory: list[ModelRow],
    role: str,
    task: str,
    squad_env: dict[str, str],
    overrides: list[LearnedOverride],
) -> dict[str, Any]:
    complexity = infer_complexity(task)
    needed = required_capabilities(task, role)
    est = estimate_tokens(task)
    bind = squad_env.get(role)
    if bind:
        for m in inventory:
            if m.model_id == bind:
                return {
                    "selected_model": bind,
                    "fit_score": 100.0,
                    "tiebreak_reason": "squad.env MODEL_BIND override",
                    "step_up_candidate": _step_candidate(inventory, bind, direction=1),
                    "step_down_candidate": _step_candidate(inventory, bind, direction=-1),
                    "complexity": complexity,
                    "required_capabilities": sorted(needed),
                    "estimated_tokens": est,
                }

    if not inventory:
        return {
            "selected_model": None,
            "fit_score": None,
            "tiebreak_reason": None,
            "step_up_candidate": None,
            "step_down_candidate": None,
            "complexity": complexity,
            "required_capabilities": sorted(needed),
            "estimated_tokens": est,
        }

    scored: list[tuple[float, ModelRow]] = []
    for m in inventory:
        s = score_model(m, needed, est, complexity, task, overrides)
        scored.append((s, m))
    scored.sort(key=lambda x: (-x[0], x[1].cost_tier, x[1].model_id))

    best_score = scored[0][0]
    ties = [m for s, m in scored if abs(s - best_score) < 0.001]
    if len(ties) > 1:
        ties.sort(key=lambda m: (m.cost_tier, m.model_id))
        chosen = ties[0]
        tiebreak = f"equal fit ({best_score:.1f}); lower cost_tier {chosen.cost_tier}"
    else:
        chosen = scored[0][1]
        tiebreak = "best fit score"

    return {
        "selected_model": chosen.model_id,
        "fit_score": round(best_score, 2),
        "tiebreak_reason": tiebreak,
        "step_up_candidate": _step_candidate(inventory, chosen.model_id, direction=1),
        "step_down_candidate": _step_candidate(inventory, chosen.model_id, direction=-1),
        "complexity": complexity,
        "required_capabilities": sorted(needed),
        "estimated_tokens": est,
    }


def _step_candidate(inventory: list[ModelRow], current: str, direction: int) -> str | None:
    if not inventory:
        return None
    uniq = sorted({m.cost_tier for m in inventory})
    cur = next((m.cost_tier for m in inventory if m.model_id == current), uniq[0])
    if direction > 0:
        higher = [t for t in uniq if t > cur]
        if not higher:
            return None
        target = min(higher)
    else:
        lower = [t for t in uniq if t < cur]
        if not lower:
            return None
        target = max(lower)
    cands = [m.model_id for m in inventory if m.cost_tier == target]
    return cands[0] if cands else None


def append_routing_log(root: Path, entry: dict) -> None:
    log_path = root / "brain" / "routing-log.jsonl"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=True) + "\n")


def build_payload(root: Path, task: str) -> dict[str, Any]:
    role = route_task(task)
    inventory, overrides, bootstrapped = load_models_md(root / "brain" / "models.md")
    squad_env = load_squad_env(root)
    model_pick = select_model(inventory, role, task, squad_env, overrides)

    mission = os.environ.get("MISSION_SLUG", "")
    if not mission:
        for p in (root / "missions").glob("*/squad.env"):
            if re.search(r"^ACTIVE=1\s*$", p.read_text(encoding="utf-8"), re.MULTILINE):
                mission = p.parent.name
                break

    tier_legacy = squad_env.get(f"tier:{role}") or squad_env.get("tier:default") or "standard"
    payload: dict[str, Any] = {
        "role": role,
        "model_tier": tier_legacy,
        "mission_slug": mission or None,
        "task_excerpt": task[:200],
        "routing_policy": "best_fit_first",
        "models_bootstrapped": bootstrapped,
        **model_pick,
    }
    if not bootstrapped:
        payload["models_status"] = "run scripts/detect-models.sh to bootstrap brain/models.md"
    elif model_pick.get("selected_model"):
        payload["model_id"] = model_pick["selected_model"]
        ct = next(
            (m.cost_tier for m in inventory if m.model_id == model_pick["selected_model"]),
            3,
        )
        payload["model_tier"] = {1: "light", 2: "light", 3: "standard", 4: "heavy", 5: "heavy"}.get(ct, "standard")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Route task to operator and best-fit model")
    parser.add_argument("task", nargs="?", default="", help="Task description")
    parser.add_argument("--log", action="store_true", help="Append JSON line to brain/routing-log.jsonl")
    args = parser.parse_args()

    task = args.task.strip()
    if not task:
        parser.error("task description required")

    root = repo_root()
    payload = build_payload(root, task)
    print(json.dumps(payload, indent=2))

    if args.log:
        entry = {**payload, "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        append_routing_log(root, entry)

    return 0


def build_payload_at(root: Path, task: str) -> dict[str, Any]:
    role = route_task(task)
    inventory, overrides, bootstrapped = load_models_md(root / "brain" / "models.md")
    squad_env = load_squad_env(root) if root == repo_root() else {}
    model_pick = select_model(inventory, role, task, squad_env, overrides)
    payload: dict[str, Any] = {
        "role": role,
        "routing_policy": "best_fit_first",
        "models_bootstrapped": bootstrapped,
        **model_pick,
    }
    if not bootstrapped:
        payload["models_status"] = "run scripts/detect-models.sh to bootstrap brain/models.md"
    return payload


class RouterTestsFixed(unittest.TestCase):
    def test_role_routing_preserved(self) -> None:
        self.assertEqual(route_task("verify unit tests"), "medic-qa")

    def test_unbootstrapped(self) -> None:
        import tempfile

        td = Path(tempfile.mkdtemp())
        (td / "brain").mkdir()
        (td / "brain" / "models.md").write_text("# empty\n", encoding="utf-8")
        payload = build_payload_at(td, "implement feature")
        self.assertFalse(payload["models_bootstrapped"])

    def test_best_fit_ranking(self) -> None:
        import tempfile

        td = Path(tempfile.mkdtemp())
        (td / "brain").mkdir()
        (td / "brain" / "models.md").write_text(
            "| model_id | provider | capabilities | context_tokens | cost_tier | latency_note | reliability_note |\n"
            "|----------|----------|--------------|----------------|-----------|--------------|------------------|\n"
            "| small-fast | local | fast_qa | 8000 | 1 | low | ok |\n"
            "| heavy-code | local | code,tool_use,reasoning | 128000 | 5 | high | ok |\n",
            encoding="utf-8",
        )
        payload = build_payload_at(td, "implement complex refactor across modules")
        self.assertEqual(payload["selected_model"], "heavy-code")

    def test_cost_tiebreak(self) -> None:
        import tempfile

        td = Path(tempfile.mkdtemp())
        (td / "brain").mkdir()
        (td / "brain" / "models.md").write_text(
            "| model_id | provider | capabilities | context_tokens | cost_tier | latency_note | reliability_note |\n"
            "|----------|----------|--------------|----------------|-----------|--------------|------------------|\n"
            "| alpha | p | code,tool_use | 64000 | 2 | | |\n"
            "| beta | p | code,tool_use | 64000 | 4 | | |\n",
            encoding="utf-8",
        )
        payload = build_payload_at(td, "implement code fix")
        self.assertEqual(payload["selected_model"], "alpha")
        self.assertIn("cost_tier", payload.get("tiebreak_reason", ""))

    def test_learned_override(self) -> None:
        import tempfile

        td = Path(tempfile.mkdtemp())
        (td / "brain").mkdir()
        (td / "brain" / "models.md").write_text(
            "| model_id | provider | capabilities | context_tokens | cost_tier | latency_note | reliability_note |\n"
            "|----------|----------|--------------|----------------|-----------|--------------|------------------|\n"
            "| alpha | p | code | 32000 | 1 | | |\n"
            "| beta | p | code,tool_use | 64000 | 3 | | |\n"
            "\n"
            "| task_pattern | model_id | outcome | notes |\n"
            "|--------------|----------|---------|-------|\n"
            "| *lint* | alpha | success | |\n",
            encoding="utf-8",
        )
        payload = build_payload_at(td, "run lint on tree")
        self.assertEqual(payload["selected_model"], "alpha")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(RouterTestsFixed)
        raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
    sys.exit(main())