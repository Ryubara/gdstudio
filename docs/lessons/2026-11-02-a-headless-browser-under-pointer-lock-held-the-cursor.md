# A headless browser under pointer lock held the cursor in an invisible box

2026-11-02

- **Saw:** with every Godot already `--headless` or under `gds godot`, the maintainer's cursor was again trapped in an
  invisible box at the top left of the screen until Esc. Agents were running Deadnight's Playwright web probes
  (`tools/web_smoke/hip_fire.py` drives the mouse under pointer lock) at the time.
- **Cause:** the page takes pointer lock and headless Google Chrome (`channel="chrome"`, the probes' `--gpu` mode)
  calls `ClipCursor` on its hidden window: measured `(17, 68, 864, 541)` for the whole lock. Esc ends the lock and the
  clip. Playwright's default headless shell did not clip. The quiet-run rule covered Godot only; a browser takes the
  mouse the same way, and the clip crosses desktops (on the private desktop without the guard: the same rectangle for
  about 0.5 s).
- **Fix:** `gds quiet [--timeout S] -- <command>` runs any command and everything it starts on the private desktop
  with the cursor freed every 5 ms (`gds godot` is now built on it): 0 of 777 samples held, the lock still took. The
  hook refuses a `tools/web_smoke/*.py` or Playwright run not wrapped in it.
- **General:** protect the person at the machine from *every* local program that can take the mouse or keyboard, not
  the one that was reported. When a rule names one program (Godot), ask which others do the same thing (browsers,
  Electron apps, game clients) and cover them by behaviour, not by name.
- **Docs:** [Browser probes and any other program](../godot/no-focus.md#browser-probes-and-any-other-program-gds-quiet),
  [web export](../godot/web-export.md).
