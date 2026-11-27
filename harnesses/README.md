# Harnesses

Task Force Null deploys into a host AI harness. **Pi Coding Agent** is the **recommended default** ([pi-agent.md](pi-agent.md)). Hermes, Claude, Grok, and Cursor are supported when already installed.

| Harness | Install note | Verify |
|---------|--------------|--------|
| **Pi Coding Agent (default)** | [pi-agent.md](pi-agent.md) | `pi --version` |
| Hermes Agent | [hermes-agent.md](hermes-agent.md) | `hermes --version` or `$HERMES_HOME` |
| Claude Code | Vendor install; workspace at repo root | `claude --version` |
| Grok Bot | Vendor / MCP setup | `XAI_API_KEY` or host env |
| Cursor | Cloud or desktop agent | `CURSOR_AGENT` / agent workspace |

`./scripts/setup.sh` (or `scripts/setup.ps1` on Windows) detects installed harnesses and offers guided install for **Pi** or **Hermes** when none are present.