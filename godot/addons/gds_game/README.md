# gds_game

The gameplay code every GDStudio game can use, whatever template it came from: scripts only, no scene, no tuning
resource, no plugin and no autoload (a `class_name` under `addons/` is a global class without one). The kit's own Godot
project is its one source; `gds sync` writes it into every game's `game/addons/gds_game/` and the game's CI fails
(`gds sync --check`) when a copy differs, so a fix made here reaches every game by its next sync. A game never edits
its copy.

## Contents

| Folder | What |
| --- | --- |
| `effects/` | `EffectDef` (what an effect is), `EffectEmitter` (one capped pool of one-shot effects, found by `EffectEmitter.find(self)`), `EffectSlot` (one playing effect) |
| `trigger_zone/` | `TriggerZone`: an area that says when the first body comes in and the last one leaves |
| `testing/` | `ExportPins` (pins every export's default in a suite) and `InputSim` (key, pad and mouse events through the `InputMap`, waits in physics ticks); used by suites only |

The scenes that carry these scripts are the template's and the game's own (3D Third Person's
`gameplay/effects/effect_emitter.tscn`, `gameplay/trigger_zone/trigger_zone.tscn`): restyle and retune them there.

## What goes here

A part belongs here when any game of any template can use it unchanged (it names no template class, path, input
action or group but its own), it is code whose look and numbers come from exports or the scene it sits on, and its
suite proves it alone in the kit's project (`godot/tests/gds_game/`). Everything else is the template's. The rule and
how a file moves here are in the kit's `docs/studio/sync.md#addons`.
