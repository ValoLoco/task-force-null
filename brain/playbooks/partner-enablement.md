# Partner Enablement

FID and UW style handoff. Document, train, and leave a capability the host team can run after the squad stands down.

## Package

| Item | Content |
|------|---------|
| Intent | Active `mission.md` objective and left and right limits. |
| Runbook | Commands the host will run (`start.sh`, `verify.sh`, `toc.sh`). |
| State | `board.md` status, `intel.md` open items, `squad.env` with secrets removed. |
| Lessons | AAR rows and playbooks that apply. No ECC skill bodies. |

## Steps

1. Medic-qa confirms `./scripts/verify.sh` is green.
2. Comms drafts the host package. Command delivers it.
3. Walk the host through one successful run on their machine.
4. Name the residual risks and the single point of contact.
5. Stand down only after the host can repeat the run without the squad.

## Limits

Do not leave credentials in the package. Do not leave the squad as a hidden dependency for routine operations.

Read with `handoff-protocol.md` at session start.
