#!/usr/bin/env bash
# Guided Task Force Null setup: harness, optional local LLM, API keys, bootstrap.
# Linux, macOS, Windows Git Bash / WSL. Native Windows: scripts/setup.ps1 or setup.bat.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_LLM_DIR="${LOCAL_LLM_DIR:-/workspace/local-llm}"
WEIGHTS_FILE="${LOCAL_LLM_DIR}/weights/Inkling-2-Mini-AD-IQ1_S.gguf"
ENSURE_SCRIPT="${LOCAL_LLM_DIR}/ensure-running.sh"
MISSION_SLUG="${SETUP_MISSION_SLUG:-}"
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_LLM=0
INSTALL_LLM=0
SKIP_KEYS=0
SKIP_DEPLOY=0
CHOSEN_HARNESS=""
INSTALL_HARNESS=""
DEFAULT_SLUG="setup-mission"
SETUP_OS=""
SETUP_PKG=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --dry-run              Print actions without executing installers or downloads
  --non-interactive      Use env/flags only (no prompts)
  --skip-llm             Skip local LLM install (no download)
  --install-llm          Accept Inkling 2 Mini download (required with --non-interactive)
  --skip-keys            Skip API key prompts
  --skip-deploy          Skip sync/detect/deploy bootstrap
  --harness NAME         hermes|pi|claude|grok-bot|cursor|generic (grok aliases to grok-bot)
  --mission-slug SLUG    Mission folder name for deploy-squad.sh
  --install-harness NAME Install hermes or pi if missing (non-interactive)

Env: SETUP_MISSION_SLUG, SETUP_HARNESS, SETUP_BASH_ONLY=1, LOCAL_LLM_DIR, INKLING_MODEL_URL,
     TFN_LLM_PROBE_URL, TFN_LLM_PROBE_HOST, TFN_LLM_PROBE_PORT, TFN_HARNESS,
     TFN_LLM_MODEL_SCAN=0 (skip on-disk model scan), TFN_LLM_SEARCH_DIRS (colon-separated roots)
Windows Git Bash: prefers delegation to scripts/setup.ps1 (set SETUP_BASH_ONLY=1 to stay in bash).
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --skip-llm) SKIP_LLM=1; shift ;;
    --install-llm) INSTALL_LLM=1; shift ;;
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
[[ -n "${TFN_HARNESS:-}" && -z "$CHOSEN_HARNESS" ]] && CHOSEN_HARNESS="$TFN_HARNESS"

normalize_harness_token() {
  case "${1:-}" in
    grok) printf 'grok-bot' ;;
    "") printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

[[ -n "$CHOSEN_HARNESS" ]] && CHOSEN_HARNESS="$(normalize_harness_token "$CHOSEN_HARNESS")"

tfn_llm_probe_host() {
  printf '%s' "${TFN_LLM_PROBE_HOST:-127.0.0.1}"
}

tfn_llm_probe_port() {
  printf '%s' "${TFN_LLM_PROBE_PORT:-8080}"
}

tfn_llm_probe_health_url() {
  if [[ -n "${TFN_LLM_PROBE_URL:-}" ]]; then
    printf '%s' "$TFN_LLM_PROBE_URL"
    return
  fi
  printf 'http://%s:%s/health' "$(tfn_llm_probe_host)" "$(tfn_llm_probe_port)"
}

tfn_llm_probe_models_url() {
  printf 'http://%s:%s/v1/models' "$(tfn_llm_probe_host)" "$(tfn_llm_probe_port)"
}

tfn_llm_probe_display_base() {
  printf 'http://%s:%s' "$(tfn_llm_probe_host)" "$(tfn_llm_probe_port)"
}

log() { printf '[setup] %s\n' "$*" >&2; }

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would run: $*"
  else
    log "run: $*"
    "$@"
  fi
}

run_in_repo() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would run in ${REPO_ROOT}: $*"
  else
    log "run in ${REPO_ROOT}: $*"
    ( cd "$REPO_ROOT" && "$@" )
  fi
}

