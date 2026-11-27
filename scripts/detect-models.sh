#!/usr/bin/env bash
# Detect harness, probe model endpoints, write brain/models.md and squad bindings.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="${MISSION_SLUG:-}"
ENV_TARGET=""
AGENTS_FILE="${REPO_ROOT}/AGENTS.md"
MODELS_FILE="${REPO_ROOT}/brain/models.md"

usage() {
  echo "Usage: $0 [--slug SLUG] [--env-file PATH] [--repo-root PATH]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --env-file) ENV_TARGET="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; MODELS_FILE="${REPO_ROOT}/brain/models.md"; AGENTS_FILE="${REPO_ROOT}/AGENTS.md"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

env_is_active() {
  local f="$1" line
  [[ -f "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^ACTIVE=1[[:space:]]*$ ]] && return 0
  done <"$f"
  return 1
}

if [[ -z "$SLUG" ]]; then
  active_count=0
  while IFS= read -r envfile; do
    if env_is_active "$envfile"; then
      active_count=$((active_count + 1))
      if [[ -z "$SLUG" ]]; then
        SLUG="$(basename "$(dirname "$envfile")")"
      fi
    fi
  done < <(find "${REPO_ROOT}/missions" -mindepth 2 -maxdepth 2 -name 'squad.env' 2>/dev/null | sort)
  if [[ "$active_count" -gt 1 ]]; then
    echo "detect-models: warning: ${active_count} missions have ACTIVE=1; using ${SLUG}" >&2
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "detect-models: python3 not found; inventory probes skipped (install python3, or pkg install python on Termux)" >&2
fi

if [[ -z "$ENV_TARGET" && -n "$SLUG" ]]; then
  ENV_TARGET="${REPO_ROOT}/missions/${SLUG}/squad.env"
fi

mkdir -p "${REPO_ROOT}/brain"

detect_harness() {
  if [[ -n "${CURSOR_TRACE_ID:-}" || -n "${CURSOR_AGENT:-}" ]]; then
    echo "cursor"
  elif command -v pi >/dev/null 2>&1; then
    echo "pi"
  elif [[ -n "${CLAUDE_CODE:-}" || -n "${CLAUDE_CODE_SSE_PORT:-}" ]] || command -v claude >/dev/null 2>&1; then
    echo "claude-code"
  elif [[ -n "${HERMES_BIN:-}" || -n "${HERMES_HOME:-}" ]] || command -v hermes >/dev/null 2>&1; then
    echo "hermes"
  elif [[ -n "${GROK_BOT:-}" || -n "${XAI_API_KEY:-}" ]]; then
    echo "grok-bot"
  else
    echo "generic"
  fi
}

HARNESS="$(detect_harness)"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TMP_INV="$(mktemp)"
OVERRIDES_TMP="$(mktemp)"
trap 'rm -f "$TMP_INV" "$OVERRIDES_TMP"' EXIT
: >"$TMP_INV"
: >"$OVERRIDES_TMP"

if [[ -f "$MODELS_FILE" ]]; then
  awk '/^\| task_pattern \|/{h=1; next} h && /^\|/{if ($0 ~ /^\|[- ]+\|/) next; if ($0 ~ /^\| *\|/) exit; print}' "$MODELS_FILE" >"$OVERRIDES_TMP" || true
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP_INV" "$HARNESS" "$TS" <<'PY'
import json, os, sys
from urllib.request import Request, urlopen

inv_path, harness, ts = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []

def fetch(url):
    try:
        req = Request(url, headers={"User-Agent": "task-force-null-detect/1"})
        with urlopen(req, timeout=3) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception:
        return ""

def add_row(model_id, provider, caps, ctx, cost, lat, rel):
    if not model_id or model_id.startswith("("):
        return
    rows.append({
        "model_id": model_id,
        "provider": provider,
        "capabilities": caps,
        "context_tokens": str(ctx or ""),
        "cost_tier": str(cost or "3"),
        "latency_note": lat or "",
        "reliability_note": rel or "",
    })

for url, provider, parser in [
    ("http://127.0.0.1:8080/v1/models", "local_openai_compat", "openai"),
    ("http://127.0.0.1:8000/v1/models", "local_vllm", "openai"),
    ("http://127.0.0.1:11434/api/tags", "ollama", "ollama"),
]:
    body = fetch(url)
    if not body:
        continue
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        continue
    if parser == "openai":
        for item in data.get("data", data.get("models", [])) or []:
            mid = item.get("id") or item.get("name") or ""
            add_row(mid, provider, "code,tool_use,reasoning", "32000", "2", "local", "probe_ok")
    elif parser == "ollama":
        for item in data.get("models", []):
            mid = item.get("name") or item.get("model") or ""
            add_row(mid, provider, "code,fast_qa", "16000", "1", "local", "probe_ok")

providers = [
    ("openai", "openai", "code,reasoning,tool_use,vision", "128000", "4"),
    ("anthropic", "anthropic", "reasoning,tool_use,long_context", "200000", "4"),
    ("nvidia_nim", "nvidia_nim", "code,reasoning,tool_use", "128000", "3"),
    ("xai", "xai", "reasoning,tool_use", "128000", "3"),
    ("openrouter", "openrouter", "code,reasoning,tool_use,fast_qa", "128000", "3"),
]
checks = {
    "openai": lambda: os.environ.get("OPENAI_API_KEY"),
    "anthropic": lambda: os.environ.get("ANTHROPIC_API_KEY"),
    "nvidia_nim": lambda: os.environ.get("NVIDIA_API_KEY") or os.environ.get("NIM_BASE_URL"),
    "xai": lambda: os.environ.get("XAI_API_KEY"),
    "openrouter": lambda: os.environ.get("OPENROUTER_API_KEY"),
}
for key, prov, caps, ctx, cost in providers:
    if checks[key]():
        add_row(f"provider:{prov}", prov, caps, ctx, cost, "api_configured", "env_present")

with open(inv_path, "w", encoding="utf-8") as f:
    json.dump({"harness": harness, "ts": ts, "rows": rows}, f)
PY
fi

{
  echo "# Model Inventory"
  echo ""
  echo "Auto-generated by \`scripts/detect-models.sh\`. Edit Learned Overrides by hand; re-run detect to refresh inventory probes."
  echo ""
  echo "Last updated: ${TS}"
  echo ""
  echo "## Harness"
  echo ""
  echo "| field | value |"
  echo "|-------|-------|"
  echo "| harness | ${HARNESS} |"
  echo "| detected_at | ${TS} |"
  echo ""
  echo "## Inventory"
  echo ""
  echo "| model_id | provider | capabilities | context_tokens | cost_tier | latency_note | reliability_note |"
  echo "|----------|----------|--------------|----------------|-----------|--------------|------------------|"
} >"$MODELS_FILE"

if [[ -s "$TMP_INV" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP_INV" >>"$MODELS_FILE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
rows = data.get("rows", [])
if not rows:
    print("| (no models detected) | | | | | run probes or set provider API env | |")
else:
    for r in rows:
        print("| {model_id} | {provider} | {capabilities} | {context_tokens} | {cost_tier} | {latency_note} | {reliability_note} |".format(**r))
PY
else
  echo "| (no models detected) | | | | | run probes or set provider API env | |" >>"$MODELS_FILE"
fi

{
  echo ""
  echo "## Role Profile Defaults"
  echo ""
  echo "| role | required_capabilities | preferred_context |"
  echo "|------|----------------------|-------------------|"
  echo "| command | reasoning,long_context | 128000 |"
  echo "| lead | reasoning,tool_use | 64000 |"
  echo "| recon | fast_qa,tool_use | 32000 |"
  echo "| builder | code,tool_use | 64000 |"
  echo "| medic-qa | fast_qa,reasoning | 32000 |"
  echo "| comms | fast_qa | 16000 |"
  echo ""
  echo "## Learned Overrides"
  echo ""
  echo "| task_pattern | model_id | outcome | notes |"
  echo "|--------------|----------|---------|-------|"
} >>"$MODELS_FILE"

if [[ -s "$OVERRIDES_TMP" ]]; then
  cat "$OVERRIDES_TMP" >>"$MODELS_FILE"
else
  echo "| | | | |" >>"$MODELS_FILE"
fi

{
  echo ""
  echo "## Bootstrap Instructions"
  echo ""
  echo "Re-run \`./scripts/detect-models.sh\` after environment changes. Update Learned Overrides with observed outcomes."
} >>"$MODELS_FILE"

if [[ -n "$ENV_TARGET" && -f "$ENV_TARGET" ]] && [[ -s "$TMP_INV" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP_INV" "$ENV_TARGET" <<'PY'
import json, sys
from pathlib import Path

data = json.load(open(sys.argv[1], encoding="utf-8"))
env_path = Path(sys.argv[2])
rows = data.get("rows", [])
if not rows:
    sys.exit(0)

def score_for_role(role, row):
    caps = set((row.get("capabilities") or "").split(","))
    want = {
        "command": {"reasoning", "long_context"},
        "lead": {"reasoning", "tool_use"},
        "recon": {"fast_qa", "tool_use"},
        "builder": {"code", "tool_use"},
        "medic-qa": {"fast_qa", "reasoning"},
        "comms": {"fast_qa"},
    }.get(role, set())
    return len(caps & want)

roles = ["command", "lead", "recon", "builder", "medic-qa", "comms"]
bindings = {}
for role in roles:
    ranked = sorted(rows, key=lambda r: (-score_for_role(role, r), int(r.get("cost_tier") or "3")))
    if ranked:
        bindings[role] = ranked[0]["model_id"]

lines = env_path.read_text(encoding="utf-8").splitlines()
out = []
seen = set()
for line in lines:
    if line.startswith("MODEL_BIND_"):
        key = line.split("=", 1)[0]
        seen.add(key)
        role = key.replace("MODEL_BIND_", "").lower().replace("_", "-")
        if role in bindings:
            out.append(f"MODEL_BIND_{role.replace('-', '_')}={bindings[role]}")
        else:
            out.append(line)
    else:
        out.append(line)
for role, mid in bindings.items():
    key = f"MODEL_BIND_{role.replace('-', '_')}"
    if key not in seen:
        out.append(f"{key}={mid}")
env_path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
fi

BLOCK_TMP="$(mktemp)"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$TMP_INV" "$HARNESS" "$TS" >"$BLOCK_TMP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("<!-- BEGIN:MODEL_INVENTORY -->")
print("### Live model inventory (auto)")
print("")
print(f"- harness: {data.get('harness', 'generic')}")
print(f"- detected_at: {data.get('ts', '')}")
rows = data.get("rows", [])
print(f"- inventory_count: {len(rows)}")
if rows:
    print("- models:")
    for r in rows[:12]:
        print(f"  - {r.get('model_id')} ({r.get('provider')}) caps={r.get('capabilities')}")
else:
    print("- models: (none detected yet)")
print("<!-- END:MODEL_INVENTORY -->")
PY
fi

if [[ -f "$AGENTS_FILE" && -s "$BLOCK_TMP" ]]; then
  python3 - "$AGENTS_FILE" "$BLOCK_TMP" <<'PY'
import re, sys
from pathlib import Path
agents = Path(sys.argv[1])
block = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = agents.read_text(encoding="utf-8")
if "<!-- BEGIN:MODEL_INVENTORY -->" in text:
    text = re.sub(
        r"<!-- BEGIN:MODEL_INVENTORY -->.*?<!-- END:MODEL_INVENTORY -->",
        block,
        text,
        count=1,
        flags=re.DOTALL,
    )
else:
    text = text.rstrip() + "\n\n" + block + "\n"
agents.write_text(text, encoding="utf-8")
PY
fi

rm -f "$BLOCK_TMP"

echo "Wrote ${MODELS_FILE}"
[[ -n "$ENV_TARGET" ]] && echo "Updated bindings in ${ENV_TARGET}"
echo "Harness: ${HARNESS}"