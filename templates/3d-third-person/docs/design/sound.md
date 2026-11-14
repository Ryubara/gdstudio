# Sound

The buses, their volumes and the sounds 3D Third Person ships: a wind, a coin, footsteps, a pistol (shot, empty click,
reload and draw), the fists' swing, bullet impacts and the menus' sounds.

## Buses

`default_bus_layout.tres` has `Master` and three buses sending to it: `SFX` for effects, `Ambient` for beds and `UI` for
menus (3 dB under the rest). An `AudioSettings` node in `world/world.tscn` holds each bus's volume as an inspector value
in dB; changing one applies to the audio server at once, in the editor and in a running game (the remote inspector), and
a settings screen sets the same properties. Give every sound player a `bus`.

## Where they play

The wind is the `Wind` player of `world/world.tscn` (autoplay, `Ambient`, -20 dB). **To use your own wind, change the
`stream` of that one player** (a seamless loop; the level and the bus stay as they are). The coin is the `Sound` node of
`pickup.tscn` (-16 dB): one of the four files each time a pickup is taken, then the pickup goes once it has played. The
steps are `Footsteps`
(`gameplay/character/footsteps.tscn`, a child of `Player`): a step sounds each time a foot of the animated skeleton
lands, so it follows the walk, run, sprint and crouch-walk clips at any blend, and never when the character stands
still or is in the air. It has three `AudioStreamPlayer3D` nodes on `SFX`, each with its own volume and bus: `Step`,
`CrouchStep` (-29 dB against the step's -20) and `LandStep` (-15 dB, played when the character lands). The weapon's
shot is the `ShotSound` node of `weapon.tscn`, three voices, played at the muzzle: its stream and volume come from the
held weapon's `WeaponDef` (`shot_sound`, `shot_volume_db`): the pistol's an `AudioStreamRandomizer` of five shots at
-22.5 dB, the rifle's of four at -23 dB, each with a pitch spread of 3 to 4% and a volume spread of 1 dB. A game's own
shot is another `shot_sound` in the definition.

A shot that lands plays the sound of its surface: each `ImpactSurface` under `Impacts/Surfaces` (`Default`, `Wood`,
`Metal`, `Target`) has an `effect` (an `EffectDef`) whose `sound` is an `AudioStreamRandomizer` of three variants on
`SFX`. The level's `EffectEmitter` plays it at the point from its pool (the effect's `max_instances` hits can sound at
once, a newer one takes the oldest's place). Change the `sound`, `sound_volume_db` or `sound_bus` in the `EffectDef`; a
hit's sound shows the change in the next hit. `Impacts.sounds_enabled` turns them all off, and so does the emitter's
`sounds_enabled`. An effect of your own can carry a sound too (a pickup's glint, a door's puff): see `EffectDef` in
`addons/gds_game/effects/`.

The menus' sounds are the `MenuSounds` autoload (`ui/menus/menu_sound_service.tscn`): twelve `AudioStreamPlayer`
nodes on `UI`, one a sound (`Hint`, `Tick`, `Press`, `Back`, `Refuse`, `Confirm`, `Tab`, `Select`, `ToggleOn`,
`ToggleOff`, `Open`, `Close`). Every menu control sends what happened (hover, focus, press, a slider step, a toggle,
a screen opening) and the service's table picks the player: a primary button confirms, Back and Esc are a lower press, a
settings tab and an option move, a switch says on and off with two pitches, a slider ticks higher as its value rises, a
screen opened with no press (Esc for the pause menu) swishes. Hover and focus on one control are one quiet hint, a
finger makes none, and a screen's swish gives way to the press that opened it. **To change a sound, change the
`stream`, `volume_db` or `pitch_scale` of its player**; a control of your own takes a role with a `ui_sound_role`
metadata (`tab`, `back`) or a `ui_sound_role()` method, and the table is `TABLE` in `menu_sound_service.gd`.

## The sounds

| Sound | Files | Bus | Notes |
| --- | --- | --- | --- |
| Wind | `assets/audio/wind/wind_soft_1.ogg` | `Ambient` | 28 s, a seamless loop (the import sets `loop`): gusty wind round a building and through grass, gusts about every 7 s with a soft whistle in them, -33 LUFS |
| Coin pickup | `assets/audio/coin/coin_pickup_1..4.ogg` | `SFX` | 0.31 to 0.32 s: one coin's bright chime and sparkle, starting at once; four variants to cycle |
| Footsteps | `assets/audio/footsteps/footstep_soft_1..4.ogg` | `SFX` | four soft sneaker steps on stone, 0.10 to 0.24 s, a rounded thud with a little grit that suits any character and floor, cycled in a seeded order for walk, run, crouch and landing (same files, the three players' own volumes) |
| Fists | `assets/audio/fists/fist_swing_1..3.ogg` | `SFX` | three 0.15 to 0.17 s whooshes of a punch, the fists' `shot_sound` |
| Bullet impacts | `assets/audio/impacts/impact_default_1..3.ogg`, `impact_wood_1..3.ogg`, `impact_metal_1..3.ogg` | `SFX` | 0.15 to 0.31 s: a dry crack and grit on stone, a hard wooden crack and knock, a bright metal ping, played at -10 to -14 dB |
| Pistol shot | `assets/audio/pistol/pistol_shot_1..5.ogg` | `SFX` | five 0.47 s shots: a sharp, bright crack with a punchy body and a short open-air tail, played with a small random pitch and volume spread (kit #1414) |
| Rifle shot | `assets/audio/rifle/rifle_shot_1..4.ogg` | `SFX` | four 0.29 s shots: a heavy, deep report with a crack on top and a tight tail, ending before the rifle's next-but-two shot takes its voice at 10 a second (kit #1414) |
| Menu sounds | `assets/audio/ui/ui_hint_1..3.ogg`, `ui_press_1..3.ogg`, `ui_confirm_1..2.ogg`, `ui_move_1..2.ogg`, `ui_toggle_1..2.ogg`, `ui_swish_1..2.ogg` | `UI` | a low wooden tock (0.05 s), a button click (0.07 to 0.14 s), a click into a two-note marimba chime (0.42 s), a wooden tab sliding in (0.13 s), a switch snap (0.06 to 0.07 s), a soft swish (0.36 to 0.39 s) |
| Pistol mechanics | `assets/audio/pistol/pistol_empty_1..2.ogg`, `pistol_reload_mag_out.ogg`, `pistol_reload_mag_in.ogg`, `pistol_reload_slide.ogg`, `pistol_draw.ogg` | `SFX` | a dry-fire click, the magazine out and in, the slide racked, a draw from a holster (0.06 to 0.30 s) |

Everything but the rifle's mechanics (Deadnight's synthesised M4A1 clicks, reload and draw, MIT) was generated with
ElevenLabs Sound Effects (`eleven_text_to_sound_v3`) by the kit's `tools/audio/sfx.py` (kit #1083). The files of a set
sit within 1 LU of each other, none peaks over -1 dBFS, and each set is levelled so that it is heard in the game as loud
as the sound it replaced (or, for the click and the reload, which were hard to hear, a few LU under a shot). The shots
(kit #1414) have their peaks held 12 dB over their loudest 400 ms by the recipe's limiter, so they are fuller at the
same peak, and a presence lift at 2 to 5 kHz keeps their crack through a 3D player's distance filter.

## Levels

The player volumes are the template's defaults: steps -20 dB, crouch steps -29, landing -15, wind -20 (the maintainer's,
set by ear in a game made from the template), coin -16 and the shots -22.5 (pistol) and -23 (rifle) (levelled against
them by measurement). Measured in the game (kit #1083, a game made from the template, the real input), the loudest 400
ms at the mix: step -41, crouch step -47, landing -35, coin -39, shot -29 (since kit #1414 the pistol's -27.5 and the
rifle's -28.7), empty click -40, reload -35, draw -30, punch
-37, impacts -41 to -44 LUFS-M, and the wind -50 LUFS integrated, so no effect jumps out. A 3D player's volume is
not one to one with what is heard (it also darkens the sound as it falls), so measure again before you move one (the
kit's Godot audio page, "The templates' buses and AudioSettings", says how).

The menus' sounds sit under the game's (kit #1100, the real keys in a game made from the template): hint -45, slider
tick -46, tab and option -40 to -41, switch -41 to -42, swish -42 to -43, press -37, back -39, confirm -33 LUFS-M, all
under the shot at -28; their players' volumes are pinned in `tests/ui/test_menu_sounds.gd`.

## Licence of the sounds

The rifle's empty clicks, reload steps and draw are GDStudio's own work (MIT, synthesised by Deadnight's code, nothing
sampled): no attribution and nothing to replace. Every other sound, the shots among them (kit #1414), was generated with
ElevenLabs Sound Effects on the studio's paid plan (kit #1083), which allows commercial use under ElevenLabs' Sound
Effects terms: the sounds may be used in a game, combined with other material, but not sold or shared on their own as
sound files or put in a sound library. No attribution is required. Each folder's `LICENSE.md` lists its files, prompts,
lengths, model and plan. The weapon pickup's two sounds (kit #889) are of that set.
