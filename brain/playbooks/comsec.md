# COMSEC

Channel discipline and secrets hygiene. Command is the only operator who speaks to the human. Comms drafts. Command relays.

## Contact

- User dialogue goes through Command only.
- Other operators use internal handoffs (`handoff-protocol.md`).
- External publish waits for the human, unless `DELEGATE_EXTERNAL=true` and pushback is ready (`brain/toc-config.md`).

## Secrets

- Never print secret values in logs, chat, AARs, or commits.
- Store API keys in gitignored `.env`.
- On Unix, `.env` is mode `600`.
- Empty setup prompts keep existing keys.
- Credentials, rotation, and new secret stores still need the human (`brain/doctrine.md`).

## Channels

One approved channel per outbound package. Name the audience, the artifact, and the approval state in the handoff.

Read with `ooda-loop.md` at session start.