detect_os() {
  if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *com.termux* ]]; then
    echo "termux"
    return
  fi
  local u
  u="$(uname -s 2>/dev/null || echo unknown)"
  case "$u" in
    Linux*) echo "linux" ;;
    Darwin*) echo "darwin" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows_gitbash" ;;
    *) echo "unknown" ;;
  esac
}

detect_pkg_manager() {
  local os="${SETUP_OS:-$(detect_os)}"
  case "$os" in
    termux)
      command -v pkg >/dev/null 2>&1 && { echo "pkg"; return 0; }
      echo "none"
      ;;
    darwin)
      command -v brew >/dev/null 2>&1 && { echo "brew"; return 0; }
      echo "none"
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then echo "apt"; return 0; fi
      if command -v dnf >/dev/null 2>&1; then echo "dnf"; return 0; fi
      if command -v pacman >/dev/null 2>&1; then echo "pacman"; return 0; fi
      echo "none"
      ;;
    windows_gitbash)
      if command -v winget.exe >/dev/null 2>&1; then echo "winget"; return 0; fi
      if command -v choco.exe >/dev/null 2>&1; then echo "choco"; return 0; fi
      echo "none"
      ;;
    *) echo "none" ;;
  esac
}

maybe_delegate_windows_ps1() {
  [[ "$(detect_os)" == "windows_gitbash" ]] || return 1
  [[ "${SETUP_BASH_ONLY:-0}" == "1" ]] && return 1
  local ps1="${REPO_ROOT}/scripts/setup.ps1"
  [[ -f "$ps1" ]] || return 1
  local ps_exe=""
  if command -v pwsh.exe >/dev/null 2>&1; then
    ps_exe="pwsh.exe"
  elif command -v powershell.exe >/dev/null 2>&1; then
    ps_exe="powershell.exe"
  fi
  [[ -n "$ps_exe" ]] || return 1
  log "Windows Git Bash: delegating to setup.ps1 via ${ps_exe}"
  local -a args=(-ExecutionPolicy Bypass -NoProfile -File "$ps1")
  [[ "$DRY_RUN" -eq 1 ]] && args+=(-DryRun)
  [[ "$NON_INTERACTIVE" -eq 1 ]] && args+=(-NonInteractive)
  [[ "$SKIP_LLM" -eq 1 ]] && args+=(-SkipLlm)
  [[ "$INSTALL_LLM" -eq 1 ]] && args+=(-InstallLlm)
  [[ "$SKIP_KEYS" -eq 1 ]] && args+=(-SkipKeys)
  [[ "$SKIP_DEPLOY" -eq 1 ]] && args+=(-SkipDeploy)
  [[ -n "$CHOSEN_HARNESS" ]] && args+=(-Harness "$CHOSEN_HARNESS")
  [[ -n "$MISSION_SLUG" ]] && args+=(-MissionSlug "$MISSION_SLUG")
  [[ -n "$INSTALL_HARNESS" ]] && args+=(-InstallHarness "$INSTALL_HARNESS")
  exec "$ps_exe" "${args[@]}"
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
  if command -v pi >/dev/null 2>&1; then
    found+=("pi")
  fi
  if command -v claude >/dev/null 2>&1; then
    found+=("claude")
  fi
  if [[ -n "${GROK_BOT:-}" || -n "${XAI_API_KEY:-}" ]]; then
    found+=("grok-bot")
  fi
  if [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]] || [[ -d "/cursor/stores" ]]; then
    found+=("cursor")
  fi
  if [[ ${#found[@]} -eq 0 ]]; then
    log "no harness detected"
  else
    log "detected harnesses: ${found[*]}"
  fi
  if [[ ${#found[@]} -gt 0 ]]; then
    printf '%s\n' "${found[@]}"
  fi
}

choose_harness() {
  if [[ -n "$CHOSEN_HARNESS" ]]; then
    CHOSEN_HARNESS="$(normalize_harness_token "$CHOSEN_HARNESS")"
    log "using harness: $CHOSEN_HARNESS"
    return 0
  fi
  detected=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && detected+=("$line")
  done < <(detect_harness_list)
  if [[ ${#detected[@]} -eq 0 ]]; then
    log "no harness installed"
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
      CHOSEN_HARNESS="${INSTALL_HARNESS:-generic}"
      return 0
    fi
    echo "Install Hermes Agent (h), Pi Coding Agent (p), or skip (s)?"
    read -r pick || true
    case "${pick:-h}" in
      h|H) CHOSEN_HARNESS="hermes"; INSTALL_HARNESS="hermes" ;;
      p|P) CHOSEN_HARNESS="pi"; INSTALL_HARNESS="pi" ;;
      *) CHOSEN_HARNESS="generic"; return 0 ;;
    esac
    return 0
  fi
  if [[ ${#detected[@]} -eq 1 ]]; then
    CHOSEN_HARNESS="$(normalize_harness_token "${detected[0]}")"
    if ! prompt_yes_no "Use harness '${CHOSEN_HARNESS}'?" y; then
      CHOSEN_HARNESS="generic"
    fi
    return 0
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    CHOSEN_HARNESS="$(normalize_harness_token "${detected[0]}")"
    return 0
  fi
  local i=1
  for h in "${detected[@]}"; do
    echo "  $i) $h"
    ((i++)) || true
  done
  read -r -p "Select harness [1]: " sel || true
  sel="${sel:-1}"
  CHOSEN_HARNESS="$(normalize_harness_token "${detected[$((sel - 1))]:-${detected[0]}}")"
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
    pi)
      if command -v pi >/dev/null 2>&1; then
        log "pi already installed"
        return 0
      fi
      if ! prompt_yes_no "Install Pi Coding Agent (pi.dev)?" y; then
        log "skipped pi install"
        return 0
      fi
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[dry-run] would run: curl -fsSL https://pi.dev/install.sh | sh"
        log "[dry-run] would run: pi install npm:pi-agents"
        return 0
      fi
      if [[ "$SETUP_OS" == "windows_gitbash" ]]; then
        log "on Windows Git Bash, run: irm https://pi.dev/install.ps1 | iex  (or use setup.ps1)"
        return 0
      fi
      curl -fsSL https://pi.dev/install.sh | sh
      command -v pi >/dev/null 2>&1 && pi install npm:pi-agents || log "pi install failed (continuing)"
      ;;
  esac
}

llama_install_hint() {
  case "$SETUP_OS" in
    darwin)
      log "Install llama.cpp: brew install llama.cpp (Metal or CPU)"
      ;;
    linux)
      case "$SETUP_PKG" in
        apt) log "Install llama-server: apt llama.cpp package or build from github.com/ggml-org/llama.cpp" ;;
        pacman) log "Install llama-server: pacman -S llama.cpp (if available) or build from source" ;;
        dnf) log "Install llama-server: build from github.com/ggml-org/llama.cpp (cmake)" ;;
        *) log "Install llama-server: build from github.com/ggml-org/llama.cpp" ;;
      esac
      ;;
    windows_gitbash)
      log "Install llama-server: winget install ggml.llamacpp  OR  choco install llama-cpp"
      ;;
    *) log "Install llama-server from https://github.com/ggml-org/llama.cpp" ;;
  esac
}

