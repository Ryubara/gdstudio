# New agent definitions invisible to a running session

2026-11-01

- **Saw:** `.claude/agents/*.md` written mid-session; starting one failed with "agent type not found".
- **Cause:** Claude Code loads project agents when a session starts.
- **Fix:** restart with `claude --resume <session id>` (the conversation is kept).
- **Docs:** Agents (`docs/agents.md`).
