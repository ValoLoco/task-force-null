#!/usr/bin/env bash
# Guided Task Force Null setup: harness, optional local LLM, API keys, bootstrap.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_LLM_DIR="${LOCAL_LLM_DIR:-/workspace/local-llm}"
WEIGHTS_FILE="${LOCAL_LLM_DIR}/weights/Inkling-2-Mini-AD-IQ1_S.gguf"
ENSURE_SCRIPT="${LOCAL_LLM_DIR}/ensure-running.sh"
MISSION_SLUG="${SETUP_MISSION_SLUG:-}"
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_LLM=0
SKIP_KEYS=0
SKIP_DEPLOY=0
CHOSEN_HARNESS=""
INSTALL_HARNESS=""
DEFAULT_SLUG="tf-null-squad"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --dry-run              Print actions without executing installers or downloads
  --non-interactive      Use env/flags only (no prompts)
  --skip-llm             Skip local llama.cpp step
  --skip-keys            Skip API key prompts
  --skip-deploy          Skip sync/detect/deploy bootstrap
  --harness NAME         hermes|pyagent|claude|grok|cursor|generic
  --mission-slug SLUG    Mission folder name for deploy-squad.sh
  --install-harness NAME Install hermes or pyagent if missing (non-interactive)

Env: SETUP_MISSION_SLUG, SETUP_HARNESS, LOCAL_LLM_DIR, INKLING_MODEL_URL
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-llm) SKIP_LLM=1; shift ;;
    --skip-keys) SKIP_KEYS=1; shift ;;
    --skip-deploy) SKIP_DEPLOY=1; shift ;;
    --harness) CHOSEN_HARNESS="$2"; shift 2 ;;
    --mission-slug) MISSION_SLUG="$2"; shift 2 ;;
    --install-harness) INSTALL_HARNESS="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "${SETUP_HARNESS:-}" && -z "$CHOSEN_HARNESS" ]] && CHOSEN_HARNESS="$SETUP_HARNESS"

log() { printf '[setup] %s\n' "$*"; }

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would run: $*"
  else
    log "run: $*"
    "$@"
  fi
}

