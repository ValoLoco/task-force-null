#!/usr/bin/env bash
# Hardware-aware Inkling 2 Mini GGUF quant selection (sourced by setup.sh and tests).
# Public Hugging Face repo: unsloth/Inkling-2-Mini-GGUF
INKLING_HF_BASE="${INKLING_HF_BASE:-https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/main}"
INKLING_OS_HEADROOM_GB="${INKLING_OS_HEADROOM_GB:-4}"
INKLING_DISK_BUFFER_GB="${INKLING_DISK_BUFFER_GB:-2}"

inkling_quant_catalog() {
  cat <<'EOF'
48|UD-Q8_K_XL|Inkling-2-Mini-UD-Q8_K_XL.gguf|22.9
32|UD-Q4_K_M|Inkling-2-Mini-UD-Q4_K_M.gguf|16.6
24|UD-Q3_K_XL|Inkling-2-Mini-UD-Q3_K_XL.gguf|13.6
16|UD-Q2_K_XL|Inkling-2-Mini-UD-Q2_K_XL.gguf|9.1
12|UD-IQ1_S|Inkling-2-Mini-UD-IQ1_S.gguf|7.8
EOF
}

tfn_detect_ram_gb() {
  if [[ -n "${TFN_DETECT_RAM_GB:-}" ]]; then
    printf '%s' "$TFN_DETECT_RAM_GB"
    return 0
  fi
  local kb bytes mib gib
  if [[ -r /proc/meminfo ]]; then
    kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    if [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]]; then
      mib=$(( (kb + 512) / 1024 ))
      printf '%s' "$mib"
      return 0
    fi
  fi
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
    if [[ -n "$bytes" && "$bytes" =~ ^[0-9]+$ ]]; then
      gib=$(( (bytes + 536870911) / 1073741824 ))
      printf '%s' "$gib"
      return 0
    fi
  fi
  if command -v wmic.exe >/dev/null 2>&1; then
    mib="$(wmic.exe computersystem get TotalPhysicalMemory 2>/dev/null | awk 'NF==1 && $1 ~ /^[0-9]+$/ {print int($1/1048576)}' | head -n1)"
    if [[ -n "$mib" && "$mib" =~ ^[0-9]+$ ]]; then
      gib=$(( (mib + 512) / 1024 ))
      printf '%s' "$gib"
      return 0
    fi
  fi
  printf '0'
}

tfn_detect_vram_gb() {
  if [[ -n "${TFN_DETECT_VRAM_GB:-}" ]]; then
    printf '%s' "$TFN_DETECT_VRAM_GB"
    return 0
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    local mib gib
    mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')"
    if [[ -n "$mib" && "$mib" =~ ^[0-9]+$ ]]; then
      gib=$(( (mib + 512) / 1024 ))
      printf '%s' "$gib"
      return 0
    fi
  fi
  printf '0'
}

tfn_detect_disk_gb() {
  local target="${1:-.}"
  if [[ -n "${TFN_DETECT_DISK_GB:-}" ]]; then
    printf '%s' "$TFN_DETECT_DISK_GB"
    return 0
  fi
  local avail
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    avail="$(df -g "$target" 2>/dev/null | awk 'NR==2 {print $4}')"
  else
    avail="$(df -BG "$target" 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}')"
    if [[ -z "$avail" ]]; then
      avail="$(df -k "$target" 2>/dev/null | awk 'NR==2 {printf "%d", int($4/1048576)}')"
    fi
  fi
  [[ -n "$avail" && "$avail" =~ ^[0-9]+$ ]] || avail=0
  printf '%s' "$avail"
}

tfn_inkling_effective_mem_gb() {
  local ram vram max eff
  ram="$(tfn_detect_ram_gb)"
  vram="$(tfn_detect_vram_gb)"
  max="$ram"
  if [[ "$vram" -gt "$max" ]]; then
    max="$vram"
  fi
  printf '%s' "$max"
}

tfn_inkling_resolve_quant_token() {
  local raw="${1:-}"
  raw="${raw#UD-}"
  raw="${raw#AD-}"
  case "$raw" in
    IQ1_S|Q2_K_XL|Q3_K_XL|Q4_K_M|Q8_K_XL)
      printf 'UD-%s' "$raw"
      return 0
      ;;
    *)
      case "${1:-}" in
        UD-IQ1_S|UD-Q2_K_XL|UD-Q3_K_XL|UD-Q4_K_M|UD-Q8_K_XL)
          printf '%s' "${1}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

tfn_inkling_row_for_quant() {
  local want="$1"
  while IFS='|' read -r _ qtoken file _size; do
    [[ -z "$qtoken" ]] && continue
    if [[ "$qtoken" == "$want" ]]; then
      printf '%s|%s|%s\n' "$qtoken" "$file" "$_size"
      return 0
    fi
  done < <(inkling_quant_catalog)
  return 1
}

tfn_inkling_disk_need_gb() {
  local fsize="$1"
  awk -v s="$fsize" -v b="$INKLING_DISK_BUFFER_GB" 'BEGIN {printf "%d", int(s + b + 0.5)}'
}

