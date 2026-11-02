# Menu items at zero alpha were still focusable and clickable

2026-11-01

- **Saw:** during a menu's entrance animation, a key press focused Play and Enter opened it before the player had seen
  the item; the capture showed the transition to Play while the menu was still fading in.
- **Cause:** `modulate.a = 0` only hides a control. It keeps its `mouse_filter` and `focus_mode`, so it still takes
  focus, hover and clicks.
- **Fix:** while items are hidden or entering, set `mouse_filter` to ignore and `focus_mode` to none, remember the old
  values and give them back when the entrance ends; do not grab focus before then. Tests send real key, click and hover
  events during the entrance and assert nothing changes (Deadnight #380).
- **Docs:** [UI controls](../godot/ui-controls.md#menus-under-test).