try_install_llama() {
  command -v llama-server >/dev/null 2>&1 && return 0
  case "$SETUP_OS" in
    darwin)
      if [[ "$SETUP_PKG" == "brew" ]] && prompt_yes_no "Install llama.cpp via Homebrew now?" y; then
        run_cmd brew install llama.cpp
      fi
      ;;
    linux)
      if [[ "$SETUP_PKG" == "apt" ]] && prompt_yes_no "Attempt apt install for llama.cpp (if packaged)?" n; then
        run_cmd sudo apt-get update && run_cmd sudo apt-get install -y llama.cpp 2>/dev/null || llama_install_hint
      else
        llama_install_hint
      fi
      ;;
    *)
      llama_install_hint
      ;;
  esac
}

llm_healthy() {
  if command -v curl >/dev/null 2>&1; then
    probe_url "$(tfn_llm_probe_health_url)" && return 0
    probe_url "$(tfn_llm_probe_models_url)" && return 0
  fi
  return 1
}

note_llm_skipped() {
  log "skipped local LLM install"
  log "API keys (in .env) or a remote inference endpoint will be needed to run models"
}

probe_url() {
  local url="$1"
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS --max-time 2 "$url" >/dev/null 2>&1
}

first_gguf() {
  local root="$1" hit
  [[ -d "$root" ]] || return 1
  hit="$(find "$root" -maxdepth 4 -type f -name '*.gguf' 2>/dev/null | head -n 1 || true)"
  [[ -n "$hit" ]] || return 1
  printf '%s\n' "$hit"
}

