# A hidden capture held the cursor in an invisible box

2026-11-02

- **Saw:** the maintainer's cursor was held inside an invisible rectangle while an agent ran a Deadnight capture
  through `gds godot`; the capture's sound played, no window showed.
- **Cause:** `gds godot` starts Godot on a private Windows desktop, which keeps its window and the keyboard focus away,
  but the night captures the mouse (`Input.MOUSE_MODE_CAPTURED`) and Windows `ClipCursor` is not per desktop: the clip
  held the real cursor to the hidden window's rectangle. The launcher had been measured for focus and keys only.
- **Fix:** the launcher sets `GDS_QUIET=1` for the program and frees the cursor every 5 ms while it runs; the game
  never captures the mouse when `GDS_QUIET` is set. A test clips the cursor from the hidden desktop and samples the
  real one.
- **Docs:** [Windowed Godot without taking the focus](../godot/no-focus.md#the-cursor-clip-crosses-desktops).
