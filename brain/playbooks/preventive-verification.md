# Preventive Verification

Medic-qa checks before merge, not only after the build. `./scripts/verify.sh` is the squad gate. A red verify blocks release.

## When

- Before a handoff to comms.
- Before Command calls a mission goal done.
- After any change under `scripts/`, `profiles/`, `brain/`, or `missions/`.

## Method

1. Run `./scripts/verify.sh` and keep the output with the handoff.
2. Re-run mission acceptance checks that verify.sh does not cover.
3. On failure, send one primary failure mode back to Builder.

## Reference names

Read-only ECC skill names, when the host armory is up: `verification-loop`, `production-audit`, `canary-watch`. Cite the name. Do not copy the skill into this repo.

## Record

Pass or fail goes on `board.md`. Meaningful failures get an AAR via `scripts/aar.sh`.

Read with `dmaic-loop.md` at session start.
