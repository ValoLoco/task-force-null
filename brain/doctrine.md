# Doctrine

## Default playbooks (session start)

Every operator reads at session start:

| Playbook | Use |
|----------|-----|
| `brain/playbooks/ooda-loop.md` | Standing decision cycle (Observe, Orient, Decide, Act) on every task turn. |
| `brain/playbooks/dmaic-loop.md` | Recursive self-improvement (Define through Control); log AARs and feed Rule-of-Two promotion. |
| `brain/playbooks/handoff-protocol.md` | Handoff packet and max-2-hops rule. |
| `brain/playbooks/autonomous-mode.md` | Idle goal loop when `AUTONOMOUS_MODE=true`. |
| `brain/playbooks/degraded-operations.md` | Armory, inference, or network outage fallbacks. |
| `brain/playbooks/mission-readiness.md` | Pre-mission gate from `setup-mission` before real work. |
| `brain/playbooks/intel-package.md` | Required fields on every Recon `intel.md` entry. |
| `brain/playbooks/comsec.md` | Command-only contact, secrets hygiene, channel discipline. |
| `brain/playbooks/preventive-verification.md` | `verify.sh` before merge. |
| `brain/playbooks/partner-enablement.md` | Host handoff so the capability remains after stand-down. |
| `brain/playbooks/controlled-change.md` | Blast radius and rollback before destructive edits. |

Read `brain/toc-config.md` with these playbooks at session start.

## Standing Rules

1. YAGNI and Carbon Fiber: smallest working solution, stdlib and POSIX only in this template tooling.
2. Profiles and `AGENTS.md` are domain-agnostic; mission context lives only under `missions/<slug>/`.
3. One owner per active task on `board.md`.
4. Max handoff hops: two (see `playbooks/handoff-protocol.md`).
5. Never use em dashes in repo prose, docs, or comments.

## Model Routing (best-fit-first)

1. Pick the model best suited to the task (complexity, required capabilities, and context needs).
2. If two models fit equally well, choose the cheaper one.
3. Step up or down based on observed results, not on cost alone.

Command and operators may update `brain/models.md` Learned Overrides and role bindings over time. Cost is a tiebreaker only, never the primary selector.

## ECC Read-Only Armory

- Specialist depth may come from `/workspace/ecc` on the host only (reference path, not vendored).
- Locate skills with `/workspace/ecc/search.sh`; load **one** skill at a time, read in place.
- Do not copy ECC skill files into this repo, `brain/playbooks/`, or mission folders.
- Do not run ECC installers, hooks, or mutating setup scripts.
- Promoted playbooks must be squad-authored summaries, never ECC paste.

## Cross-Training Baseline

Every operator can read all brain and mission files and browse ECC read-only. Only Lead assigns; only Comms packages external; only Medic-qa gates release.

## User interface

- **Command** is the only operator that may speak to the human directly.
- Lead, recon, builder, medic-qa, and comms use internal artifacts and handoffs only.
- Comms packages human-facing output and sends it to **Command**; Command routes approvals and relay. External send waits for human approval.

## TOC, delegation, and autonomous mode

`brain/toc-config.md` holds the machine-readable toggles. Dashboard command: `./scripts/toc.sh`.

When the user asks Command for `give me the dashboard` or `TOC`, Command runs `./scripts/toc.sh` and relays the output.

- `DELEGATE_BLOCKERS=true`: Command resolves blockers from `brain/` context.
- `DELEGATE_EXTERNAL=true`: Command approves external publishes and destructive actions.
- Both default to `false`.

Pushback is mandatory even when a toggle is `true` if `brain/aar-log.md` has fewer than 5 real AAR entries, or `missions/` has fewer than 3 completed missions (a `board.md` with at least one task, every status `done`). Command names the missing context and waits for the human.

`AUTONOMOUS_MODE=false` by default, in `brain/toc-config.md` and the active `squad.env`. When `true`, Command schedules standing cron jobs for mission tasks, operators execute them, and the idle-trigger loop in `brain/playbooks/autonomous-mode.md` runs. When `false`, Command acts only on explicit user missions.

## Human Approval Gates (Hard Stop)

External publish and destructive actions stop for the human unless `DELEGATE_EXTERNAL=true` and pushback is ready (at least 5 real AARs and 3 completed missions):

- External publish (web, email, social, customer channel).
- Destructive data or infra actions.

These always stop for the human:

- Credential creation, rotation, or storage outside approved secret stores.
- Doctrine or mission limit exceptions.

## Rule-of-Two Promotion

A practice moves from AAR to `brain/playbooks/<name>.md` only after **two** independent AAR entries cite the same **Fix** for the same **Friction** class. Command records promotion in `aar-log.md` with timestamp and playbook path.