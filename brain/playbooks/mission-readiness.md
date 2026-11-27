# Mission Readiness

Pre-mission gate. `missions/setup-mission/` is the repeatable check before any real mission starts. Command owns the gate. Lead does not open follow-on work until it passes.

## Checks

1. Environment: repo root, `bash`, and `python3` are available. `./scripts/start.sh` resolves `setup-mission`.
2. Armory: `./scripts/sync-armory.sh --allow-offline` leaves `armory/ecc/PINNED_SHA` in place.
3. Models: `./scripts/detect-models.sh --slug setup-mission` refreshes `brain/models.md`.
4. Active mission: exactly one `missions/*/squad.env` has `ACTIVE=1`.
5. Health: `./scripts/verify.sh` exits 0.

## Pass rule

All five checks pass, or the failure is logged with an owner. A failed check blocks a new slug from `deploy-squad.sh` until Command records the exception.

## After the gate

Lead copies `missions/_template` only when the user has named the next objective. `setup-mission` stays the bootstrap record.

Read with `dmaic-loop.md` at session start.
