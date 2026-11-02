---
areas: [web, godot]
---
# A browser test cannot see inside a Godot canvas

2026-11-01

- **Saw:** a Playwright run of a web export has no DOM to wait on: every screen is one `<canvas>`.
- **Cause:** Godot draws everything itself, so there is no element, text or role to query.
- **Fix:** a probe node that, only when `OS.has_feature("web")`, writes the top screen's name and a few counters to a
  window object (`JavaScriptBridge.create_object("Object")`, a few times a second). The test polls it with
  `page.evaluate`.
- **Docs:** Deadnight `docs/research/web-export.md`.
