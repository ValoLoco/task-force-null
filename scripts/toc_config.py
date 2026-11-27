"""TOC brain/toc-config.md and squad.env toggle helpers."""
from __future__ import annotations

import re
import sys
from pathlib import Path

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