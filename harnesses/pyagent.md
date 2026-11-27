# PyAgent

## Prerequisites

- Python 3.10+
- `pip` or `uv` for package install

## Install

```bash
pip install --user pyagent
# or: python3 -m pip install pyagent
```

Confirm the CLI is available:

```bash
command -v pyagent || python3 -m pyagent --help
```

## Verify

```bash
pyagent --version 2>/dev/null || python3 -m pyagent --version
```

## Task Force Null deploy

1. Run `./scripts/setup.sh` and select **PyAgent** when prompted.
2. Configure PyAgent project root to this repository path.
3. Load `AGENTS.md` and operator profiles from `profiles/`; active mission under `missions/<slug>/`.
4. ECC: read-only from `armory/ecc/` or `/workspace/ecc`; never run `install.sh` from ECC.

Re-run `setup.sh` to refresh models and armory without destroying saved API keys in `.env`.