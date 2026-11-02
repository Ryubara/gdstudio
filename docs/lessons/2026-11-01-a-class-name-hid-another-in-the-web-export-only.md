---
areas: [web, godot]
---
# A class name hid another one, only in the web export

2026-11-01

- **Saw:** the web export printed `Parse Error: Class "NeonSign" hides a global script class` and could not load the
  script; the editor, a headless import and the capture runs had shown nothing.
- **Cause:** a new lot script and an older UI skin script both said `class_name NeonSign`.
- **Fix:** rename the new one (`LotNeonSign`), and grep for `class_name <Name>` before choosing one.
- **Docs:** [Compatibility lighting](../godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light).
