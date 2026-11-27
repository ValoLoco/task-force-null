# Doctrine

## Standing Rules

1. YAGNI and Carbon Fiber: smallest working solution, stdlib and POSIX only in this template tooling.
2. Profiles and `AGENTS.md` are domain-agnostic; mission context lives only under `missions/<slug>/`.
3. One owner per active task on `board.md`.
4. Max handoff hops: two (see `playbooks/handoff-protocol.md`).
5. Never use em dashes in repo prose, docs, or comments.

## ECC Read-Only Armory

- Specialist depth may come from `/workspace/ecc` on the host only (reference path, not vendored).
- Locate skills with `/workspace/ecc/search.sh`; load **one** skill at a time, read in place.
- Do not copy ECC skill files into this repo, `brain/playbooks/`, or mission folders.
- Do not run ECC installers, hooks, or mutating setup scripts.
- Promoted playbooks must be squad-authored summaries, never ECC paste.

## Cross-Training Baseline

Every operator can read all brain and mission files and browse ECC read-only. Only Lead assigns; only Comms packages external; only Medic-qa gates release.

## Human Approval Gates (Hard Stop)

- External publish (web, email, social, customer channel).
- Destructive data or infra actions.
- Credential creation, rotation, or storage outside approved secret stores.
- Doctrine or mission limit exceptions.

## Rule-of-Two Promotion

A practice moves from AAR to `brain/playbooks/<name>.md` only after **two** independent AAR entries cite the same **Fix** for the same **Friction** class. Command records promotion in `aar-log.md` with timestamp and playbook path.