detect_running_server() {
  if probe_url "$(tfn_llm_probe_models_url)" || probe_url "$(tfn_llm_probe_health_url)"; then
    printf '%s\n' "$(tfn_llm_probe_display_base)|llama-server / Inkling"
    return 0
  fi
  if probe_url "http://127.0.0.1:11434/api/tags" || probe_url "http://127.0.0.1:11434/v1/models"; then
    printf '%s\n' "http://127.0.0.1:11434|Ollama"
    return 0
  fi
  if probe_url "http://127.0.0.1:8000/v1/models"; then
    printf '%s\n' "http://127.0.0.1:8000|vLLM"
    return 0
  fi
  return 1
}

detect_installed_model() {
  local root hit dir scan_ollama=1
  if [[ "${TFN_LLM_MODEL_SCAN:-1}" == "0" ]]; then
    return 1
  fi
  if [[ -n "${TFN_LLM_SEARCH_DIRS+x}" ]]; then
    scan_ollama=0
    if [[ -z "${TFN_LLM_SEARCH_DIRS}" ]]; then
      return 1
    fi
    local IFS=':'
    for dir in ${TFN_LLM_SEARCH_DIRS}; do
      [[ -n "$dir" ]] || continue
      if hit="$(first_gguf "$dir")"; then
        printf '%s\n' "$hit"
        return 0
      fi
    done
    return 1
  fi
  for root in \
    "$LOCAL_LLM_DIR" \
    "/workspace/local-llm" \
    "${HOME}/local-llm" \
    "${HOME}/.cache/llama.cpp" \
    "${HOME}/models" \
    "${HOME}/Models" \
    "${HOME}/.cache/huggingface"
  do
    [[ -n "$root" ]] || continue
    if hit="$(first_gguf "$root")"; then
      printf '%s\n' "$hit"
      return 0
    fi
  done
  if [[ "$scan_ollama" -eq 1 ]] && [[ -d "${HOME}/.ollama/models/manifests" ]]; then
    hit="$(find "${HOME}/.ollama/models/manifests" -maxdepth 5 -type f 2>/dev/null | head -n 1 || true)"
    if [[ -n "$hit" ]]; then
      printf '%s\n' "$hit"
      return 0
    fi
  fi
  return 1
}