tfn_inkling_select_quant() {
  local weights_dir="${1:-.}"
  if [[ -n "${INKLING_MODEL_URL:-}" ]]; then
    printf 'explicit_url'
    return 0
  fi
  local norm="" fsize="" disk need_disk row
  if [[ -n "${INKLING_QUANT:-}" ]]; then
    norm="$(tfn_inkling_resolve_quant_token "$INKLING_QUANT")" || {
      printf 'invalid_quant'
      return 1
    }
    row="$(tfn_inkling_row_for_quant "$norm")" || {
      printf 'invalid_quant'
      return 1
    }
    fsize="${row##*|}"
    disk="$(tfn_detect_disk_gb "$weights_dir")"
    need_disk="$(tfn_inkling_disk_need_gb "$fsize")"
    if [[ "$disk" -lt "$need_disk" ]]; then
      printf 'skip_low_disk'
      return 0
    fi
    printf '%s' "$norm"
    return 0
  fi
  local eff
  eff="$(tfn_inkling_effective_mem_gb)"
  while IFS='|' read -r min_gb qtoken _file sz; do
    [[ -z "$min_gb" ]] && continue
    if [[ "$eff" -ge "$min_gb" ]]; then
      norm="$qtoken"
      fsize="$sz"
      break
    fi
  done < <(inkling_quant_catalog)
  if [[ -z "$norm" ]]; then
    printf 'skip_low_memory'
    return 0
  fi
  disk="$(tfn_detect_disk_gb "$weights_dir")"
  need_disk="$(tfn_inkling_disk_need_gb "$fsize")"
  if [[ "$disk" -lt "$need_disk" ]]; then
    printf 'skip_low_disk'
    return 0
  fi
  printf '%s' "$norm"
}

tfn_inkling_model_url() {
  if [[ -n "${INKLING_MODEL_URL:-}" ]]; then
    printf '%s' "$INKLING_MODEL_URL"
    return 0
  fi
  local quant="$1" row file
  row="$(tfn_inkling_row_for_quant "$quant")" || return 1
  file="$(echo "$row" | cut -d'|' -f2)"
  printf '%s/%s' "$INKLING_HF_BASE" "$file"
}

tfn_inkling_weights_filename() {
  local quant="$1" row
  row="$(tfn_inkling_row_for_quant "$quant")" || return 1
  echo "$row" | cut -d'|' -f2
}

tfn_inkling_plan() {
  local weights_dir="${1:-.}"
  local ram vram eff disk sel url file reason fsize need_disk
  ram="$(tfn_detect_ram_gb)"
  vram="$(tfn_detect_vram_gb)"
  eff="$(tfn_inkling_effective_mem_gb)"
  disk="$(tfn_detect_disk_gb "$weights_dir")"
  if [[ -n "${INKLING_MODEL_URL:-}" ]]; then
    url="$INKLING_MODEL_URL"
    file="$(basename "$url")"
    printf 'action=download\nquant=\nfile=%s\nurl=%s\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
      "$file" "$url" "$ram" "$vram" "$eff" "$disk"
    return 0
  fi
  sel="$(tfn_inkling_select_quant "$weights_dir")" || {
    printf 'action=error\nreason=invalid_quant\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
      "$ram" "$vram" "$eff" "$disk"
    return 1
  }
  case "$sel" in
    skip_low_memory)
      reason="effective memory below 12 GB (max of RAM/VRAM minus ${INKLING_OS_HEADROOM_GB} GB OS headroom; RAM=${ram} GB, VRAM=${vram} GB)"
      printf 'action=skip\nreason=%s\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
        "$reason" "$ram" "$vram" "$eff" "$disk"
      return 0
      ;;
    skip_low_disk)
      reason="insufficient free disk for selected quant (need file size + ${INKLING_DISK_BUFFER_GB} GB buffer)"
      printf 'action=skip\nreason=%s\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
        "$reason" "$ram" "$vram" "$eff" "$disk"
      return 0
      ;;
    invalid_quant)
      printf 'action=error\nreason=invalid INKLING_QUANT\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
        "$ram" "$vram" "$eff" "$disk"
      return 1
      ;;
    explicit_url)
      url="$INKLING_MODEL_URL"
      file="$(basename "$url")"
      printf 'action=download\nquant=\nfile=%s\nurl=%s\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
        "$file" "$url" "$ram" "$vram" "$eff" "$disk"
      return 0
      ;;
    *)
      url="$(tfn_inkling_model_url "$sel")"
      file="$(tfn_inkling_weights_filename "$sel")"
      printf 'action=download\nquant=%s\nfile=%s\nurl=%s\nram_gb=%s\nvram_gb=%s\neffective_gb=%s\ndisk_gb=%s\n' \
        "$sel" "$file" "$url" "$ram" "$vram" "$eff" "$disk"
      return 0
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  tfn_inkling_plan "${1:-.}"
fi