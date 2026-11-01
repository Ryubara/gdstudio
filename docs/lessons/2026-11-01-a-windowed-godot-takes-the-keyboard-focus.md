# A windowed Godot takes the keyboard from the person at the machine

2026-11-01

- **Saw:** every agent capture or autopilot run opened a Godot window in front and the maintainer's typing went into it.
- **Cause:** Godot activates its own window; no start flag prevents it (`SW_SHOWMINNOACTIVE`, `--position` off screen
  and the console wrapper's start all fail), `display/window/size/no_focus` needs a file in every game and leaves the
  window over the screen.
- **Fix:** start Godot on a private Windows desktop with `gds godot ...` (`gds capture frames` does): rendering and
  Movie Maker work, nothing reaches the person's desktop. A hook refuses a windowed Godot started straight from a shell.
- **Docs:** [Windowed Godot without taking the focus](../godot/no-focus.md).
