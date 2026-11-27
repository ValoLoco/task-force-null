# Grok Bot (Task Force Null Command)

Published template: [Task Force Null Command](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I)

## One line

Import the [published template](https://x.ai/bot/zBFQAAO1GAvF30CG0mr6I) in Grok Bot and open its chat to run built-in onboarding.

## Onboarding skill

The template ships **`task-force-null-getting-started`**. It runs on first chat and walks clone, harness setup, and squad bootstrap.

## Repo root and clone path

Onboarding clones [`ValoLoco/task-force-null`](https://github.com/ValoLoco/task-force-null). If your checkout is not the default layout, pass **`--repo-root`** on TOC and helper scripts:

```bash
./scripts/toc.sh --repo-root /path/to/task-force-null
./scripts/setup.sh   # uses script location to infer repo root
```

`scripts/op-log.sh`, `scripts/toc.sh`, and `scripts/detect-models.sh` all accept `--repo-root` for non-default clone paths.

## TOC surfaces

After the repo is present:

| Surface | Command |
|---------|---------|
| Terminal | `./scripts/toc.sh` |
| Localhost web | `./scripts/toc.sh --web` |
| Native GPUI | `./scripts/toc.sh --gpui` or `./scripts/toc.sh --native` |

Add `--repo-root` when scripts are invoked outside the default clone directory.

## Harness notes

- Grok Bot mounts the repo workspace and loads `AGENTS.md`.
- Command is the sole user-facing operator; other profiles work internal handoffs only.
- Inference: Grok native by default; onboarding may prompt for API keys or local Inkling via `llama.cpp`.