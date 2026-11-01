# The screen stretched after a UI scale round trip

2026-11-01

- **Saw:** after 125% and back to 100%, a column was 1425 px tall and off centre.
- **Cause:** autowrap Labels report a tall minimum size while a container sizes them; a CenterContainer kept it.
- **Fix:** no autowrap in rows (trim with an ellipsis), and a round-trip test.
- **Docs:** [UI controls](../godot/ui-controls.md).
