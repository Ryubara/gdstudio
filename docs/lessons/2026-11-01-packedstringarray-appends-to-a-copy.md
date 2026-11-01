# PackedStringArray appends to a copy

2026-11-01

- **Saw:** a credits list stayed empty although every line was appended.
- **Cause:** packed arrays are value types: `var list := data.names; list.append(x)` changes a copy, not `data.names`.
- **Fix:** append to the property itself, or assign the copy back; a test caught it.
- **Docs:** Deadnight `docs/research/main-menu.md`.
