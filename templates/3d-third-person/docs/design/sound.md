# Sound

The buses, their volumes and the sounds 3D Third Person ships: a wind, a coin, footsteps, a pistol (shot, empty click,
reload and draw), the fists' swing and bullet impacts. No menu sound ships yet.

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
(`gameplay/character/footsteps.tscn`, a child of `Player`): a step sounds each time a foot of the animated skeleton
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
`sounds_enabled`. An effect of your own can carry a sound too (a pickup's glint, a door's puff): see `EffectDef` in `addons/gds_game/effects/`.

## The sounds

| Sound | Files | Bus | Notes |
| --- | --- | --- | --- |
| Wind | `assets/audio/wind/wind_soft_1.ogg` | `Ambient` | 28 s, a seamless loop (the import sets `loop`): gusty wind round a building and through grass, gusts about every 7 s with a soft whistle in them, -33 LUFS |
| Coin pickup | `assets/audio/coin/coin_pickup_1..4.ogg` | `SFX` | 0.31 to 0.32 s: one coin's bright chime and sparkle, starting at once; four variants to cycle |
| Footsteps | `assets/audio/footsteps/footstep_soft_1..4.ogg` | `SFX` | four soft sneaker steps on stone, 0.10 to 0.24 s, a rounded thud with a little grit that suits any character and floor, cycled in a seeded order for walk, run, crouch and landing (same files, the three players' own volumes) |
| Fists | `assets/audio/fists/fist_swing_1..3.ogg` | `SFX` | three 0.15 to 0.17 s whooshes of a punch, the fists' `shot_sound` |
| Bullet impacts | `assets/audio/impacts/impact_default_1..3.ogg`, `impact_wood_1..3.ogg`, `impact_metal_1..3.ogg` | `SFX` | 0.15 to 0.31 s: a dry crack and grit on stone, a hard wooden crack and knock, a bright metal ping, played at -10 to -14 dB |
| Pistol shot | `assets/audio/pistol/pistol_shot_1..5.ogg` | `SFX` | five 0.10 s reports from Deadnight's House Pistol, synthesised (MIT), played with a small random pitch and volume spread |
| Pistol mechanics | `assets/audio/pistol/pistol_empty_1..2.ogg`, `pistol_reload_mag_out.ogg`, `pistol_reload_mag_in.ogg`, `pistol_reload_slide.ogg`, `pistol_draw.ogg` | `SFX` | a dry-fire click, the magazine out and in, the slide racked, a draw from a holster (0.06 to 0.30 s) |

Everything but the pistol shots was generated with ElevenLabs Sound Effects (`eleven_text_to_sound_v3`) by the kit's
`tools/audio/sfx.py` (kit #1083). The files of a set sit within 1 LU of each other, none peaks over -1 dBFS, and each
set is levelled so that it is heard in the game as loud as the sound it replaced (or, for the click and the reload,
which were hard to hear, a few LU under a shot); the pistol shots are full-scale files played at a trim.

## Levels

The player volumes are the template's defaults: steps -20 dB, crouch steps -29, landing -15, wind -20 (the
maintainer's, set by ear in a game made from the template), coin -16 and shot -22 (levelled against them by
measurement). Measured in the game (kit #1083, a game made from the template, the real input), the loudest 400 ms
at the mix: step -41, crouch step -47, landing -35, coin -39, shot -29, empty click -40, reload -35, draw -30, punch
-37, impacts -41 to -44 LUFS-M, and the wind -50 LUFS integrated, so no effect jumps out. A 3D player's volume is
not one to one with what is heard (it also darkens the sound as it falls), so measure again before you move one (the
kit's Godot audio page, "The templates' buses and AudioSettings", says how).

## Licence of the sounds

The pistol shots are GDStudio's own work (MIT, synthesised by Deadnight's code, nothing sampled): no attribution and
nothing to replace. Every other sound was generated with ElevenLabs Sound Effects on the studio's paid plan (kit #1083),
which allows commercial use under ElevenLabs' Sound Effects terms: the sounds may be used in a game, combined with other
material, but not sold or shared on their own as sound files or put in a sound library. No attribution is required. Each
folder's `LICENSE.md` lists its files, prompts, lengths, model and plan.
