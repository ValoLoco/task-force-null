# Hermes Agent

Optional harness when Hermes is already your host. For new installs, prefer **Pi Coding Agent** ([pi-agent.md](pi-agent.md)).

## Prerequisites

- Linux or macOS with `bash`, `git`, and network for first-time install
- Python 3.10+ if installing from source (see upstream Hermes docs)

## Install

```bash
python3 -m pip install --user hermes-agent
```

Follow upstream Hermes Agent install docs if you use a different distribution or clone-based install.

Confirm `hermes` is on `PATH` or set `HERMES_HOME` to the install root.

## Verify

```bash
command -v hermes && hermes --version
```

## Task Force Null deploy

1. Run `./scripts/setup.sh` from this repo root and select **Hermes** when prompted (`--install-harness hermes` in non-interactive runs).
2. Point the Hermes workspace or project root at this repository (`REPO_ROOT`).
3. Load `AGENTS.md`, `brain/playbooks/`, `profiles/`, and the active `missions/<slug>/` folder.
4. Do not run ECC installers from `armory/ecc/`; use vendored ECC read-only.

Re-run `setup.sh` safely: it refreshes armory, models, and mission files without wiping `.env` keys.

## Related

- **Pi Coding Agent:** default harness with `pi-agents` and Pi Durable checkpointing ([pi-agent.md](pi-agent.md)).
- **Setup on Windows:** use `scripts/setup.ps1` for Pi; Hermes install is typically via Python on all platforms Hermes supports.