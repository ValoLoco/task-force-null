```text
==========================================================================
  ____  _   _ _____ _   _    _  _____ _   _ ____     _
 | __ )| | | | ____| \ | |  / \|_   _| | | |  _ \   / \
 |  _ \| | | |  _| |  \| | / _ \ | | | | | | |_) | / _ \
 | |_) | |_| | |___| |\  |/ ___ \| | | |_| |  _ < / ___ \
 |____/ \___/|_____|_| \_/_/   \_\_|  \___/|_| \_\_/   \_\

                     BUENATURA

  _____ _   ___ _  __   ___ ___  ___  ___ ___   _  _ _   _ _    _
 |_   _/_\ / __| |/ /  | __/ _ \| _ \/ __| __| | \| | | | | |  | |
   | |/ _ \\__ \ ' <   | _| (_) |   / (__| _|  | .' | |_| | |__| |__
   |_/_/ \_\___/_|\_\  |_| \___/|_|_\\___|___| |_|\_|\___/|____|____|
                     TASK FORCE NULL
==========================================================================
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Task Force Null (TASK FORCE NULL)

Released under the [MIT License](LICENSE) (Copyright 2026 Valentin Kranz).

Lean, redeployable **Special Forces AI agent team** template ([`ValoLoco/task-force-null`](https://github.com/ValoLoco/task-force-null)). One five-operator squad plus Command for multi-squad work, shared `brain/`, swappable `missions/<slug>/` per deployment.

## Quick install (one line)

Clone once, then run setup for your OS.

| OS | One-line setup |
|----|----------------|
| **Linux / macOS** | `git clone --depth 1 https://github.com/ValoLoco/task-force-null.git && cd task-force-null && ./scripts/setup.sh` |
| **Windows PowerShell** | `git clone --depth 1 https://github.com/ValoLoco/task-force-null.git; cd task-force-null; .\scripts\setup.ps1` |
| **Windows cmd / double-click** | Clone the repo, then run `scripts\setup.bat` (forwards to `setup.ps1`) |

Dry run (no installs or `.env` writes): add `--dry-run` on bash or `-DryRun` on PowerShell.

**Termux (Android), inside this quick install:**

- Install Termux from F-Droid or GitHub (the Play Store build is not the one to use).
- Skip `setup.sh`. `sudo apt-get`, `/workspace/local-llm`, and `systemd` do not apply.
- Clone into Termux `$HOME`. `/sdcard` is `noexec`.
- On the built-in `setup-mission`, run `./scripts/sync-armory.sh --allow-offline`, `./scripts/detect-models.sh --slug setup-mission`, and `./scripts/start.sh`.
- Inference: `pkg install llama-cpp` and a small 1B to 4B `Q4_K_M` model (`llama-server` on `:8080`), or an SSH/Tailscale tunnel of a remote `llama-server` onto `127.0.0.1:8080`. The 6.88 GB Inkling 2 Mini quant is too heavy for a phone.
- Harness: `pkg install nodejs git`, then `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` and `pi install npm:pi-agents`. `pi`, `pi-agents`, and Pi Durable run on Termux Node 24+ with Node's built-in `node:sqlite`.
- Persistence: no `systemd`. Use `tmux` or `termux-services` (`runit`) plus `termux-wake-lock`. Android 12+ Phantom Process Killer can still stop background work.

## Grok Bot template

Grok Bot users can add **Task Force Null Command** to their profiles via the [published Grok Bot template](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I).

**One line:** Import the [published Task Force Null Command template](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I) in Grok Bot and open its chat to start the built-in onboarding flow.

