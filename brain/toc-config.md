# TOC Config

Machine-readable toggles for the Tactical Operations Center. Defaults keep the human in charge. Command reads this file before blockers, external sends, or idle goal generation.

DELEGATE_BLOCKERS=false
DELEGATE_EXTERNAL=false
AUTONOMOUS_MODE=false

MIN_AARS_FOR_DELEGATION=5
MIN_COMPLETED_MISSIONS_FOR_DELEGATION=3

## Delegation

- `DELEGATE_BLOCKERS=true`: Command resolves blockers from `brain/` context.
- `DELEGATE_EXTERNAL=true`: Command approves external publishes and destructive actions.
- Both default to `false`. The human decides.

## Pushback guardrails

Even when a delegation toggle is `true`, Command pushes back and asks the human, naming the missing context, when either threshold fails:

- Fewer than `MIN_AARS_FOR_DELEGATION` real AAR entries in `brain/aar-log.md`. Lines inside fenced examples do not count.
- Fewer than `MIN_COMPLETED_MISSIONS_FOR_DELEGATION` completed missions under `missions/`.

A mission is completed when its `board.md` status table has at least one task and every task status is `done`. Directory names that start with `_` are templates, not missions.

`pushback active` means a threshold is unmet, so delegation does not take effect.
`pushback ready` means both thresholds are met, so a `true` toggle may apply.

## Autonomous mode

`AUTONOMOUS_MODE=false` by default. The same key is stored on the active `missions/<slug>/squad.env`.

When `true`, Command schedules standing cron jobs for mission tasks, operators execute them, and the idle-trigger loop in `brain/playbooks/autonomous-mode.md` runs.

When `false`, Command acts only on explicit user missions.

Delegation and human approval gates still apply unless explicitly delegated and pushback is ready.

## Dashboard

When the user asks Command for `give me the dashboard` or `TOC`, Command runs `./scripts/toc.sh` and relays the output.

`./scripts/toc.sh --set-delegation blockers=true|false external=true|false` updates the delegation keys.
`./scripts/toc.sh --set-autonomous true|false` updates `AUTONOMOUS_MODE` here and on the active `squad.env`.
`./scripts/toc.sh --toggle` prompts for the three toggles.
`./scripts/toc.sh --watch` refreshes every 30 seconds. `--interval <seconds>` changes the period.
