# OODA Loop

Standing decision cycle for every operator. Run it each turn before and after meaningful work.

## Phases

| Phase | Job |
|-------|-----|
| **Observe** | Gather primary artifacts and live state: repo tree, `board.md`, `intel.md`, mission files, and real tool outputs. Never trust model recall alone. |
| **Orient** | Filter observations through `missions/<slug>/mission.md` left/right limits, `brain/doctrine.md`, prior AARs, and active risks on the board or in intel. |
| **Decide** | Pick the smallest in-scope next action, owner role, and model fit (`scripts/router.py`). If blocked, irreversible, or off-mission, stop at a human approval gate or 2-Fail escalation to Lead. |
| **Act** | Execute within limits, verify against acceptance criteria, then emit a handoff packet (`playbooks/handoff-protocol.md`) or loop back to **Observe**. |

## When to apply

- Every task turn before you act.
- Ambiguous handoffs or missing acceptance criteria.
- Unexpected failures, flaky tools, or verify regressions.
- Mid-mission pivots when scope or risk changes.

Default playbook: read at session start with `dmaic-loop.md` and doctrine.