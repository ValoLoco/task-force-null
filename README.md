```
==============================================================================
                         BUENATURA
  _____         _     _____ ____  _____ _____   __     ______  _     _
 |  __ \       | |   / ____/ ___||  ___| ____|  \ \   / /___ \| |   | |
 |  |  | | __ _ | | _| |   \___ \| |_  |  _|     \ \ / /   __) | |   | |
 |  |  | |/ _` || || | |    ___) |  _| | |___     \ V /   / __/| |   | |
 | |_|_| \__,_||_| \_____|____/|_|   |_____|     \_/   |_____||_|___|_|
                    T A S K   F O R C E   N U L L
==============================================================================
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Task Force Null (TASK FORCE NULL)

Released under the [MIT License](LICENSE) (Copyright 2026 Valentin Kranz).

Lean, redeployable **Special Forces AI agent team** template ([`ValoLoco/task-force-null`](https://github.com/ValoLoco/task-force-null)). One five-operator squad plus Command for multi-squad work, shared `brain/`, swappable `missions/<slug>/` per deployment.

## One-line deploy prompt

Copy into any AI harness (Hermes, Grok Bot, Claude, Codex, Cursor, etc.):

```text
You are Task Force Null: read AGENTS.md, brain/doctrine.md, and profiles/{lead,recon,builder,medic-qa,comms,command}.md; clone https://github.com/ValoLoco/task-force-null into this project; run scripts/deploy-squad.sh <slug> "<one-line objective>" (syncs armory/ecc via scripts/sync-armory.sh) and scripts/start.sh; operate within missions/<slug>/mission.md limits with one board.md owner per task; use scripts/router.py for routing; ECC is read-only (prefer /workspace/ecc/search.sh online, armory/ecc offline, one skill at a time, never copy ECC into the repo, never run ECC installers or hooks); human approval for all external publish and destructive actions.
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

## Fast clone / clone size

| Goal | Command |
|------|---------|
| Full offline-ready clone (shallow) | `git clone --depth 1 https://github.com/ValoLoco/task-force-null.git` |
| Lightweight online-only sparse clone (skips `armory/ecc/` blobs until needed) | `git clone --filter=blob:none --sparse https://github.com/ValoLoco/task-force-null.git && cd task-force-null && git sparse-checkout set --no-cone '/*' '!/armory/ecc/'` |

`armory/ecc/**` is marked `linguist-vendored` in `.gitattributes` so GitHub collapses vendored diffs and keeps language stats clean while the full offline copy stays in the repo.

Restore a full offline armory anytime with `./scripts/sync-armory.sh` or `git sparse-checkout disable` after a sparse clone.

## Verification (`scripts/verify.sh`)

One command runs shell syntax checks, router smoke tests, setup/detect-models tests, profile line limits, branding checks, and an owned-file em-dash scan (excluding `armory/ecc/`). Default `VERIFY_SKIP_ONLINE_SYNC=1` avoids upstream ECC sync during verify so CI and offline runs stay deterministic; unset it locally to exercise live `sync-armory.sh`.

```bash
./scripts/verify.sh
```

GitHub Actions runs the same script on pushes and pull requests targeting `main` (see `.github/workflows/verify.yml`).

## Top-level structure

```
AGENTS.md          # Unit persona, chain of command, ECC rule
armory/ecc/        # Vendored affaan-m/ECC (offline read-only reference)
profiles/          # Six lean operator profiles (~20 lines each)
brain/             # Shared memory: doctrine, AARs, playbooks
missions/          # Per-deployment context (_template + active slugs)
scripts/           # setup, router, deploy, sync-armory, start, AAR
harnesses/         # Hermes / PyAgent install notes
systemd/           # User unit template for persistence
```

## ECC armory (`armory/ecc/`)

The full [affaan-m/ECC](https://github.com/affaan-m/ECC) repository is vendored under **`armory/ecc/`** for offline use (agents, skills, docs, tests, scripts). The synced commit is recorded in `armory/ecc/PINNED_SHA`.

| Rule | Detail |
|------|--------|
| Online sync | `./scripts/deploy-squad.sh` runs `scripts/sync-armory.sh --allow-offline` unless `SKIP_SYNC_ARMORY=1` |
| Manual sync | `./scripts/sync-armory.sh` (add `--allow-offline` to keep local copy if upstream is down) |
| Discovery online | Prefer `/workspace/ecc/search.sh <query>` when the host armory is mounted |
| Discovery offline | Browse and read skills under `armory/ecc/` one at a time |
| Prohibited | Never run ECC `install.sh`, `install.ps1`, hooks, or copy skill bodies into `brain/` or missions |

Medic QA blocks merges that embed ECC skill bodies. Lead logs which ECC skill was consulted when it influenced scope or implementation.

## Best-fit-first model routing

- Bootstrap inventory: `./scripts/detect-models.sh --slug <slug>` probes local OpenAI-compatible endpoints (`:8080`, vLLM `:8000`, Ollama `:11434`) and notes configured API providers via env presence (secrets never printed).
- Route: `python3 scripts/router.py "implement payment webhook"` returns operator role, `selected_model`, `fit_score`, `tiebreak_reason`, and step up/down candidates.
- Policy lives in `AGENTS.md` and `brain/doctrine.md`: fit first, cost tiebreak, step on observed results.

## How `brain/` compounds

1. Squads append **AARs** (`Outcome` / `Friction` / `Fix`) via `scripts/aar.sh`.
2. **Rule-of-Two** (`brain/doctrine.md`): the same fix for the same friction class must appear in two AARs before Command promotes a **playbook** under `brain/playbooks/` (squad-native only, never ECC copies).
3. Mission folders swap per deploy; profiles and `AGENTS.md` stay stable.

## Guided setup (`scripts/setup.sh`)

Interactive first-time bootstrap (idempotent, safe to re-run):

```bash
git clone https://github.com/ValoLoco/task-force-null.git
cd task-force-null
./scripts/setup.sh
```

| Mode | Usage |
|------|--------|
| Dry run | `./scripts/setup.sh --dry-run` (prints commands, no installs or downloads) |
| CI / automation | `./scripts/setup.sh --non-interactive --skip-llm --harness cursor --mission-slug my-squad` |
| Skip duplicate sync | Deploy path uses `SKIP_SYNC_ARMORY=1` / `SKIP_DETECT_MODELS=1` when `deploy-squad.sh` runs inside setup |

**Flow:** detect harness (Hermes, PyAgent, Claude, Grok, Cursor) → optional harness install ([`harnesses/`](harnesses/README.md)) → optional local LLM on `127.0.0.1:8080` (reuses `/workspace/local-llm` when present, no re-download of the 6.5 GB Inkling quant) → optional API keys into gitignored `.env` (`chmod 600`, empty input keeps existing keys) → `sync-armory.sh`, `detect-models.sh`, `deploy-squad.sh`, `start.sh`.

Secrets never print to logs. See [`.env.example`](.env.example).

## Deploy a new squad (manual)

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

`install-systemd.sh` writes `REPO_ROOT` and `MISSION_SLUG` into a user-unit drop-in. Default unit path assumes `~/task-force-null`; override via the drop-in when cloned elsewhere.

## Design principles

- **Carbon Fiber:** maximum clarity, minimum moving parts.
- **YAGNI:** no third-party deps in template tooling (POSIX bash, Python 3 stdlib only).
- **Profiles unchanged across environments;** only mission folders and `squad.env` change.

## Example mission

See `missions/example-mission/` for a minimal populated mission, or `./scripts/deploy-squad.sh` from `_template`.

## License

MIT License. See [LICENSE](LICENSE).