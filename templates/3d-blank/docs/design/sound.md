# Sound

The buses, their volumes and the wind that 3D Blank started with.

## Buses

`default_bus_layout.tres` has `Master` and three buses sending to it: `SFX` for effects, `Ambient` for beds and `UI`
for menus (3 dB under the rest). An `AudioSettings` node in `main.tscn` holds each bus's volume as an inspector value
in dB; changing one applies to the audio server at once, in the editor and in a running game (the remote inspector),
and a settings screen sets the same properties. Give every sound player a `bus`; a bus the game renames only loses its
slider.

## The wind

`assets/audio/wind/wind_soft_1.ogg`: a soft, even hush of air over grass, 10.5 s, a seamless loop (the import sets
`loop`), levelled to -33 LUFS so it stays a background under the effects. The `Wind` player of `main.tscn` plays it from
the start on the `Ambient` bus (its volume and bus are the node's own, and the `Ambient` slider of `AudioSettings` sets
the whole bed).

When the game quits, `AudioSettings` stops the players under its parent and waits for the audio thread to let go of them;
without that, a sound still playing at exit is reported as a leak (`ObjectDB instances were leaked at exit`), which a
test run's CI check fails on.

## Licence of the sounds

The wind was generated with ElevenLabs Sound Effects (`eleven_text_to_sound_v3`) on the studio's paid plan
(kit #1083), which allows commercial use under ElevenLabs' Sound Effects terms: it may be used in a game, combined with
other material, but not sold or shared on its own as a sound file or put in a sound library. No attribution is
required. `assets/audio/wind/LICENSE.md` lists the file, its prompt, length, model and plan.
