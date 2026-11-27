# Handoff Protocol

## Handoff Packet (required fields)

| Field | Description |
|-------|-------------|
| `task_id` | Board task reference |
| `from_role` | Profile id (e.g. recon) |
| `to_role` | Profile id |
| `intent_snippet` | Relevant Commander's Intent lines |
| `acceptance` | Verifiable done criteria |
| `artifacts` | Paths, commands, or URLs |
| `risks` | Open items from intel or recon |
| `hop` | 1 or 2 (max 2) |

## Max-2-Hops Rule

A task may pass role-to-role at most twice without Lead reset or human review. Hop 3 requires Lead to split the task or escalate.

## Comms Path

Builder → Medic-qa → Comms → **Command** → Human approval → external channel.

Only **Command** talks to the human. Internal-only handoffs may skip Comms unless the deliverable is human-facing documentation (still relayed via Command if shown to the user).