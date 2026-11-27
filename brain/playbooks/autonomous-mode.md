# Autonomous Mode

Standing loop for Command when `AUTONOMOUS_MODE=true` in `brain/toc-config.md` and the active `squad.env`. When the flag is `false`, Command acts only on explicit user missions.

## Loop

1. Command runs a standing cron check of mission status and open goals. `./scripts/toc.sh` is the status view.
2. Operators execute owned `board.md` tasks that are still open.
3. When no unfinished goals remain, Command uses `brain/`, project files, and the environment to define one new high-value goal. DMAIC (`dmaic-loop.md`) is one method. Any context-driven approach is valid.
4. Command delegates that goal to Lead. Lead decomposes it into owned `board.md` tasks.

## Guardrails

- Read `brain/toc-config.md` first. Delegation toggles stay off unless set.
- Pushback stays mandatory below 5 real AARs or 3 completed missions, even if a delegation toggle is `true`.
- Human approval gates still apply unless `DELEGATE_EXTERNAL=true` and pushback is ready.
- Idle goal generation does not skip medic-qa, comms relay, or mission limits.

## Cron shape

```
*/30 * * * * cd /path/to/repo && ./scripts/toc.sh
```

Command owns the schedule. Other operators do not install cron.

Read with `ooda-loop.md` and `dmaic-loop.md` at session start.
