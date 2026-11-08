---
areas: [godot, net]
---
# A Godot server image could not import its project

2026-11-01

- **Saw:** `docker build` printed "Could not create project data directory (res://.godot)", and the container then
  failed with parse errors on every script that uses a `class_name`.
- **Cause:** `WORKDIR /app` creates a root-owned folder; the non-root user could not create `.godot/` in it.
- **Fix:** create `/app` and `chown` it to the game user before `COPY` and the build-time `godot --headless --import`.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#headless-server-image).
