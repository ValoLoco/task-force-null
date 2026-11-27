# Harnesses

Task Force Null deploys into a host AI harness. Pick one and follow its install note before `./scripts/setup.sh`.

| Harness | Install note | Verify |
|---------|--------------|--------|
| Hermes Agent (default) | [hermes-agent.md](hermes-agent.md) | `hermes --version` or `$HERMES_HOME` |
| PyAgent | [pyagent.md](pyagent.md) | `pyagent --version` or `python3 -m pyagent --help` |
| Claude Code | Use vendor install; point workspace at this repo | `claude --version` |
| Grok Bot | Vendor / MCP setup | `GROK_BOT` or host env |
| Cursor | Cloud or desktop agent | `CURSOR_AGENT` / agent workspace |

Setup detects installed harnesses and guides install when none are present.