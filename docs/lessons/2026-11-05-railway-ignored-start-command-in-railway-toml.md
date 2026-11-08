---
areas: [backend, tools]
---
# Railway ran the Dockerfile's command, not the `startCommand` of the uploaded railway.toml

2026-11-05

- **Saw:** a throwaway bench service was uploaded with a `railway.toml` carrying `[deploy] startCommand = "sh
  /app/bench.sh"`; the deployment started the game server (`--server`) as the Dockerfile says.
- **Cause:** not established (the file sat at the stage root beside the Dockerfile, and `restartPolicyType =
  "NEVER"` was in the same table); the Dockerfile's `CMD` was what ran.
  or the file's own reference).
- **Fix:** put the command in the stage's Dockerfile (`CMD ["sh", "/app/bench.sh"]`) for a bench service, and keep the
  script and its settings inside the uploaded `game/` folder. The script prints `RESULT|<label>|<rep>|<json>` lines
  and ends with `sleep` so the container stays up; `railway logs --service <name>` returns them, and the service is
  deleted when the numbers are copied out.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#headless-server-image).
