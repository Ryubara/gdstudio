# The game server in a container

<!-- new section: multiplayer.md stood at its 50 KB limit (gdstudio #1123, from #910's report), so the section on
     the game server's image moved here; multiplayer.md keeps a short section that links to it -->

The game server as a headless Godot export in a container. Deploying it is on [Railway](../../../studio/railway.md);
the 3D Third Person server is on [The game server](../third-person/game-server.md).

## Headless server image {#headless-server-image}

`debian:bookworm-slim`, download the Linux Godot binary for the pinned version and verify its SHA-512 (the values are in
`tools.toml`), copy the project, run `godot --headless --path /app --import` once **at build time**, then
`godot --headless --path /app -- --server`. The app folder must be owned by the non-root user or the import cannot
write `.godot/`. Read `$PORT` (Railway) and bind plain `ws://`: TLS ends at the platform's edge.
Process 1 is `tini`, which passes the platform's SIGTERM on (Godot as process 1 ignores it and is killed after the
grace period). Deploying and testing it on Railway: [Railway](../../../studio/railway.md). The 3D Third Person server
starts with `godot --headless --path game -- --server` ([The game server](../third-person/game-server.md#template-server))
and its image, deploy and numbers are the template's `server/` ([The server image](../third-person/game-server.md#server-image)).

- **Approach:** Read a procfs file with `get_line()` (it is one line), treat an empty result as no data, and test
  Linux-only paths in the Docker image. **Watch out for:** procfs files report a length of 0 and
  `FileAccess.get_as_text()` reads `get_length()` bytes, so `/proc/self/stat` came back empty and a headless server
  logged `Out of bounds get index '11'` every 5 s; on Windows the path does not exist, so it showed only in the
  container. **Seen:** Deadnight, 2026-11-01 (fix: `get_line()` and an empty check).
- **Approach:** Cap Godot's worker pool in a server image (`threading/worker_pool/max_threads=2` in an `override.cfg`
  the Dockerfile writes) and read the process's processor share beside the step time. **Watch out for:** the pool has
  a thread a core and Jolt hands every physics step to all of them: an idle 3D Third Person server took 24% of a core
  on a 16-core machine (16 workers at 1.1% each) and 30% with 8 bots while its step read 0.6 ms; two threads gave 1.9%
  and 6.7% with the same step times, and Railway's hosts have 48 cores. **Seen:** gdstudio #910, 2026-11-11 (the
  template's `server/Dockerfile`).
