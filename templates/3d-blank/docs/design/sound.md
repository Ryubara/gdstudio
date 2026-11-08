# Sound

The buses, their volumes and the wind that 3D Blank started with.

## Buses

`default_bus_layout.tres` has `Master` and three buses sending to it: `SFX` for effects, `Ambient` for beds and `UI`
for menus (3 dB under the rest). An `AudioSettings` node in `main.tscn` holds each bus's volume as an inspector value
in dB; changing one applies to the audio server at once, in the editor and in a running game (the remote inspector),
and a settings screen sets the same properties. Give every sound player a `bus`; a bus the game renames only loses its
slider.

## The wind

`assets/audio/wind/wind_soft_1.ogg`: a soft outdoor wind, 10.5 s, a seamless loop (the import sets `loop`), levelled
to -33 LUFS so it stays a background under the effects. The `Wind` player of `main.tscn` plays it from the start on the
`Ambient` bus (its volume and bus are the node's own, and the `Ambient` slider of `AudioSettings` sets the whole bed).

When the game quits, `AudioSettings` stops the players under its parent and waits for the audio thread to let go of them;
without that, a sound still playing at exit is reported as a leak (`ObjectDB instances were leaked at exit`), which a
test run's CI check fails on.

## Licence of the sounds: temporary

The wind was generated with ElevenLabs Sound Effects on the free tier, with the maintainer's agreement for now:
**attribution is required and it is not licensed for commercial use. Replace or relicense it before any commercial
release**, and name ElevenLabs on the Credits screen until then. `assets/audio/wind/LICENSE.md` lists the file, its
prompt, length, model and plan.
