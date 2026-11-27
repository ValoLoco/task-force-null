# Brain Index

Shared **Task Force Null** memory for all squads. Read at deploy; write via AARs, promoted playbooks, and doctrine updates.

| Path | Purpose |
|------|---------|
| `doctrine.md` | Standing rules, model routing, ECC armory, approval gates, Rule-of-Two |
| `toc-config.md` | Delegation toggles, pushback thresholds, `AUTONOMOUS_MODE` |
| `models.md` | Detected model inventory, Learned Overrides (bootstrap via `detect-models.sh`) |
| `aar-log.md` | Outcome / Friction / Fix history |
| `playbooks/_template.md` | Skeleton for new playbooks |
| `playbooks/ooda-loop.md` | Observe, Orient, Decide, Act on every turn |
| `playbooks/dmaic-loop.md` | Define through Control for repeating friction |
| `playbooks/handoff-protocol.md` | Handoff packet and max-2-hops rule |
| `playbooks/autonomous-mode.md` | Idle goal loop when `AUTONOMOUS_MODE=true` |
| `playbooks/degraded-operations.md` | Outage fallbacks for armory, inference, and network |
| `playbooks/mission-readiness.md` | Pre-mission gate before a real mission |
| `playbooks/intel-package.md` | Required Recon fields on every intel entry |
| `playbooks/comsec.md` | Command-only contact and secrets hygiene |
| `playbooks/preventive-verification.md` | `verify.sh` before merge |
| `playbooks/partner-enablement.md` | Host handoff after stand-down |
| `playbooks/controlled-change.md` | Blast radius and rollback before destructive edits |

**External reference (not in repo):** `/workspace/ecc` read-only armory; discover via `/workspace/ecc/search.sh`. Never duplicate ECC skills here.

**Read order for new deployment:** `doctrine.md`, then `../AGENTS.md`, then `toc-config.md`, then the playbooks above, then active `missions/<slug>/mission.md`, `intel.md`, and `board.md`.

**Write policy:** Operators append AARs; Lead proposes playbook drafts; Command promotes after Rule-of-Two (squad-native content only).

**Dashboard:** `./scripts/toc.sh`. Command runs it when the user asks for `TOC` or `give me the dashboard`.
