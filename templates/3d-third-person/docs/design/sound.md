# Sound

The buses, their volumes and the sounds 3D Third Person started with: a wind, a coin and footsteps.

## Buses

`default_bus_layout.tres` has `Master` and three buses sending to it: `SFX` for effects, `Ambient` for beds and `UI`
for menus (3 dB under the rest). An `AudioSettings` node in `main.tscn` holds each bus's volume as an inspector value
in dB; changing one applies to the audio server at once, in the editor and in a running game (the remote inspector),
and a settings screen sets the same properties. Give every sound player a `bus`.

## Where they play

The wind is the `Wind` player of `main.tscn` (autoplay, `Ambient`). The coin is the `Sound` node of `pickup.tscn`: one
of the four files each time a pickup is taken, then the pickup goes once it has played. The steps are `Footsteps`
(`gameplay/player/footsteps.tscn`, a child of `Player`): a step sounds each time a foot of the animated skeleton
lands, so it follows the walk, run, sprint and crouch-walk clips at any blend, and never when the character stands
still or is in the air. It has three `AudioStreamPlayer3D` nodes on `SFX`, each with its own volume and bus: `Step`,
`CrouchStep` (9 dB quieter) and `LandStep` (3 dB louder, played when the character lands). The pistol has a slot for a
shot sound (the `ShotSound` node of `weapon.tscn`) and nothing in it: the template ships no pistol sound, and
Deadnight's are not committed here because no licence entry shows that GDStudio made them. Put a file there and a shot
plays it at the muzzle.

## The sounds

| Sound | Files | Bus | Notes |
| --- | --- | --- | --- |
| Wind | `assets/audio/wind/wind_soft_1.ogg` | `Ambient` | 10.5 s, a seamless loop (the import sets `loop`), -33 LUFS |
| Coin pickup | `assets/audio/coin/coin_pickup_1..4.ogg` | `SFX` | 0.35 to 0.36 s: a shake of coins into a soft pop; four variants to cycle |
| Footsteps | `assets/audio/footsteps/footstep_hard_1..10.ogg` | `SFX` | single steps on a hard floor, 0.13 to 0.19 s, cycled for walk and run; a crouch step can be the same file, quieter |

All are levelled so that files of a set sit within 0.3 LU of each other (coin -20 LUFS-M, steps -29 LUFS-M) and none
peaks over -1 dBFS.

## Licence of the sounds: temporary

They were generated with ElevenLabs Sound Effects on the free tier, with the maintainer's agreement for now:
**attribution is required and they are not licensed for commercial use. Replace or relicense them before any
commercial release**, and name ElevenLabs on the Credits screen until then. Each folder's `LICENSE.md` lists its files,
prompts, lengths, model and plan.
