---
areas: [web, tools]
---
# A backslash n in an export option became a line break in the page's script

2026-11-05

- **Saw:** an edit script appended a JavaScript readout to `html/head_include` in `export_presets.cfg` with
  `.join('\n')` in it; before the export was run, the line was read back and the `\n` was two characters in a quoted
  option value.
- **Cause:** Godot reads an option value as a quoted string with escapes, so `\n` becomes a real line break inside a JS
  string literal: a syntax error that kills the whole script, and the page looks fine without it.
- **Fix:** no backslash in `head_include`: `String.fromCharCode(10)` for a newline, single quotes only; grep the changed
  line for `\` and `"` before exporting, then read the readout on the exported page (Deadnight `phone_view.py`).
- **Docs:** `docs/godot/web-export.md` (phone page size section).
