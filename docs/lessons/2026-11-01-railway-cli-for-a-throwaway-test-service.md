---
areas: [backend, tools]
---
# Deploying a throwaway Dockerfile service with the Railway CLI

2026-11-01

- **Saw:** nothing wrong; this is the shortest path that worked.
- **Cause:** n/a.
- **Fix:** from the folder holding the Dockerfile: `railway init -n <project>`, `railway add --service <name>`, `railway
  up --ci -s <name>` (remote build, about a minute), `railway domain -s <name>` (public `*.up.railway.app`, TLS at the
  edge, so clients use `wss://`), `railway logs -s <name>`. The region is in `railway status --json` under
  `multiRegionConfig`; the edge that answered is the `x-railway-edge` response header. `railway down -s <name> -y` stops
  it and keeps the project. Railway documents HTTP, WebSocket and a TCP proxy only: assume no inbound UDP.
- **Docs:** [Multiplayer](../godot/multiplayer.md#headless-server-image).