| On import | Detail |
|-----------|--------|
| Bootstrap skill | `task-force-null-getting-started` runs automatically |
| Repo + harness | Clones [`ValoLoco/task-force-null`](https://github.com/ValoLoco/task-force-null); installs Pi Coding Agent (`pi`, `pi-agents`) |
| TOC group | Spawns **Lead**, **Recon**, **Builder**, **Medic QA**, and **Comms** alongside **Command** in the 6-bot **Task Force Null TOC** group channel |
| Standing routines | Wires **TOC Status Check** and paused-by-default **Autonomous Mode Loop** in place of `systemd` |
| Inference | Grok Bot native inference by default; onboarding may prompt for an extra API key (NVIDIA NIM, OpenAI, xAI, Anthropic, or other) and/or local Inkling via `llama.cpp` |
| Sidebar | Creating a dedicated **Task Force Null** sidebar section takes one manual step in the Grok Bot sidebar UI |

## One-line deploy prompt (existing harness, no setup)

Copy into any AI harness (Hermes, Pi, Grok Bot, Claude, Cursor, etc.) when you **do not** run `setup.sh`:

```text
You are Task Force Null: read AGENTS.md, brain/doctrine.md, and profiles/{lead,recon,builder,medic-qa,comms,command}.md; clone https://github.com/ValoLoco/task-force-null into this project; run scripts/start.sh and complete missions/setup-mission/ first (Command is the only user-facing agent; other operators never speak to the user); then scripts/deploy-squad.sh <slug> "<one-line objective>" (syncs armory/ecc via scripts/sync-armory.sh) for follow-on missions; operate within missions/<slug>/mission.md limits with one board.md owner per task; use scripts/router.py for routing; ECC is read-only (prefer /workspace/ecc/search.sh online, armory/ecc offline, one skill at a time, never copy ECC into the repo, never run ECC installers or hooks); human approval for all external publish and destructive actions; Builder -> medic-qa -> comms -> Command -> human for external packages.
```

## Special Forces parallel

| Profile | MOS parallel | Function |
|---------|----------------|----------|
| `command.md` | Colonel / group | Multi-squad intent, deconfliction, playbook promotion |
| `lead.md` | 18A | Commander's Intent, routing, go/no-go |
| `recon.md` | 18F | Verified intel, risks, open questions |
| `builder.md` | 18B/18C | Minimum viable deliverables in scope |
| `medic-qa.md` | 18D | Evidence-based verification, 3-line AAR |
| `comms.md` | 18E | Human-facing packaging, approval gates |

Profiles live in `profiles/` and stay **domain-agnostic**. Project intent lives under `missions/`. Unit soul and chain of command: **`AGENTS.md`**.

## Guided setup flow (`setup.sh` / `setup.ps1`)

Interactive first-time bootstrap. Idempotent and safe to re-run (preserves existing `.env` keys when prompts are left empty).

| Step | What happens |
|------|----------------|
| 1. Harness detection | Detects Hermes, **Pi Coding Agent** (`pi`), Claude, Grok, Cursor (see [`harnesses/`](harnesses/README.md)). |
| 2. Harness install (optional) | **Hermes:** `pip install --user hermes-agent`. **Pi:** Linux/macOS `curl -fsSL https://pi.dev/install.sh \| sh` then `pi install npm:pi-agents` (pulls durable sub-agents); Windows `irm https://pi.dev/install.ps1 \| iex` then `pi install npm:pi-agents`. |
| 3. Local LLM (opt-in) | Detect a running server on `127.0.0.1:8080` (llama-server / Inkling), `:11434` (Ollama), or `:8000` (vLLM), or an installed model under `LOCAL_LLM_DIR`, `/workspace/local-llm`, `~/local-llm`, `~/.cache/llama.cpp`, common `*.gguf` paths, or Ollama manifests. If one is found, setup skips the download and prints the endpoint or path. If none is found, setup asks before **Inkling 2 Mini (6.5 GB AD IQ1_S quant)**. The prompt is `[y/N]` and the default is **No**. Nothing downloads unless you accept. `--non-interactive` without `--install-llm` declines. `--skip-llm` skips the step. Declining continues setup and states that API keys in `.env` or a remote inference endpoint are required, then moves on to API keys and squad bootstrap. |
| 4. API keys (optional) | Masked prompts for `NVIDIA_API_KEY`, `OPENAI_API_KEY`, `XAI_API_KEY` into gitignored `.env` (empty input keeps existing values; `chmod 600` on Unix). |
| 5. Bootstrap | `sync-armory.sh --allow-offline`, `detect-models.sh`, `deploy-squad.sh`, `start.sh`. |

| Mode | Usage |
|------|--------|
| Dry run | `./scripts/setup.sh --dry-run` or `.\scripts\setup.ps1 -DryRun` |
| CI / automation | `./scripts/setup.sh --non-interactive --skip-llm --harness cursor --mission-slug my-squad` |
| Download Inkling in CI | Add `--install-llm` (or `-InstallLlm`). Without it, non-interactive setup declines the 6.5 GB quant. |
| Skip bootstrap | `--skip-deploy` / `-SkipDeploy` |

On **Windows Git Bash**, `setup.sh` delegates to `setup.ps1` when PowerShell is available (`SETUP_BASH_ONLY=1` forces bash-only).

Secrets never print to logs. See [`.env.example`](.env.example).

## Cross-platform notes

| Topic | Linux | macOS | Windows |
|-------|-------|-------|---------|
| Setup entry | `./scripts/setup.sh` | same | `setup.ps1`, `setup.bat`, or Git Bash `setup.sh` |
| Package managers | `apt-get`, `dnf`, `pacman` (auto-detected) | `brew` | `winget`, `choco` |
| Pi install | `curl -fsSL https://pi.dev/install.sh \| sh` + `pi install npm:pi-agents` | same | `irm https://pi.dev/install.ps1 \| iex` + `pi install npm:pi-agents` |
| `llama.cpp` binary | Distro package or cmake build; binary `llama-server` | `brew install llama.cpp` (Metal or CPU) | `winget install ggml.llamacpp` or `choco install llama-cpp` / `llama-server.exe` |
| Line endings | `.gitattributes`: `*.sh` / `*.py` LF; `*.ps1` / `*.bat` CRLF | same | same |
| Bootstrap scripts | Native bash | Native bash | PowerShell calls `bash` for `sync-armory`, `detect-models`, `deploy-squad` when Git Bash is installed |

Termux details are in **Quick install** above (`$HOME`, `pkg`, no `systemd`, skip the heavy quant). Do not run `setup.sh` on Android.

## Fast clone / clone size

| Goal | Command |
|------|---------|
| Full offline-ready clone (shallow) | `git clone --depth 1 https://github.com/ValoLoco/task-force-null.git` |
| Lightweight online-only sparse clone (skips `armory/ecc/` blobs until needed) | `git clone --filter=blob:none --sparse https://github.com/ValoLoco/task-force-null.git && cd task-force-null && git sparse-checkout set --no-cone '/*' '!/armory/ecc/'` |

`armory/ecc/**` is marked `linguist-vendored` in `.gitattributes` so GitHub collapses vendored diffs and keeps language stats clean while the full offline copy stays in the repo.

Restore a full offline armory anytime with `./scripts/sync-armory.sh` or `git sparse-checkout disable` after a sparse clone.

## ECC armory (`armory/ecc/`)

The full [affaan-m/ECC](https://github.com/affaan-m/ECC) repository is vendored under **`armory/ecc/`** for **offline** use (agents, skills, docs, tests, scripts). The synced commit is recorded in `armory/ecc/PINNED_SHA`.

| Rule | Detail |
|------|--------|
| Online deploy | `./scripts/deploy-squad.sh` runs `scripts/sync-armory.sh --allow-offline` unless `SKIP_SYNC_ARMORY=1` |
| Manual sync | `./scripts/sync-armory.sh` (add `--allow-offline` to keep local copy if upstream is down) |
| Discovery online | Prefer `/workspace/ecc/search.sh <query>` when the host armory is mounted |
| Discovery offline | Browse and read skills under `armory/ecc/` one at a time |
| Prohibited | Never run ECC `install.sh`, `install.ps1`, hooks, or copy skill bodies into `brain/` or missions |

Use shallow or sparse clone (above) when you only need the squad template online first; sync or sparse-checkout restore when you need offline ECC.

Medic QA blocks merges that embed ECC skill bodies. Lead logs which ECC skill was consulted when it influenced scope or implementation.

## Verification (`scripts/verify.sh`)

One command runs shell syntax checks, router and setup smoke tests, profile line limits, branding checks, and an owned-file em-dash scan (excluding `armory/ecc/`). Default `VERIFY_SKIP_ONLINE_SYNC=1` avoids upstream ECC sync during verify so CI and offline runs stay deterministic; unset it locally to exercise live `sync-armory.sh`. `./scripts/verify.sh` does not require Rust/Cargo. Native GPUI coverage is in `scripts/test_toc_gpui.sh` (run locally when `cargo` is installed) and `.github/workflows/toc-gpui.yml`; set `VERIFY_RUN_GPUI=1` to opt into GPUI during verify when `cargo` is present.

```bash
./scripts/verify.sh
```

GitHub Actions runs the same script on pushes and pull requests targeting `main` (`.github/workflows/verify.yml`: `actions/checkout@v4`, Python 3.11, `./scripts/verify.sh`).

## TOC (Tactical Operations Center)

`./scripts/toc.sh` prints a text dashboard: active missions (objective, active flag, board progress), task ownership, recent AARs, model routing, armory `PINNED_SHA`, and the delegation / autonomous / maturity strip.

```bash
./scripts/toc.sh
./scripts/toc.sh --watch
./scripts/toc.sh --watch --interval 15
./scripts/toc.sh --web
./scripts/toc.sh --web --port 8765 --no-open
./scripts/toc.sh --gpui
./scripts/toc.sh --native setup-mission
./scripts/toc.sh --gpui --url http://127.0.0.1:8765
./scripts/toc.sh --set-delegation blockers=false external=false
./scripts/toc.sh --set-autonomous false
./scripts/toc.sh --toggle
```

| Surface | Command | Requires |
|---------|---------|----------|
| Terminal (default) | `./scripts/toc.sh` | Python 3 only |
| Localhost web | `./scripts/toc.sh --web` | Python 3 only |
| Native GPUI desktop | `./scripts/toc.sh --gpui` | Rust/Cargo, GPU stack (see [`toc-gpui/README.md`](toc-gpui/README.md)) |

`--web` runs `scripts/toc-web.py` on `127.0.0.1` only. It prints `http://127.0.0.1:<PORT>` (use `--port 0` or omit port for an ephemeral port). Set `TFN_TOC_PORT` to pick a port. Use `--no-open` to skip the browser. Real-time updates use Server-Sent Events.

`--gpui` (alias `--native`) launches the optional Rust GPUI app in `toc-gpui/`. Default feed watches the repo filesystem. Pass `--url` to follow the web TOC SSE stream instead.

Stream operator output live with `./scripts/op-log.sh <mission> <role> -- <cmd>` (writes UTC-timestamped lines under `missions/<mission>/logs/<role>.log` for the dashboard). If the web or native dashboard is unavailable, use the text dashboard above.

Ask Command for `give me the dashboard` or `TOC`. Command runs `./scripts/toc.sh` and relays the output.

Config: [`brain/toc-config.md`](brain/toc-config.md).

| Key | Default | Effect when true |
|-----|---------|------------------|
| `DELEGATE_BLOCKERS` | `false` | Command resolves blockers from `brain/` context. |
| `DELEGATE_EXTERNAL` | `false` | Command approves external publishes and destructive actions. |
| `AUTONOMOUS_MODE` | `false` | Command schedules standing cron jobs, operators run them, and the idle goal loop in [`autonomous-mode.md`](brain/playbooks/autonomous-mode.md) runs. `false` means Command acts only on explicit user missions. |

`--set-autonomous true|false` writes `AUTONOMOUS_MODE` in `brain/toc-config.md` and the active `squad.env`. `--set-delegation blockers=true|false external=true|false` updates one or both delegation keys. `--toggle` prompts for all three.

**Pushback guardrails:** even if a delegation toggle is `true`, Command pushes back and asks the human (naming the missing context) when there are fewer than 5 real AAR entries or fewer than 3 completed missions. The status strip shows `pushback active` or `pushback ready`. A completed mission has at least one `board.md` task and every status `done`.

## Top-level structure

```
AGENTS.md          # Unit persona, chain of command, ECC rule
armory/ecc/        # Vendored affaan-m/ECC (offline read-only reference)
profiles/          # Six lean operator profiles (~20 lines each)
brain/             # Shared memory: doctrine, AARs, playbooks
  toc-config.md    # DELEGATE_BLOCKERS, DELEGATE_EXTERNAL, AUTONOMOUS_MODE, thresholds
  playbooks/       # ooda-loop, dmaic-loop, handoff-protocol, autonomous-mode,
                   # degraded-operations, mission-readiness, intel-package,
                   # comsec, preventive-verification, partner-enablement,
                   # controlled-change
missions/          # Per-deployment context (_template + active slugs)
  setup-mission/   # Default first bootstrap (ACTIVE=1 in template repo)
  example-mission/ # Sample mission (inactive by default)
scripts/           # setup.sh, setup.ps1, toc.sh, router, deploy, sync-armory, verify
harnesses/         # Hermes / Pi install notes
systemd/           # User unit template for persistence
```

## Best-fit-first model routing

- Bootstrap inventory: `./scripts/detect-models.sh --slug <slug>` probes local OpenAI-compatible endpoints (`:8080`, vLLM `:8000`, Ollama `:11434`) and notes configured API providers via env presence (secrets never printed).
- Route: `python3 scripts/router.py "implement payment webhook"` returns operator role, `selected_model`, `fit_score`, `tiebreak_reason`, and step up/down candidates.
- Policy lives in `AGENTS.md` and `brain/doctrine.md`: fit first, cost tiebreak, step on observed results.

## How `brain/` compounds

1. Squads append **AARs** (`Outcome` / `Friction` / `Fix`) via `scripts/aar.sh`.
2. **Rule-of-Two** (`brain/doctrine.md`): the same fix for the same friction class must appear in two AARs before Command promotes a **playbook** under `brain/playbooks/` (squad-native only, never ECC copies).
3. Mission folders swap per deploy; profiles and `AGENTS.md` stay stable.

## Deploy a new squad (manual, without `setup.sh`)

```bash
git clone https://github.com/ValoLoco/task-force-null.git
cd task-force-null

./scripts/deploy-squad.sh my-project "Ship the API integration MVP"
./scripts/detect-models.sh --slug my-project   # also runs at deploy unless SKIP_DETECT_MODELS=1
./scripts/start.sh
python3 scripts/router.py --log "research dependency versions"
MISSION_SLUG=my-project ./scripts/aar.sh \
  "MVP shipped" "Missing env validation" "start.sh checks squad.env"
```

Set `MISSION_SLUG` in the environment or keep exactly one `missions/*/squad.env` with `ACTIVE=1`.

## Systemd persistence

```bash
./scripts/install-systemd.sh my-project
systemctl --user daemon-reload
systemctl --user enable --now sf-agent-unit@my-project.service
loginctl enable-linger "$USER"
```

`install-systemd.sh` writes `REPO_ROOT` and `MISSION_SLUG` into a user-unit drop-in. Default unit path assumes `~/task-force-null`; override via the drop-in when cloned elsewhere. Linux with systemd only. macOS, Windows, and Termux run `./scripts/start.sh` directly (Termux: `tmux` or `termux-services`, see Quick install).

## Design principles

- **Carbon Fiber:** maximum clarity, minimum moving parts.
- **YAGNI:** no third-party deps in template tooling (POSIX bash, Python 3 stdlib only).
- **Profiles unchanged across environments;** only mission folders and `squad.env` change.

## Example mission

Fresh clones start with **`missions/setup-mission/`** (bootstrap checklist). See `missions/example-mission/` for a sample follow-on mission, or `./scripts/deploy-squad.sh` from `_template`.

## License

MIT License. See [LICENSE](LICENSE).