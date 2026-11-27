# Pi Coding Agent (recommended default)

Upstream: [earendil-works/pi](https://github.com/earendil-works/pi) (MIT). CLI docs and installers: [pi.dev](https://pi.dev).

## Prerequisites

- Linux, macOS, or Windows with network for first install
- **npm path:** Node.js 22.19+ if you install via npm instead of the shell installer

## Install (verified)

### Linux / macOS (recommended)

```bash
curl -fsSL https://pi.dev/install.sh | sh
```

### Windows PowerShell

```powershell
irm https://pi.dev/install.ps1 | iex
```

### npm alternative (Node 22.19+)

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

Same npm package as documented in the root `README.md` and Termux quick install. Prefer `https://pi.dev/install.sh` (or `install.ps1` on Windows) when you want the upstream installer; use npm when you already standardize on a global Node toolchain.

Confirm `pi` is on `PATH` before installing extensions.

## Multi-agent extension (Pi Agents)

```bash
pi install npm:pi-agents
```

Package: [mavam/pi-agents](https://github.com/mavam/pi-agents) (MIT).

## Pi Durable (checkpointing)

`@earendil-works/pi-durable` (MIT, [earendil-works/pi](https://github.com/earendil-works/pi) monorepo) installs **automatically** as a direct dependency of `pi-agents`. It provides crash-resilient sub-agents and checkpoints conversations and tasks to disk. You normally do not install it separately; run `pi install npm:pi-agents` once.

## Verify

```bash
command -v pi && pi --version
```

## Task Force Null deploy

1. Run `./scripts/setup.sh` (or `scripts\setup.ps1` on Windows) and select **Pi** when prompted, or run `curl -fsSL https://pi.dev/install.sh | sh` (or `install.ps1`) then `pi install npm:pi-agents` manually.
2. Point the Pi workspace or project root at this repository (`REPO_ROOT`).
3. Load `AGENTS.md`, `brain/playbooks/`, `profiles/`, and the active `missions/<slug>/` folder.
4. ECC: read-only from `armory/ecc/`; never run ECC installers or hooks.

Re-run setup to refresh armory and models without wiping saved `.env` keys.