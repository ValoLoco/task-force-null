#!/usr/bin/env bash
# Tactical Operations Center dashboard. Bash plus Python 3 stdlib.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCH=0
INTERVAL=30
TOGGLE=0
MUTATE=0
SET_AUTONOMOUS=""
DELEGATION_SET=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --watch                         Refresh every 30 seconds (clears the screen)
  --interval SECONDS              Watch period in seconds (use with --watch)
  --set-delegation KEY=true|false Set DELEGATE_BLOCKERS and/or DELEGATE_EXTERNAL
                                  Keys: blockers, external (one or both)
  --set-autonomous true|false     Set AUTONOMOUS_MODE in toc-config and active squad.env
  --toggle                        Prompt for blockers, external, and autonomous
  --repo-root PATH                Read and write this repo root (tests)

Config: brain/toc-config.md
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch) WATCH=1; shift ;;
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --set-delegation)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        DELEGATION_SET="${DELEGATION_SET} $1"
        shift
      done
      MUTATE=1
      ;;
    --set-autonomous)
      SET_AUTONOMOUS="${2:-}"
      shift 2
      MUTATE=1
      ;;
    --toggle) TOGGLE=1; MUTATE=1; shift ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  echo "interval must be a positive integer" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "toc: python3 is required" >&2
  exit 1
fi

render() {
  local mutate="$1"
  TOC_REPO="$REPO_ROOT" \
  TOC_MUTATE="$mutate" \
  TOC_TOGGLE="$TOGGLE" \
  TOC_DELEGATION="$DELEGATION_SET" \
  TOC_AUTONOMOUS="$SET_AUTONOMOUS" \
  TOC_INTERVAL="$INTERVAL" \
  TOC_WATCH="$WATCH" \
  python3 /dev/fd/3 3<<'PY'
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

repo = Path(os.environ["TOC_REPO"]).resolve()
mutate = os.environ.get("TOC_MUTATE", "0") == "1"
toggle = os.environ.get("TOC_TOGGLE", "0") == "1"
delegation_raw = os.environ.get("TOC_DELEGATION", "").strip()
autonomous_set = os.environ.get("TOC_AUTONOMOUS", "").strip().lower()
interval = os.environ.get("TOC_INTERVAL", "30")
watching = os.environ.get("TOC_WATCH", "0") == "1"

config_path = repo / "brain" / "toc-config.md"
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

def parse_config(text):
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

def load_config():
    if config_path.is_file():
        return parse_config(config_path.read_text(encoding="utf-8"))
    return dict(DEFAULTS)

def write_config(vals):
    if config_path.is_file():
        lines = config_path.read_text(encoding="utf-8").splitlines()
    else:
        lines = ["# TOC Config", ""]
    seen = set()
    out = []
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

def as_bool(value):
    return str(value).strip().lower() in ("1", "true", "yes", "on")

def norm_bool(value, label):
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on"):
        return "true"
    if text in ("0", "false", "no", "off"):
        return "false"
    print("toc: invalid %s value: %s" % (label, value), file=sys.stderr)
    sys.exit(2)

def prompt_value(label, current):
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

def active_env_files():
    missions = repo / "missions"
    found = []
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

def set_env_key(path, key, value):
    if path.is_file():
        lines = path.read_text(encoding="utf-8").replace("\r", "").splitlines()
    else:
        lines = []
    out = []
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

def apply_mutations(vals):
    changed = False
    if delegation_raw:
        for token in delegation_raw.split():
            if "=" not in token:
                print("toc: expected key=true|false, got %s" % token, file=sys.stderr)
                sys.exit(2)
            key, value = token.split("=", 1)
            key = key.strip().lower()
            mapped = {"blockers": "DELEGATE_BLOCKERS", "external": "DELEGATE_EXTERNAL"}.get(key)
            if not mapped:
                print("toc: unknown delegation key: %s" % key, file=sys.stderr)
                sys.exit(2)
            vals[mapped] = norm_bool(value, key)
            changed = True
    if autonomous_set:
        vals["AUTONOMOUS_MODE"] = norm_bool(autonomous_set, "autonomous")
        changed = True
    if toggle:
        vals["DELEGATE_BLOCKERS"] = prompt_value("DELEGATE_BLOCKERS", vals["DELEGATE_BLOCKERS"])
        vals["DELEGATE_EXTERNAL"] = prompt_value("DELEGATE_EXTERNAL", vals["DELEGATE_EXTERNAL"])
        vals["AUTONOMOUS_MODE"] = prompt_value("AUTONOMOUS_MODE", vals["AUTONOMOUS_MODE"])
        changed = True
    if changed:
        write_config(vals)
        if autonomous_set or toggle:
            targets = active_env_files()
            if not targets:
                fallback = repo / "missions" / "setup-mission" / "squad.env"
                if fallback.is_file():
                    targets = [fallback]
            for env in targets:
                set_env_key(env, "AUTONOMOUS_MODE", vals["AUTONOMOUS_MODE"])
    return vals

def split_row(line):
    text = line.strip()
    if not text.startswith("|"):
        return None
    cells = [cell.strip() for cell in text.strip("|").split("|")]
    if not cells or all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) or cell == "" for cell in cells):
        if cells and all(set(cell) <= set("-: ") and "-" in cell for cell in cells if cell):
            return None
    if cells and all(re.fullmatch(r"[-: ]+", cell or "-") for cell in cells):
        return None
    return cells

