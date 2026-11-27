# Pi Coding Agent

## Prerequisites

- Linux, macOS, or Windows with network for first-time install
- `curl` on Unix; PowerShell on Windows

## Install (verified)

**Linux / macOS:**

```bash
curl -fsSL https://pi.dev/install.sh | sh
pi install npm:pi-agents
```

(`pi install npm:pi-agents` pulls in `@earendil-works/pi-durable` for crash-resilient durable sub-agents.)

**Windows PowerShell:**

```powershell
irm https://pi.dev/install.ps1 | iex
pi install npm:pi-agents
```

## Verify

```bash
command -v pi && pi --version
```

## Task Force Null deploy

1. Run `./scripts/setup.sh` (or `scripts\setup.ps1` on Windows) and select **Pi** when prompted.
2. Point Pi workspace or project root at this repository (`REPO_ROOT`).
3. Load `AGENTS.md`, `profiles/`, and the active `missions/<slug>/` folder.
4. ECC: read-only from `armory/ecc/`; never run ECC installers or hooks.

Re-run setup to refresh armory and models without wiping saved `.env` keys.