prompt_yes_no() {
  local q="$1" default="${2:-y}"
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  local ans
  read -r -p "$q [${default}]: " ans || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

detect_harness_list() {
  local found=()
  if command -v hermes >/dev/null 2>&1 || [[ -n "${HERMES_HOME:-}" ]]; then
    found+=("hermes")
  fi
  if command -v pyagent >/dev/null 2>&1 || python3 -m pyagent --help >/dev/null 2>&1; then
    found+=("pyagent")
  fi
  if command -v claude >/dev/null 2>&1; then
    found+=("claude")
  fi
  if [[ -n "${GROK_BOT:-}" || -n "${XAI_API_KEY:-}" ]]; then
    found+=("grok")
  fi
  if [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]] || [[ -d "/cursor/stores" ]]; then
    found+=("cursor")
  fi
  if [[ ${#found[@]} -eq 0 ]]; then
  log "no harness detected"
  else
    log "detected harnesses: ${found[*]}"
  fi
  printf '%s\n' "${found[@]}"
}

choose_harness() {
  if [[ -n "$CHOSEN_HARNESS" ]]; then
    log "using harness: $CHOSEN_HARNESS"
    return 0
  fi
  mapfile -t detected < <(detect_harness_list)
  if [[ ${#detected[@]} -eq 0 ]]; then
    log "no harness installed"
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
      CHOSEN_HARNESS="${INSTALL_HARNESS:-generic}"
      return 0
    fi
    echo "Install Hermes Agent (h) or PyAgent (p), or skip (s)?"
    read -r pick || true
    case "${pick:-h}" in
      h|H) CHOSEN_HARNESS="hermes"; INSTALL_HARNESS="hermes" ;;
      p|P) CHOSEN_HARNESS="pyagent"; INSTALL_HARNESS="pyagent" ;;
      *) CHOSEN_HARNESS="generic"; return 0 ;;
    esac
    return 0
  fi
  if [[ ${#detected[@]} -eq 1 ]]; then
    CHOSEN_HARNESS="${detected[0]}"
    if ! prompt_yes_no "Use harness '${CHOSEN_HARNESS}'?" y; then
      CHOSEN_HARNESS="generic"
    fi
    return 0
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    CHOSEN_HARNESS="${detected[0]}"
    return 0
  fi
  local i=1
  for h in "${detected[@]}"; do
    echo "  $i) $h"
    ((i++)) || true
  done
  read -r -p "Select harness [1]: " sel || true
  sel="${sel:-1}"
  CHOSEN_HARNESS="${detected[$((sel - 1))]:-${detected[0]}}"
  log "selected: $CHOSEN_HARNESS"
}

install_harness_if_needed() {
  local target="${INSTALL_HARNESS:-}"
  [[ -z "$target" ]] && return 0
  case "$target" in
    hermes)
      if command -v hermes >/dev/null 2>&1; then
        log "hermes already installed"
        return 0
      fi
      if ! prompt_yes_no "Install Hermes Agent via pip?" y; then
        log "skipped hermes install"
        return 0
      fi
      run_cmd python3 -m pip install --user hermes-agent || log "hermes install failed (continuing)"
      ;;
    pyagent)
      if command -v pyagent >/dev/null 2>&1; then
        log "pyagent already installed"
        return 0
      fi
      if ! prompt_yes_no "Install PyAgent via pip?" y; then
        log "skipped pyagent install"
        return 0
      fi
      run_cmd python3 -m pip install --user pyagent || log "pyagent install failed (continuing)"
      ;;
  esac
}

llm_healthy() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 "http://127.0.0.1:8080/health" >/dev/null 2>&1 && return 0
    curl -fsS --max-time 2 "http://127.0.0.1:8080/v1/models" >/dev/null 2>&1 && return 0
  fi
  return 1
}

local_llm_ready() {
  [[ -f "$ENSURE_SCRIPT" && -f "$WEIGHTS_FILE" ]] && return 0
  llm_healthy && return 0
  return 1
}

setup_local_llm() {
  [[ "$SKIP_LLM" -eq 1 ]] && { log "skip local LLM"; return 0; }
  if local_llm_ready; then
    log "reusing existing local LLM at ${LOCAL_LLM_DIR}"
    if ! llm_healthy; then
      if [[ -f "$ENSURE_SCRIPT" ]]; then
        run_cmd bash "$ENSURE_SCRIPT"
      fi
    fi
    return 0
  fi
  if ! prompt_yes_no "Set up llama.cpp + Inkling 2 Mini (6.5 GB) on 127.0.0.1:8080?" n; then
    log "skipped local LLM setup"
    return 0
  fi
  local url="${INKLING_MODEL_URL:-https://huggingface.co/FUN-GAL/Inkling-2-Mini-gguf/resolve/main/Inkling-2-Mini-AD-IQ1_S.gguf}"
  run_cmd mkdir -p "${LOCAL_LLM_DIR}/weights"
  if [[ ! -f "$WEIGHTS_FILE" ]]; then
    run_cmd curl -fL --progress-bar -o "$WEIGHTS_FILE" "$url"
  else
    log "weights already present"
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would start llama-server on :8080"
    return 0
  fi
  if ! command -v llama-server >/dev/null 2>&1; then
    log "llama-server not found; install llama.cpp and re-run or use cloud keys only"
    return 0
  fi
  if ! llm_healthy; then
    nohup llama-server -m "$WEIGHTS_FILE" --host 127.0.0.1 --port 8080 \
      --load-mode mmap --lazy-mode on --n-gpu-layers 0 --ctx-size 2048 \
      >/dev/null 2>&1 &
    sleep 2
  fi
}

get_env_val() {
  local key="$1" file="${REPO_ROOT}/.env"
  [[ -f "$file" ]] || return 1
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2- || return 1
}

set_env_val() {
  local key="$1" val="$2" file="${REPO_ROOT}/.env"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    grep -v -E "^${key}=" "$file" >"$tmp" || true
  else
    : >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$val" >>"$tmp"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would set ${key}=*** in .env"
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file"
  chmod 600 "$file"
}

prompt_api_keys() {
  [[ "$SKIP_KEYS" -eq 1 ]] && { log "skip API keys"; return 0; }
  local keys=(NVIDIA_API_KEY OPENAI_API_KEY XAI_API_KEY)
  for key in "${keys[@]}"; do
    local cur=""
    cur="$(get_env_val "$key" 2>/dev/null || true)"
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
      [[ -n "$cur" ]] && log "${key} already set in .env"
      continue
    fi
    local prompt="Enter ${key} (leave empty to keep existing)"
    if [[ -n "$cur" ]]; then
      prompt="${prompt} [masked]"
    fi
    echo "$prompt"
    local val=""
    read -rs val || true
    echo ""
    [[ -z "$val" ]] && continue
    set_env_val "$key" "$val"
    log "${key} saved"
  done
}

source_env_safe() {
  local file="${REPO_ROOT}/.env"
  [[ -f "$file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$file" | sed 's/\r$//')
  set +a
}

deploy_harness_notes() {
  case "$CHOSEN_HARNESS" in
    hermes) log "Hermes: set workspace to ${REPO_ROOT}; see harnesses/hermes-agent.md" ;;
    pyagent) log "PyAgent: set project root to ${REPO_ROOT}; see harnesses/pyagent.md" ;;
    claude) log "Claude Code: open ${REPO_ROOT} as project root" ;;
    grok) log "Grok Bot: mount repo and load AGENTS.md" ;;
    cursor) log "Cursor: agent workspace at ${REPO_ROOT}" ;;
    *) log "Generic: load AGENTS.md and profiles from ${REPO_ROOT}" ;;
  esac
}

bootstrap_deploy() {
  [[ "$SKIP_DEPLOY" -eq 1 ]] && { log "skip bootstrap deploy"; return 0; }
  [[ -z "$MISSION_SLUG" ]] && MISSION_SLUG="$DEFAULT_SLUG"
  source_env_safe
  run_cmd env -C "$REPO_ROOT" bash ./scripts/sync-armory.sh --allow-offline
  run_cmd env -C "$REPO_ROOT" MISSION_SLUG="$MISSION_SLUG" bash ./scripts/detect-models.sh --slug "$MISSION_SLUG"
  if [[ -d "${REPO_ROOT}/missions/${MISSION_SLUG}" ]]; then
    log "mission ${MISSION_SLUG} already exists; skipping deploy-squad.sh"
  else
    run_cmd env -C "$REPO_ROOT" SKIP_SYNC_ARMORY=1 SKIP_DETECT_MODELS=1 \
      bash ./scripts/deploy-squad.sh "$MISSION_SLUG" "Task Force Null setup mission"
  fi
  run_cmd env -C "$REPO_ROOT" MISSION_SLUG="$MISSION_SLUG" bash ./scripts/start.sh
  deploy_harness_notes
}

main() {
  log "Task Force Null setup (repo=${REPO_ROOT})"
  [[ "$DRY_RUN" -eq 1 ]] && log "[dry-run] mode enabled (no installs, downloads, or .env writes)"
  choose_harness
  install_harness_if_needed
  setup_local_llm
  prompt_api_keys
  bootstrap_deploy
  log "setup complete"
}

main "$@"