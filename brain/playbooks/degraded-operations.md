# Degraded Operations

SERE-style resilience when the armory, inference, or the network is down. Stay inside mission limits. If the fallback is blocked, halt and log.

## Triggers

| Loss | Fallback |
|------|----------|
| ECC host (`/workspace/ecc`) down | Read vendored `armory/ecc/` in place. One skill. Do not copy skill bodies. |
| Inference endpoint down | Use a local or secondary model already installed, or `.env` keys, or another remote endpoint. Do not start a surprise download. |
| Network down | Use cached `brain/` (doctrine, playbooks, AARs, `models.md`) and the active mission folder. |

## Order

1. Name the outage in the handoff or in `intel.md` (source, time, confidence).
2. Take one fallback from the table. Do not invent a new toolchain.
3. If that fallback is blocked, stop. Append an AAR with `scripts/aar.sh`.
4. Command tells the human only when the block needs a decision.

## Limits

No ECC installers or hooks. No secrets in the AAR. No external send while offline.

Read with `ooda-loop.md` and `comsec.md` at session start.
