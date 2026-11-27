# Controlled Change

Bounded edits and rollbacks. Every destructive or cross-module action states a blast radius and a concrete rollback before it runs.

## Before execution

| Item | Required content |
|------|------------------|
| Blast radius | Paths, services, and users affected. |
| Rollback | Exact command or file restore that returns the last good state. |
| Proof | Check that shows the rollback worked (command and expected result). |

## Rules

- No destructive step without those three items in the handoff.
- Cross-module edits name every module touched. Unrelated cleanup waits.
- If rollback was not rehearsed and the action is hard to undo, stop for the human.
- `DELEGATE_EXTERNAL` does not waive this playbook. It only changes who may approve.

## Reference names

Read-only ECC skill names, when needed: `change-impact`, `safety-guard`. Cite the name. Do not copy the skill into this repo.

Read with `ooda-loop.md` at session start.
