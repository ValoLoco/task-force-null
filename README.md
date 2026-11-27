# second-brain

Lean, redeployable **Special Forces AI agent team** template. One five-operator squad (plus Command for multi-squad work), one shared `brain/`, and swappable `missions/<slug>/` context per deployment.

## Special Forces parallel

| Profile | MOS parallel | Function |
|---------|----------------|----------|
| `command.md` | Colonel / group | Multi-squad intent, deconfliction, playbook promotion |
| `lead.md` | 18A | Commander's Intent, routing, go/no-go |
| `recon.md` | 18F | Verified intel, risks, open questions |
| `builder.md` | 18B/18C | Minimum viable deliverables in scope |
| `medic-qa.md` | 18D | Evidence-based verification, 3-line AAR |
| `comms.md` | 18E | Human-facing packaging, approval gates |

Profiles live in `profiles/` and stay **domain-agnostic**. Project-specific intent lives under `missions/`.

## Top-level structure

```
profiles/          # Six lean operator profiles (~15-25 lines each)
brain/             # Shared memory: doctrine, AARs, playbooks
missions/          # Per-deployment context (_template + active slugs)
scripts/           # Router, deploy, start, AAR (bash + Python 3 stdlib)
systemd/           # User unit template for persistence
```

## How `brain/` compounds

1. Squads append **AARs** (`Outcome` / `Friction` / `Fix`) via `scripts/aar.sh`.
2. **Rule-of-Two** (`brain/doctrine.md`): the same fix for the same friction class must appear in two AARs before Command promotes a **playbook** under `brain/playbooks/`.
3. Doctrine and handoff protocol change rarely; mission folders swap per deploy without editing profiles.

## Deploy a new squad (new project)

```bash
git clone https://github.com/ValoLoco/second-brain.git
cd second-brain

# Create and activate a mission slug
./scripts/deploy-squad.sh my-project "Ship the API integration MVP"

# Validate layout and active mission
./scripts/start.sh

# Route a task (optional logging)
python3 scripts/router.py --log "research dependency versions"

# Record an AAR
MISSION_SLUG=my-project ./scripts/aar.sh \
  "MVP shipped" "Missing env validation" "start.sh checks squad.env"
```

Set `MISSION_SLUG` in the environment or keep exactly one `missions/*/squad.env` with `ACTIVE=1`.

## Systemd persistence

Install the user unit (adjust path via override if not in `~/second-brain`):

```bash
./scripts/install-systemd.sh my-project
systemctl --user daemon-reload
systemctl --user enable --now sf-agent-unit@my-project.service
loginctl enable-linger "$USER"
```

The unit runs `scripts/start.sh` oneshot with `Restart=on-failure`. Use `install-systemd.sh` to write `REPO_ROOT` and `MISSION_SLUG` into a drop-in.

## Design principles

- **Carbon Fiber:** maximum clarity, minimum moving parts.
- **YAGNI:** no third-party deps in template tooling (POSIX bash, Python 3 stdlib only).
- **Profiles unchanged across environments;** only mission folders and `squad.env` change.

## Example mission

See `missions/example-mission/` for a minimal populated mission. Copy ideas from it, or deploy fresh from `_template` with `deploy-squad.sh`.