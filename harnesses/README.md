# Harnesses

Task Force Null deploys into a host AI harness. Pick one and follow its install note before setup.

| Harness | Install note | Verify |
|---------|--------------|--------|
| Hermes Agent | [hermes-agent.md](hermes-agent.md) | `hermes --version` or `$HERMES_HOME` |
| Pi Coding Agent | [pi-agent.md](pi-agent.md) | `pi --version` |
| Claude Code | Vendor install; workspace at repo root | `claude --version` |
| Grok Bot | Vendor / MCP setup | `XAI_API_KEY` or host env |
| Cursor | Cloud or desktop agent | `CURSOR_AGENT` / agent workspace |

Setup detects installed harnesses and guides install when none are present (Hermes pip, Pi via pi.dev, or manual).