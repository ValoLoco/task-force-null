# DMAIC Loop

Recursive self-improvement cycle for the squad. Use when the same friction class or task bottleneck repeats.

## Phases

| Phase | Job |
|-------|-----|
| **Define** | Name the recurring friction class or bottleneck and state the target outcome in one sentence. |
| **Measure** | Capture baseline evidence: failure counts, retries, latency, handoff hops, or failed `scripts/verify.sh` output. |
| **Analyze** | Trace root cause from primary artifacts (logs, diffs, verify output). No guessed causes. |
| **Improve** | Apply the smallest verifiable fix in scope: process tweak, script guard, model override in `brain/models.md`, or draft playbook text. |
| **Control** | Lock the gain: run `./scripts/verify.sh`, update doctrine or a playbook draft, and feed Rule-of-Two if the fix must promote. |

## Run one full cycle

1. **Define** the friction class (e.g. "sync-armory dirties tree in verify").
2. **Measure** with concrete numbers or command output saved in the AAR.
3. **Analyze** with file paths and one primary cause line.
4. **Improve** with the minimal merged change or playbook note.
5. **Control** by re-running verify or medic-qa checks, then log AAR.

## AAR and Rule-of-Two

Log via `scripts/aar.sh`:

```text
Outcome: <did the fix hold under verify?>
Friction: <friction class name, same wording if repeating>
Fix: <what changed, path or command>
```

Command promotes to `brain/playbooks/<name>.md` only after **two** AARs cite the same **Fix** for the same **Friction** class (`brain/doctrine.md` Rule-of-Two).

Default playbook: read at session start with `ooda-loop.md` and doctrine.