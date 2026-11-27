# Commander's Intent (bootstrap)

**Mission slug:** `setup-mission`  
**Objective:** Default first mission on every fresh deploy. Command settles the team in before real work.

## Bootstrap sequence (Command owns user dialogue)

1. Verify local environment and host harness (Pi, Hermes, Claude, Cursor, etc.).
2. Confirm `armory/ecc/` status: `./scripts/sync-armory.sh --allow-offline`.
3. Run `./scripts/detect-models.sh --slug setup-mission` and confirm inventory in `brain/models.md`.
4. Introduce each operator role (`command`, `lead`, `recon`, `builder`, `medic-qa`, `comms`) to the user via **Command only**.
5. Ask the user to define project goals and the next mission slug(s).

When these items complete, **Command** waits for the user's next objectives (no direct speech from other operators).

## Success Criteria

- [ ] `scripts/start.sh` resolves `setup-mission` as active mission
- [ ] Board tasks T-1 through T-5 closed with evidence
- [ ] User stated next goals or next mission slug in intel

## Left Limits

- POSIX bash and Python 3 stdlib in template scripts only unless mission expands scope.

## Right Limits

- No external publish without human approval; no ECC installers or hooks.

## Notes

Shipped active by default. Clone `missions/_template` or run `deploy-squad.sh` for follow-on missions; set `ACTIVE=1` on one slug only.