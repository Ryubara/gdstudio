# tools

Captures, benches and probes, one folder per purpose (`tools/capture/`). They are left out of the export, so shipped
code never refers to `res://tools/`: the other way round is fine, tools may use the game.

`tools/capture/level_tour.tscn` records the level from a few angles for a pull request's screenshots.
