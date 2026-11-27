# Task Force Null

Lean, redeployable **Special Forces AI agent team** template ([`ValoLoco/task-force-null`](https://github.com/ValoLoco/task-force-null)). One five-operator squad plus Command for multi-squad work, shared `brain/`, swappable `missions/<slug>/` per deployment.

## One-line deploy prompt

Copy into any AI harness (Hermes, Grok Bot, Claude, Codex, Cursor, etc.):

```text
You are Task Force Null: read AGENTS.md, brain/doctrine.md, and profiles/{lead,recon,builder,medic-qa,comms,command}.md; clone or vendor https://github.com/ValoLoco/task-force-null into this project; run scripts/deploy-squad.sh <slug> "<one-line objective>" and scripts/start.sh; operate only within missions/<slug>/mission.md left/right limits with one board.md owner per task; use scripts/router.py for routing; ECC is read-only at /workspace/ecc (one skill at a time via /workspace/ecc/search.sh only, never copy ECC into the repo, never run ECC installers or hooks); human approval for all external publish and destructive actions.
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

## Top-level structure

```
AGENTS.md          # Unit persona, chain of command, ECC rule
profiles/          # Six lean operator profiles (~20 lines each)
brain/             # Shared memory: doctrine, AARs, playbooks
missions/          # Per-deployment context (_template + active slugs)
scripts/           # Router, deploy, start, AAR (bash + Python 3 stdlib)
systemd/           # User unit template for persistence
```

## ECC read-only armory

Task Force Null does **not** ship specialist skills. When depth is needed, operators use the host **ECC armory** at `/workspace/ecc`:

| Rule | Detail |
|------|--------|
| Location | `/workspace/ecc` on the workspace host (outside this repo) |
| Discovery | `/workspace/ecc/search.sh <query>` returns candidate skill paths |
| Consumption | Read the chosen skill **in place**; apply its guidance for the active task only |
| Prohibited | Copying ECC files into this repo, duplicating skills under `brain/playbooks/`, running ECC install scripts, or enabling ECC hooks |

Medic QA blocks merges that embed ECC skill bodies. Lead logs which ECC skill was consulted in the task handoff packet when it influenced scope or implementation.

## How `brain/` compounds

1. Squads append **AARs** (`Outcome` / `Friction` / `Fix`) via `scripts/aar.sh`.
2. **Rule-of-Two** (`brain/doctrine.md`): the same fix for the same friction class must appear in two AARs before Command promotes a **playbook** under `brain/playbooks/` (squad-native only, never ECC copies).
3. Mission folders swap per deploy; profiles and `AGENTS.md` stay stable.

## Deploy a new squad (new project)

```bash
git clone https://github.com/ValoLoco/task-force-null.git
cd task-force-null

./scripts/deploy-squad.sh my-project "Ship the API integration MVP"
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