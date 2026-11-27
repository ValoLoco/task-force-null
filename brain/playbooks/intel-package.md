# Intel Package

Recon standard for every `intel.md` entry. An entry missing these fields is incomplete. Lead does not route build work on an incomplete package.

## Required fields

| Field | Rule |
|-------|------|
| `source` | Primary artifact: path, command, log, or human statement. |
| `timestamp` | UTC time the fact was checked. |
| `confidence` | One of `verified`, `inferred`, `unknown`. |
| `risks` | What breaks if this fact is wrong. `none` is allowed. |
| `open_questions` | Unresolved items. `none` is allowed. |

## Rules

- Prefer primary artifacts over model recall.
- `unknown` confidence cannot satisfy a success criterion by itself.
- Update the row when the fact changes. Keep the new timestamp.
- ECC: name a skill if one was read. Do not paste the skill body.

## Handoff

Recon sends the package to Lead: findings, risks, open questions, recon-complete yes or no.

Read with `handoff-protocol.md` at session start.
