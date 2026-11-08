# tools

Captures, benches and probes, one folder per purpose (`tools/capture/`, `tools/web_smoke/`). They are left out of the
export, so shipped code never refers to `res://tools/`: the other way round is fine, tools may use the game.

- `tools/capture/level_tour.tscn` records the level from a few angles for a pull request's screenshots.
- `tools/capture/walkthrough.tscn` plays the character through the map by pressing the input actions, for a clip.
- `tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touches (run it under
  `gds quiet`; the command is in its header).
