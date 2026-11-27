# Hermes Agent

## Prerequisites

- Linux or macOS with `bash`, `git`, and network for first-time install
- Python 3.10+ if installing from source (see upstream Hermes docs)

## Install

```bash
# Example: follow upstream Hermes Agent install (adjust URL to your distribution)
pip install --user hermes-agent
# or clone upstream Hermes and add to PATH per their README
```

Confirm `hermes` is on `PATH` or set `HERMES_HOME` to the install root.

## Verify

```bash
command -v hermes && hermes --version
```

## Task Force Null deploy

1. Run `./scripts/setup.sh` from this repo root and select **Hermes** when prompted.
2. Point the Hermes workspace or project root at this repository (`REPO_ROOT`).
3. Ensure Hermes loads `AGENTS.md`, `profiles/`, and the active `missions/<slug>/` folder.
4. Do not run ECC installers from `armory/ecc/`; use vendored skills read-only.

Re-run `setup.sh` safely: it refreshes armory, models, and mission files without wiping `.env` keys.