accept_llm_install() {
  local ans
  if [[ "$INSTALL_LLM" -eq 1 ]]; then
    return 0
  fi
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    return 1
  fi
  printf '%s' "Install Inkling 2 Mini (6.5 GB AD IQ1_S quant) on 127.0.0.1:8080? [y/N]: " >&2
  read -r ans || true
  [[ "${ans:-N}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

setup_local_llm() {
  local detected path label
  if [[ "$SKIP_LLM" -eq 1 ]]; then
    note_llm_skipped
    return 0
  fi
  if detected="$(detect_running_server)"; then
    path="${detected%%|*}"
    label="${detected#*|}"
    log "detected local model server at ${path} (${label}); skipping local LLM install"
    return 0
  fi
  if path="$(detect_installed_model)"; then
    log "detected local model at ${path}; skipping local LLM install"
    return 0
  fi
  if ! accept_llm_install; then
    note_llm_skipped
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
    try_install_llama
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
  if [[ "$SETUP_OS" != "windows_gitbash" ]]; then
    chmod 600 "$file" 2>/dev/null || true
  fi
}

prompt_api_keys() {
  [[ "$SKIP_KEYS" -eq 1 ]] && { log "skip API keys"; return 0; }
  local keys=(NVIDIA_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY XAI_API_KEY)
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
    pi) log "Pi: set workspace to ${REPO_ROOT}; see harnesses/pi-agent.md" ;;
    claude) log "Claude Code: open ${REPO_ROOT} as project root" ;;
    grok-bot|grok) log "Grok Bot: mount repo and load AGENTS.md" ;;
    cursor) log "Cursor: agent workspace at ${REPO_ROOT}" ;;
    *) log "Generic: load AGENTS.md and profiles from ${REPO_ROOT}" ;;
  esac
}

bootstrap_deploy() {
  [[ "$SKIP_DEPLOY" -eq 1 ]] && { log "skip bootstrap deploy"; return 0; }
  [[ -z "$MISSION_SLUG" ]] && MISSION_SLUG="$DEFAULT_SLUG"
  source_env_safe
  run_in_repo bash ./scripts/sync-armory.sh --allow-offline
  local dm_args=(env MISSION_SLUG="$MISSION_SLUG")
  [[ -n "$CHOSEN_HARNESS" ]] && dm_args+=(TFN_HARNESS="$CHOSEN_HARNESS")
  dm_args+=(bash ./scripts/detect-models.sh --slug "$MISSION_SLUG")
  [[ -n "$CHOSEN_HARNESS" ]] && dm_args+=(--harness "$CHOSEN_HARNESS")
  run_in_repo "${dm_args[@]}"
  if [[ -d "${REPO_ROOT}/missions/${MISSION_SLUG}" ]]; then
    log "mission ${MISSION_SLUG} already exists; skipping deploy-squad.sh"
  else
    run_in_repo env SKIP_SYNC_ARMORY=1 SKIP_DETECT_MODELS=1 \
      bash ./scripts/deploy-squad.sh "$MISSION_SLUG" "Task Force Null setup mission"
  fi
  run_in_repo env MISSION_SLUG="$MISSION_SLUG" bash ./scripts/start.sh
  deploy_harness_notes
}

main() {
  SETUP_OS="$(detect_os)"
  SETUP_PKG="$(detect_pkg_manager)"
  log "Task Force Null setup (repo=${REPO_ROOT}, os=${SETUP_OS}, pkg=${SETUP_PKG})"
  if [[ "$SETUP_OS" == "termux" ]]; then
    log "Termux detected. Skip setup.sh on Android."
    log "sudo apt-get, /workspace/local-llm, and systemd do not apply here."
    log "Clone into \$HOME. /sdcard is noexec."
    log "Then run: ./scripts/sync-armory.sh --allow-offline"
    log "         ./scripts/detect-models.sh --slug setup-mission"
    log "         ./scripts/start.sh"
    log "Inference: pkg install llama-cpp and a 1B to 4B Q4_K_M model on 127.0.0.1:8080, or tunnel a remote llama-server there."
    log "The 6.88 GB Inkling 2 Mini quant is too heavy for a phone."
    log "Harness: pkg install nodejs git, then npm install -g --ignore-scripts @earendil-works/pi-coding-agent and pi install npm:pi-agents (Node 24+, node:sqlite)."
    exit 0
  fi
  maybe_delegate_windows_ps1 || true
  [[ "$DRY_RUN" -eq 1 ]] && log "[dry-run] mode enabled (no installs, downloads, or .env writes)"
  choose_harness
  install_harness_if_needed
  setup_local_llm
  prompt_api_keys
  bootstrap_deploy
  log "setup complete"
}

main "$@"