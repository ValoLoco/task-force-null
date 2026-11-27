# Harnesses

Task Force Null deploys into a host AI harness. **Pi Coding Agent** is the **recommended default** ([pi-agent.md](pi-agent.md)). Hermes, Claude, Grok, and Cursor are supported when already installed.

| Harness | Install note | Verify |
|---------|--------------|--------|
| **Pi Coding Agent (default)** | [pi-agent.md](pi-agent.md) | `pi --version` |
| Hermes Agent | [hermes-agent.md](hermes-agent.md) | `hermes --version` or `$HERMES_HOME` |
| Claude Code | Vendor install; workspace at repo root | `claude --version` |
| Grok Bot | [grok-bot.md](grok-bot.md) and [published template](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I) | `XAI_API_KEY` or host env |
| Cursor | Cloud or desktop agent | `CURSOR_AGENT` / agent workspace |

`./scripts/setup.sh` (or `scripts/setup.ps1` on Windows) detects installed harnesses and offers guided install for **Pi** or **Hermes** when none are present.

**Grok Bot one line:** Import the [published Task Force Null Command template](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I) in Grok Bot and open its chat to start the built-in onboarding flow (same template linked from the root `README.md`).