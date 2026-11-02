# Behind Discord's proxy the web build read every 200 as "cannot reach the servers"

2026-11-02

- **Saw:** in the Discord Activity, Play together said "Could not reach the game's servers. Check your connection."
  while the backend logged 200 and 201 for the same requests; the same build worked in a plain browser (Deadnight).
- **Cause:** Discord's proxy (Cloudflare) gzips answers. The browser's fetch decodes them but leaves the
  `Content-Encoding: gzip` header, and Godot's `HTTPRequest` (`accept_gzip` on by default) decodes the body a second
  time, fails (a `stream_peer_gzip.cpp` error), returns a result other than `RESULT_SUCCESS` and status 0, which the
  game read as a network failure. The unreadable `/auth/discord` 200 also made the game send the same OAuth code
  again, and Discord answered `400 invalid_grant`.
- **Fix:** `HTTPRequest.accept_gzip = false` in the web build (Deadnight #475); trade an OAuth code once. Reproduce
  with a local HTTPS stand-in that gzips its answers, never only in a plain browser tab.
- **Docs:** [Web export](../godot/web-export.md#discord-activity-the-proxy-and-the-iframe).
