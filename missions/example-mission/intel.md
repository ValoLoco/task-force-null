# Intel

## Verified Findings

| ID | Finding | Source | Confidence | Updated |
|----|---------|--------|------------|---------|
| F-1 | Repo root contains profiles, brain, missions, scripts, systemd | tree listing | verified | 2026-11-27 |
| F-2 | Router maps keywords to six operator roles | scripts/router.py | verified | 2026-11-27 |

## Open Questions

| ID | Question | Owner | Blocking |
|----|----------|-------|----------|
| Q-1 | Target host OS for systemd user unit? | recon | no |

## Risk Register

| ID | Risk | Mitigation |
|----|------|------------|
| R-1 | Wrong MISSION_SLUG in squad.env | start.sh validates active mission |