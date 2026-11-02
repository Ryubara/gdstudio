---
areas: [blender, tools]
---
# Blender's download site refuses scripts

2026-11-01

- **Saw:** downloads from download.blender.org returned a browser-check page, not the file.
- **Cause:** the site sits behind a bot check.
- **Fix:** the official mirrors (same checksum file), pinned in `tools.toml`.
- **Docs:** [Workspace](../workspace.md#tools).
