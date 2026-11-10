# Sound

The buses, their volumes and the sounds 3D Third Person started with: a wind, a coin, footsteps, a pistol shot and
bullet impacts.

## Buses

`default_bus_layout.tres` has `Master` and three buses sending to it: `SFX` for effects, `Ambient` for beds and `UI`
for menus (3 dB under the rest). An `AudioSettings` node in `world/world.tscn` holds each bus's volume as an inspector value
in dB; changing one applies to the audio server at once, in the editor and in a running game (the remote inspector),
and a settings screen sets the same properties. Give every sound player a `bus`.

## Where they play

The wind is the `Wind` player of `world/world.tscn` (autoplay, `Ambient`, -20 dB). **To use your own wind, change the
`stream` of that one player** (a seamless loop; the level and the bus stay as they are). The coin is the `Sound` node of
`pickup.tscn` (-16 dB): one of the four files each time a pickup is taken, then the pickup goes once it has played. The
steps are `Footsteps`
(`gameplay/player/footsteps.tscn`, a child of `Player`): a step sounds each time a foot of the animated skeleton
lands, so it follows the walk, run, sprint and crouch-walk clips at any blend, and never when the character stands
still or is in the air. It has three `AudioStreamPlayer3D` nodes on `SFX`, each with its own volume and bus: `Step`,
`CrouchStep` (-29 dB against the step's -20) and `LandStep` (-15 dB, played when the character lands). The pistol's
shot is the `ShotSound` node of `weapon.tscn` (-22 dB): an `AudioStreamRandomizer` of five shots with a pitch spread of
4% and a volume spread of 1 dB, three voices, played at the muzzle. A game's own shot is another `stream` in that one
node.

A shot that lands plays the sound of its surface: each `ImpactSurface` under `Impacts/Surfaces` (`Default`, `Wood`,
`Metal`, `Target`) has an `effect` (an `EffectDef`) whose `sound` is an `AudioStreamRandomizer` of three variants on
`SFX`. The level's `EffectEmitter` plays it at the point from its pool (the effect's `max_instances` hits can sound at
once, a newer one takes the oldest's place). Change the `sound`, `sound_volume_db` or `sound_bus` in the `EffectDef`; a
hit's sound shows the change in the next hit. `Impacts.sounds_enabled` turns them all off, and so does the emitter's
`sounds_enabled`. An effect of your own can carry a sound too (a pickup's glint, a door's puff): see `gameplay/effects/`.

## The sounds

| Sound | Files | Bus | Notes |
| --- | --- | --- | --- |
| Wind | `assets/audio/wind/wind_soft_1.ogg` | `Ambient` | 10.5 s, a seamless loop (the import sets `loop`), -33 LUFS |
| Coin pickup | `assets/audio/coin/coin_pickup_1..4.ogg` | `SFX` | 0.35 to 0.36 s: a shake of coins into a soft pop; four variants to cycle |
| Footsteps | `assets/audio/footsteps/footstep_soft_1..4.ogg` | `SFX` | four soft, low thuds of 0.08 to 0.13 s that suit any character and floor, cycled in a seeded order for walk, run, crouch and landing (same files, the three players' own volumes) |
| Bullet impacts | `assets/audio/impacts/impact_default_1..3.ogg`, `impact_wood_1..3.ogg`, `impact_metal_1..3.ogg` | `SFX` | 0.22, 0.26 and 0.45 s, synthesised by `tools/audio/impact_sounds.py` (MIT, seeded): a dry smack and thud, a hollow knock and a splinter's tick, a ping and a short ricochet whine; peak -6 dBFS, played at -10 to -14 dB |
| Pistol shot | `assets/audio/pistol/pistol_shot_1..5.ogg` | `SFX` | five 0.10 s reports from Deadnight's House Pistol, synthesised (MIT), played with a small random pitch and volume spread |

The generated files are levelled so that files of a set sit within 0.3 LU of each other (coin -20 LUFS-M, steps -33
LUFS-M) and none peaks over -1 dBFS; the pistol shots are full-scale files played at a trim.

## Levels

The player volumes are the template's defaults: steps -20 dB, crouch steps -29, landing -15, wind -20 (the
maintainer's, set by ear in a game made from the template), coin -16 and shot -22 (levelled against them by
measurement). Measured in the game, the loudest 400 ms at the mix: step -40, crouch step -46, landing -37, coin -37,
shot -31 LUFS-M, and the wind -50 LUFS integrated, so no effect jumps out. A 3D player's volume is not one to one with
what is heard (it also darkens the sound as it falls), so measure again before you move one (the kit's Godot audio
page, "The templates' buses and AudioSettings", says how).

## Licence of the sounds

The pistol shots are GDStudio's own work (MIT, synthesised by Deadnight's code, nothing sampled): no attribution and
nothing to replace. The coin, the steps and the wind are temporary: they were generated with ElevenLabs Sound
Effects on the free tier, with the maintainer's agreement for now:
**attribution is required and they are not licensed for commercial use. Replace or relicense them before any
commercial release**, and name ElevenLabs on the Credits screen until then. Each folder's `LICENSE.md` lists its files,
prompts, lengths, model and plan.