def parse_tasks(board_text):
    tasks = []
    header = None
    for line in board_text.replace("\r", "").splitlines():
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
        tasks.append({"id": task_id, "owner": owner or "-", "status": status or "-", "name": name or "-"})
    return tasks

def objective_of(mission_md):
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

def is_active(env_path):
    if not env_path.is_file():
        return False
    text = env_path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
    return any(re.match(r"^ACTIVE=1\s*$", line.strip()) for line in text.splitlines())

def env_bindings(env_path):
    rows = []
    if not env_path.is_file():
        return rows
    for line in env_path.read_text(encoding="utf-8", errors="replace").replace("\r", "").splitlines():
        if line.startswith("MODEL_BIND_") and "=" in line:
            key, value = line.split("=", 1)
            if value.strip():
                rows.append("%s=%s" % (key, value.strip()))
    return rows

def count_aars(path):
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

def mission_rows():
    missions = repo / "missions"
    rows = []
    if not missions.is_dir():
        return rows
    for mission_md in sorted(missions.glob("*/mission.md")):
        slug = mission_md.parent.name
        if slug.startswith("_"):
            continue
        board = mission_md.parent / "board.md"
        tasks = parse_tasks(board.read_text(encoding="utf-8", errors="replace")) if board.is_file() else []
        done = sum(1 for task in tasks if task["status"].strip().lower() in ("done", "complete", "closed"))
        total = len(tasks)
        if total == 0:
            pct = 0
        else:
            pct = (100 * done + total // 2) // total
        completed = total > 0 and done == total
        rows.append({
            "slug": slug,
            "objective": objective_of(mission_md),
            "active": is_active(mission_md.parent / "squad.env"),
            "tasks": tasks,
            "done": done,
            "total": total,
            "pct": pct,
            "completed": completed,
        })
    return rows

def section_tables(models_text):
    sections = {}
    current = ""
    for line in models_text.replace("\r", "").splitlines():
        if line.startswith("## "):
            current = line[3:].strip().lower()
            sections[current] = []
            continue
        if current:
            sections[current].append(line)
    return sections

def table_rows(lines):
    rows = []
    header = None
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

def on_off(value):
    return "ON" if as_bool(value) else "OFF"

def clip(text, width):
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= width:
        return text
    return text[: width - 3] + "..."

vals = load_config()
if mutate:
    vals = apply_mutations(vals)

min_aars = int(vals.get("MIN_AARS_FOR_DELEGATION") or "5")
min_missions = int(vals.get("MIN_COMPLETED_MISSIONS_FOR_DELEGATION") or "3")
aar_count = count_aars(repo / "brain" / "aar-log.md")
missions = mission_rows()
completed = sum(1 for row in missions if row["completed"])
pushback = "pushback ready" if aar_count >= min_aars and completed >= min_missions else "pushback active"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
bar = "=" * 72
dash = "-" * 72

print(bar)
print(" TASK FORCE NULL  TOC")
print(" %s" % now)
if watching:
    print(" watch: every %ss" % interval)
print(
    " DELEGATION: blockers=%s external=%s | AUTONOMOUS: %s | MATURITY: %s/%s AARs, %s/%s missions (%s)"
    % (
        on_off(vals["DELEGATE_BLOCKERS"]),
        on_off(vals["DELEGATE_EXTERNAL"]),
        on_off(vals["AUTONOMOUS_MODE"]),
        aar_count,
        min_aars,
        completed,
        min_missions,
        pushback,
    )
)
print(bar)

print(" ACTIVE MISSIONS")
print(dash)
if not missions:
    print(" (no missions)")
else:
    for row in missions:
        state = "ACTIVE" if row["active"] else "INACTIVE"
        print(" %s  %s  %s%%  (%s/%s done)" % (row["slug"], state, row["pct"], row["done"], row["total"]))
        print("   %s" % row["objective"])
print("")

print(" TASK OWNERSHIP")
print(dash)
any_task = False
for row in missions:
    if not row["tasks"]:
        continue
    any_task = True
    print(" %s" % row["slug"])
    for task in row["tasks"]:
        print("   %-6s %-10s %-8s %s" % (task["id"], clip(task["owner"], 10), clip(task["status"], 8), clip(task["name"], 42)))
if not any_task:
    print(" (no tasks)")
print("")

print(" RECENT AARS")
print(dash)
aar_path = repo / "brain" / "aar-log.md"
entries = []
if aar_path.is_file():
    text = aar_path.read_text(encoding="utf-8", errors="replace").replace("\r", "")
    parts = re.split(r"```", text)
    visible = "\n".join(parts[i] for i in range(0, len(parts), 2))
    current = None
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
if not entries:
    print(" (none recorded)")
else:
    for entry in entries[-3:][::-1]:
        print(" %s" % clip(entry["head"], 70))
        if entry["outcome"]:
            print("   outcome: %s" % clip(entry["outcome"], 64))
        if entry["friction"]:
            print("   friction: %s" % clip(entry["friction"], 63))
        if entry["fix"]:
            print("   fix: %s" % clip(entry["fix"], 68))
print("")

print(" MODEL ROUTING")
print(dash)
models_path = repo / "brain" / "models.md"
if not models_path.is_file():
    print(" harness: (models.md missing)")
    print(" inventory: (none)")
    print(" learned overrides: (none)")
else:
    sections = section_tables(models_path.read_text(encoding="utf-8", errors="replace"))
    harness = ""
    for row in table_rows(sections.get("harness", [])):
        if row.get("field", "").strip() == "harness":
            harness = row.get("value", "").strip()
    print(" harness: %s" % (harness or "(not bootstrapped)"))
    inventory = []
    for row in table_rows(sections.get("inventory", [])):
        mid = (row.get("model_id") or "").strip()
        if mid and mid not in ("|", "(no models detected)"):
            inventory.append("%s (%s)" % (mid, (row.get("provider") or "").strip()))
    if inventory:
        print(" inventory: %s" % clip("; ".join(inventory[:6]), 68))
    else:
        print(" inventory: (none)")
    overrides = []
    for row in table_rows(sections.get("learned overrides", [])):
        pattern = (row.get("task_pattern") or "").strip()
        model_id = (row.get("model_id") or "").strip()
        if pattern and model_id:
            overrides.append("%s -> %s" % (pattern, model_id))
    if overrides:
        print(" learned overrides: %s" % clip("; ".join(overrides[:4]), 60))
    else:
        print(" learned overrides: (none)")
bindings = []
missions_dir = repo / "missions"
if missions_dir.is_dir():
    for env in sorted(missions_dir.glob("*/squad.env")):
        if env.parent.name.startswith("_"):
            continue
        for item in env_bindings(env):
            bindings.append("%s %s" % (env.parent.name, item))
if bindings:
    print(" bindings: %s" % clip("; ".join(bindings[:6]), 64))
else:
    print(" bindings: (none)")
print("")

print(" ARMORY")
print(dash)
armory = repo / "armory" / "ecc"
pinned = armory / "PINNED_SHA"
print(" armory/ecc: %s" % ("present" if armory.is_dir() else "missing"))
if pinned.is_file():
    sha = pinned.read_text(encoding="utf-8", errors="replace").strip().splitlines()
    print(" PINNED_SHA: %s" % (sha[0].strip() if sha else "(empty)"))
else:
    print(" PINNED_SHA: (missing)")
print(bar)
PY
}

if [[ "$WATCH" -eq 1 ]]; then
  render "$MUTATE"
  TOGGLE=0
  MUTATE=0
  DELEGATION_SET=""
  SET_AUTONOMOUS=""
  trap 'exit 0' INT TERM
  while true; do
    sleep "$INTERVAL"
    if command -v clear >/dev/null 2>&1; then
      clear
    else
      printf '\033[2J\033[H'
    fi
    render 0
  done
else
  render "$MUTATE"
fi
