# Audio

Draft for `docs/engines/godot/audio.md` in the kit (from Deadnight's sound design, issue 43). Game specifics are in Deadnight's
`docs/design/audio.md` and `docs/research/audio.md`.

## Making sounds with code {#making-sounds-with-code}

Original, committable sounds: numpy and scipy through `uv run --with numpy --with scipy`, one function per sound, a seeded
`numpy.random.Generator` (seed = CRC of the name and variant number), WAV to the pinned ffmpeg, Ogg Vorbis quality 4 with
`-fflags +bitexact -flags:a +bitexact` so two runs give byte-identical files. Building blocks that cover a lot:

- Gunshot: crack (high-passed noise, ~10 ms) + blast (low-passed noise with a falling cutoff) + body (a falling sine),
  soft-clipped, one slap echo, a decaying darkening noise as the room.
- Struck metal: damped sines at inharmonic ratios (1, 1.58, 2.31, 3.37, 4.9) plus a 3 ms noise transient.
- Voice: a jittery sawtooth through two vowel formant sets, crossfaded, with breath noise and low-passed-noise
  amplitude.
- Loops: make every part a whole number of cycles in the loop length; filter noise in the frequency domain; give hard
  envelopes a 2 ms attack.
- Convert a duration to samples with one rounding helper, not `int()`.

Without ears, check with log spectrogram sheets (`ffmpeg -i a.wav -lavfi showspectrumpic=s=700x180:legend=0:scale=log:fscale=log`),
peak levels and loop seams; judging taste is a human's job.

## Service shape that worked {#service-shape-that-worked}

Pooled `AudioStreamPlayer`/`AudioStreamPlayer3D` (no nodes created while playing); a pure `RefCounted` budget that hands
out slots (group limits, priority, a loudness margin so a voice is not stolen back and forth, per-sound cooldown) and
takes time as an argument so tests need no clock; a seeded generator for variant and pitch; `AudioEffectAmplify` added
to a bus at runtime for ducking (leaves the bus volume to the player's settings; remove it in `_exit_tree`); per-player
`attenuation_filter_cutoff_hz` and `volume_db` for occlusion; a `Callable` probe for what blocks sound.

**A stopped voice lingers until the mixer steps.** `AudioStreamPlayer.stop()` only marks the playback for removal; the
audio server holds it and its stream until the mixer thread has run a few times. Quitting soon after (a headless test,
a capture) then reports leaked `AudioStreamPlayback` objects and streams, at random and more often on a busy machine.
Before `quit()`, wait on the mixer, not on time: poll `AudioServer.get_time_since_last_mix()` once per frame and count
each fall, until about four mixes have landed (with a poll cap).

## The templates' buses and AudioSettings {#template-buses}

<!-- new section: the sections above are Deadnight's own buses and service; nothing said what a game made
     from a template starts with -->

3D Blank (and so 3D Third Person) ships `default_bus_layout.tres` with `Master` and three buses sending to it: `SFX`
(steps, pickups, hits), `Ambient` (beds such as the wind) and `UI` (menus, -3 dB: interface sounds sit under the
game's). A sound's player sets `bus` to one of them. The `AudioSettings` node in `world/world.tscn` (`core/audio_settings/`)
holds one `@export_range` volume in dB a bus; each setter calls `AudioServer.set_bus_volume_db` at once, so the remote
inspector tunes the mix while the game runs, a settings screen sets the same properties, and `@tool` makes the editor's
own mixer follow. A bus the project lacks is skipped (`AudioSettings.bus_volume_db` returns `NAN` for it), so renaming
one costs only its slider. The sounds are on [Sound effects](../../gamedev/audio/sound-effects.md).

- **Approach:** Put the volume of a bus in a node's exported property with a setter that writes `AudioServer`, not
  only in the Audio panel. **Watch out for:** the Audio panel edits the layout file in the editor and nothing in a
  running game, so a mix could not be tuned through the remote inspector; a setter also runs when the scene loads,
  before the buses may exist, so `_ready` applies them all again. **Seen:** gdstudio #835, 2026-11-08 (the node and a
  GdUnit4 suite that sets each export and reads the bus back).
- **Approach:** Give the player's own volume (a settings slider) a layer of its own on top of the mix:
  `AudioSettings.set_player_gain(bus, 0..1)` is static, remembers each bus's mix (the node's value, or the layout's
  when no node exists yet) and writes `mix + linear_to_db(gain)`, muting at 0. **Watch out for:** a slider that writes
  `AudioServer` directly is lost the next time the inspector or the remote inspector changes the node, and a menu
  before the game has no node to set; the gain must outlive scenes, so it is static, and a test resets it with
  `reset_player_gain()`. **Seen:** gdstudio #881, 2026-11-10 (`test_audio_settings.gd`, `test_settings_service.gd`).
- **Approach:** When sounds land before anything plays them, say so wherever the template is described (its design
  page, the pull request, the report): which files have no player yet and the issue that wires them. Search the scenes
  and scripts for `AudioStreamPlayer` and find where each one's `stream` comes from (the scene, or a script when it
  plays); pin both in a test. **Watch out for:** a player with no `stream` is no sound either: #852 shipped `ShotSound`
  empty and the report of its clip listed shots that were never heard; files under `assets/audio/` and a bus layout were
  read as working audio (a game was silent, and our handoff said 3D Blank played a wind no node played). Check each
  sound a report claims against the capture's track. **Seen:** gdstudio #835 and #837, 2026-11-08; #857, 2026-11-09
  (five shots, and a test that fails on a player with nothing to play).

- **Approach:** Play each template sound from a node with its own volume and bus (`Wind` on `Ambient` in `world/world.tscn`,
  `Sound` in `pickup.tscn`, `Step`, `CrouchStep` and `LandStep` in `footsteps.tscn`, `ShotSound` in `weapon.tscn`), and
  test that every player is on a template bus and every file in `assets/audio/` is named by a scene. **Watch out for:**
  an autoplaying sound leaks `ObjectDB instances were leaked at exit` when a process quits with it playing (every
  GdUnit run that frees the main scene), which CI's grep fails: `AudioSettings._exit_tree` stops the players under its
  parent and waits three mixes (`drain_mixer()`), and a suite that plays a sound calls `AudioDrain.stop_all()`.
  **Seen:** gdstudio #836, 2026-11-08 (one voice: 4 instances, 2 resources; the drain takes about 0.23 s for each main
  scene freed in a headless run).

- **Approach:** Level a template's sounds against each other by playing them in a game made from it with the real
  input under Movie Maker and reading the loudest 400 ms of each (the wind's integrated)
  ([Capturing sound](#capturing-sound)); keep the numbers set by ear fixed, move the others until none jumps out, and
  pin every volume in a test. **Watch out for:** a 3D player's volume is not one to one with what is heard: it darkens
  as it falls (the attenuation filter), so a bright coin lost 16 dB for 4 dB set, a pistol shot 1 dB per dB, and a
  camera fix moved it 6 dB; measure again after one. Hold a crouch with `Input.action_press`, not
  `player.crouching`, which physics rewrites and lands. The coin at 0 dB sat 30 LU over steps at -20.
  **Seen:** gdstudio #857, 2026-11-09 (steps -40, crouch steps -46, landings -37, coin -37, shot -31 LUFS-M at
  the mix, wind -50 integrated).

## Capturing sound {#capturing-sound}

- `--write-movie <absolute folder>/name.png --fixed-fps 10` also writes `name.wav`: 32-bit integer PCM, stereo, 48 kHz.
  The folder must exist. Mux with ffmpeg; analyse by reading `<i4`.
- The headless GdUnit4 run uses the dummy audio driver: players report `playing`, nothing is heard.
- The listener is the current `Camera3D` unless an `AudioListener3D` is current; a high capture camera makes distances
  wrong.
- Movie Maker writes only the mix. For per-bus stems (voice against guns against beds), put an `AudioEffectRecord` on
  each bus to measure and save its recording at the end; it works under Movie Maker (Deadnight #442 measured the voice
  4.8 LU under the guns and 10.6 LU over the beds that way).
- Transcribe generated voice takes with ElevenLabs Scribe to catch audio tags read aloud: performed sounds come back
  in brackets, spoken tags as words; Scribe bills the speech character quota. The whole voice pipeline, from
  casting to the game: [Voice lines](../../gamedev/audio/voice-lines.md).

- **Time a pattern of sounds at 60 fps, with no pictures.** A sound schedule follows the frames, so a recording at 10
  frames a second puts every start on a 0.1 s grid and stacks the quick ones in a frame. Use `--write-movie
  <abs>/x.avi --fixed-fps 60` and pull the track with `ffmpeg -i x.avi -vn -c:a pcm_s32le x.wav`; keep the PNG movie for
  pictures. To find a tone in a busy mix, correlate with a windowed carrier at its frequency (Deadnight's
  `tools/audio/beep_report.py`): a pure tone reads 0.58 and noise far less, and the tone's amplitude is its level in the
  mix whatever else sounds (Deadnight #680).

- **Approach:** End a capture scene by stopping every audio player and waiting a few frames before `quit()`
  (`AudioSettings.stop_players(get_tree().root)`, eight `process_frame`s), and read the log for `still in use`.
  **Watch out for:** under Movie Maker the mixer runs on the frames, not on its own thread, so
  `AudioSettings.drain_mixer()` waits its whole second for nothing, and a tour that quit with the wind playing printed
  `2 resources still in use at exit` and made the capture unusable as proof. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** A capture cut by `--quit-after N` before its scene ends needs that silence too: the templates'
  `AudioSettings` pauses the tree and stops every player at frame `N - 8`, told N by `++ --quit-after=N`, which
  `gds godot` and `gds capture frames` add to a Movie Maker run (`capture.tell_movie_end`); a plain Godot start still
  leaks. **Watch out for:** Godot removes the arguments it uses from `OS.get_cmdline_args()`, so a script cannot read
  where the capture ends, and `--quit-after` stops with no frame left to mix: whatever plays then (the looping wind, a
  coin picked up in the last second) is held, one Ogg voice being 4 leaked instances and 2 resources under `--verbose`.
  **Seen:** gdstudio #1030, 2026-11-10 (the action tour's 1200-frame capture, 4 resources: the wind and a coin).
- **Approach:** Capture to an absolute path of a folder that exists, smoke the run with `--quit-after 25` first, and for
  a long run write `x.avi`, pull the track with `ffmpeg -i x.avi -vn -c:a pcm_s32le x.wav` at once and delete the avi
  only after the wav exists; split a long capture into runs of a few minutes of sound. **Watch out for:** a relative
  path is relative to `--path`, not the shell, and the writer makes no folder, so a run with script errors still records
  every frame (1500 took 100 s) and no audio; an avi holds the audio inside, the track is finished only when the run
  ends, and `gds godot` stops a run at 900 s (an avi encodes at about 15 ms a frame). **Seen:** Deadnight, 2026-11-01
  (the relative path); Deadnight #718, 2026-11-03 (fix: runs of one case each, three at a time; five minutes of sound
  and 40 minutes were lost to a deleted avi).
- **Approach:** Prove a change left a sound as it was with a null test: the same scene captured before and after, both
  tracks read by their own sample width (`<i4` for Movie Maker), the difference measured window by window (a few seconds
  each) against each window's level, and the frames of any window that differs read to name what plays there.
  **Watch out for:** a script that read the 32-bit track as `int16` gave every window the same -10.8 dB and looked like
  a change; the whole action tour differed by -44 dB RMS only because its shots vary from run to run (its first 8 s),
  while its walking differed by -70 to -83 dB (16-bit rounding) and a crowd of walkers by -65 dB. **Seen:** gdstudio
  #1023, 2026-11-10.

## Layered gunshots and event-timed sounds {#layered-gunshots-and-event-timed-sounds}

- **Split a shot across voices.** Play the report (transient and body, 0.05 to 0.35 s), a long blast and a tail as
  three separate sounds with their own random variants and a few dB of level jitter; the combinations are many even
  with three files each, and a cooldown on the blast and tail of an automatic gun keeps twelve shots a second from
  becoming a wall of tails. Start the tail 40 to 70 ms late: the lot answers late.
- **Time steps to the clip, not the clock.** Read the animation's event frames from its spec (`clips.json`, frames over
  fps) and schedule each step's sound on a clock the owner steps (`advance(delta)`), tagged per player so putting the
  weapon away cancels what is left. A test steps 1 ms either side of each frame and needs no wall time.
- **Stamp a scheduled sound with its due time**, not the step's end: when one big step runs several items, `now()`
  inside an item must be that item's time, or timing assertions see the step size instead of the frame.
- **Hitscan impacts without a hit report:** a pellet that ended short of the weapon's range struck something; the
  zombies' hits arrive in the same batch just after, so queue the world impact for the next step and let each hit
  claim the pellet end nearest its point.
- **Generated sounds (ElevenLabs Sound Effects) vary wildly in level and lead-in.** Peaks from -22 to over 0 dBFS,
  the shot sometimes 0.3 s in, and no seed to repeat one. Trim to where it first rises within 34 dB of its peak,
  normalise to a fixed peak, fade the end, keep loops untrimmed, and keep the prompt with the file.

## Close and powerful sounds {#close-and-powerful-sounds}

Moved to [Mixing levels](audio-mixing/mixing-levels.md#close-and-powerful-sounds).

## Headroom without a limiter {#headroom-without-a-limiter}

Moved to [Mixing levels](audio-mixing/mixing-levels.md#headroom-without-a-limiter).

## A layer over a sound that already peaks {#a-layer-over-a-sound-that-already-peaks}

Moved to [Mixing levels](audio-mixing/mixing-levels.md#a-layer-over-a-sound-that-already-peaks).

## Is a sound heard under fire? {#is-a-sound-heard-under-fire}

Moved to [Mixing levels](audio-mixing/mixing-levels.md#is-a-sound-heard-under-fire).

## Warnings that must carry through cover {#warnings-that-must-carry-through-cover}

Moved to [Mixing levels](audio-mixing/mixing-levels.md#warnings-that-must-carry-through-cover).

## Starting sounds {#starting-sounds}

Measured in Deadnight's web build (Chrome, RTX 5080, #402): starting an Ogg Vorbis `AudioStreamPlayer` costs about
0.8 ms (headers and codebooks are read again on every `play()`), a PCM one about 0.3 ms, and a 40 s Ogg bed 43 ms. A
frame that starts six sounds pays six times.

- **Approach:** Decode short sounds (up to 2.5 s) once to `AudioStreamWAV` with `AudioStreamPlayback.mix_audio` while
  loading, cap sound starts per frame and defer the rest, start beds silent and paused then fade them in, and pool the
  effects and bodies a shot or kill makes; on a hitch task look for objects made inside the frame before profiling the
  GPU, and time each kind of frame (a shot, a kill) with a probe round its handler. **Watch out for:** `play()` on
  Ogg Vorbis re-reads the headers, so every shot and kill cost the single-threaded web build 6 to 8 ms while the
  resource count stayed flat and nothing looked like a leak. **Seen:** Deadnight #387, 2026-11-01 (fix: Deadnight #402,
  decode on load and a start cap; a GdUnit test counts nodes and objects over a run and fails on an allocation per kill).

Measured in the 3D Third Person template (desktop, Godot 4.7.2, gdstudio #1023): `AudioStreamPlayer3D.play()` of a
0.1 s mono Ogg Vorbis step costs about 250 µs, of the same samples as an `AudioStreamWAV` about 1 µs. `DecodedSounds`
of `gds_game` makes the WAV (`DecodedSounds.decoded(stream)`: short, non-looping Ogg Vorbis and MP3, at the mix rate,
16-bit, mono when the channels match, made once and shared); the template's `Footsteps` plays its steps through it.

- **Approach:** Decode a short sound that is started often (steps, shots, impacts) once and share the WAV across every
  node that plays it; warm it in `_ready` so the first play does not decode; prove the sound unchanged with a null test
  of two Movie Maker mixes, before and after. **Watch out for:** a crowd's footsteps paid the Ogg setup on every step
  (14 µs a walking character a frame on the desktop, 22 in Chrome: 0.35 ms a frame for 25), while the step list
  emptied cost 1.6 µs; the decode itself is a GDScript loop, 2 ms on the desktop and up to 16 ms in Chrome for four
  steps, so it belongs in the load, not the frame. **Seen:** gdstudio #1023, 2026-11-10 (footsteps 13 µs to 2.3 on the
  desktop, 22 to 7 to 8 in Chrome).

Measured again for shots and impacts (gdstudio #1067, Godot 4.7.2, `tools/bench/sound_start_bench.tscn` of 3D Third
Person: 50 starts a round, the median of nine rounds): the time is all the Vorbis set-up, neither the randomizer nor the
3D player. On the desktop an Ogg take starts in 250 µs, the same take as 16-bit PCM or QOA in 0.5 µs, a randomizer of
PCM takes in 1 µs; the weapon's `ShotSound` went from 244 to 1 µs and an impact through the `EffectEmitter` from 330 to
26 µs (19 of them the emitter's own slot search with 50 slots). In Chrome the shot went from 310 to 2 µs and the
impact from 364 to 18 µs. `DecodedSounds.decoded()` takes an `AudioStreamRandomizer` too (a copy holding decoded
takes, the spread and weights kept, rebuilt when the original changes), and decodes through the engine's own WAV
reader: the 23 takes of the pistol and the impacts in 13 ms on the desktop and 31 ms in Chrome, against 28 and 51 ms
for the old loop over every sample in script. Online (a server, seven `server_bot.gd --shoot` bots and
`predict_bot.gd`, 30 s on one machine, two runs each), a played shot cost the predicting client 663 µs and a hit 696 to
719 µs before and 216 to 252 and 240 to 339 µs after; with every sound switched off they cost 277 and 249 µs, so what is
left is the projectile, the flash and the mark, not the sound. The client's step p95 went from 1.7 to 1.9 ms to 0.9 to
1.3 ms.

- **Approach:** Set the stream of every player of a short, often-started sound through `DecodedSounds.decoded()`
  (the weapon when its definition is applied, an effect slot at each play, each reload step), decode while the level
  loads (`Weapon._apply_definition`, `EffectSlot.prepare`) and leave the definitions on the Ogg files. **Watch out
  for:** the first fix decoded only lone streams, so every shot and impact, an `AudioStreamRandomizer`, still paid the
  Ogg set-up (0.5 ms a played shot online in #906's bad-network run); at 1 to 4 µs a start no start cap or distance
  cull is needed. A test comparing a player's `stream` with a file compares with `DecodedSounds.decoded(file)`.
  **Seen:** gdstudio #1067, 2026-11-11 (tests fail on main: the weapon's players, a hit's voice and the reload steps
  hold Ogg takes).
- **Approach:** In the web build measure a sound start on what the player really plays, a lone file and a randomizer
  apart. **Watch out for:** a lone `AudioStreamWAV` or Ogg plays as a browser sample there (one
  `createBufferSource` a start, 85 to 110 µs even for PCM, 420 to 550 for Ogg), while an `AudioStreamRandomizer` is
  not sampled and plays as a stream Godot mixes (2 µs with PCM takes): our shots and impacts are randomizers, so they
  stay streams after the change, as before. A tap on the output reads silence for a sound stopped within four frames
  (the browser's output comes 50 ms or more after the start), and an emitter stopped before the wait reads none
  either: hold each round about 20 frames before stopping it. **Seen:** gdstudio #1067, 2026-11-11 (`tools/bench/sound_start_bench.py`
  counts the samples per case and taps the output).

A capped start returns no player: Deadnight's `Audio.play` answers null both for a dropped sound (too far, over its
voice limit) and for one put off to the next frame by the starts-per-frame cap, which then plays. Code that schedules
from the returned player (a gust that times the next one by its length) takes null as "length unknown", never as "not
played" (Deadnight #782).

## Swelling a bed with an event {#swelling-a-bed-with-an-event}

`Audio.set_bed_level(id, db)` is dB under the bed's own level and is clamped at 0: a bed cannot be raised over what its
trim gives it. A bed that an event should lift (a gust of wind over a located wind loop, Deadnight #809) needs
headroom: raise the sound's trim by the swell's size and rest the bed that much lower (`level = rest - headroom +
swell * size`), so the heard level at rest is what it was and the peak is `size` over it. A 3D loop has no such clamp
(its `volume_db` can go over its trim), so add the swell to its target. Read the swell in a tick that already runs (ten
times a second is smooth for a gust: a bed fades at 20 dB a second) and tell the bed only when the level moves.
Measure it as the bus's momentary loudness with and without the swell on the same seed, the same listener spot and only
the beds the place plays (`tools/audio/gust_levels.py` in Deadnight): a 6 dB swell on a loop that sits 10 dB or more under
the rest of the bus raised the bus by 0.3 to 0.6 LU, and 3 dB on the roof wind, the loudest thing in its room, by 1.3 to
2.0 LU. Size the swell for how far under the bus the loop sits, not for the dB it is given.

## Levelling an ambient bed {#levelling-ambient-beds}

<!-- new section: the sections around it are about a bed's swell and a sound's headroom; nothing said how to set or cut
a bed's level so it is heard against the quiet it plays in -->

A bed is judged by what the player hears of it in its own place, not by a loudness table of the files.

- **Approach:** Judge a bed in its own band against what shares that band, from a capture of the quiet stretch (beds
  alone, rules paused) before and after; when asked for less, cut both level and density, and take "N% quieter" from the
  original level as heard (half as loud is about -10 dB: see [Reading an ask](../../studio/asks.md#numbers)).
  **Watch out for:** a 25% cut became -2.5 dB checked by integrated loudness against other beds, but the crickets are a
  narrow 3.4 to 5.7 kHz tone nothing masks, 2.5 dB is about the smallest step an ear notices, and the chirp rate (25 a
  second) was never touched. **Seen:** Deadnight #382; Deadnight #781, 2026-11-03 (fix: level -6 dB and half
  the chirps, then -26 dB from the original; the rate counted from the recipe's own plan).
- **Approach:** To thin a generated bed keep the random draw and drop every other event (the scale at 1.0 must render
  the old file bit for bit), and set the entry's peak so each event keeps its level while `volume_db` carries the cut.
  **Watch out for:** narrowing the draw (`uniform(2.0, 4.2)` to `(1.0, 2.1)`) draws another set of insects (57% fewer
  chirps, not 50%), and a loop normalised to its peak gets 2 dB louder per chirp when fewer overlap. **Seen:**
  Deadnight #781, 2026-11-03 (fix: every other chirp dropped, the peak set per chirp).
- **Approach:** Before measuring a sound in a place, list what plays there from the place's own design page and start
  exactly that. **Watch out for:** a capture copied from the first map's wind capture started the crickets and highway
  the second map plays its sound in place of, so the swell looked small against a quiet that was never that map's, and
  six runs were done again. **Seen:** Deadnight #809, 2026-11-03 (fix: the capture starts only what the map starts;
  `--beds` adds the other map's two for the louder case).
- **Approach:** Level a bed that has to stand out (wind gusts over a base) from a capture of its own bus with that sound
  alone (`--solo`, the same seed as the run with the beds), reading each gust's momentary peak against the base median
  and the beds a moment before; the table of the files gives only the starting trim. **Watch out for:** a played 3D
  sound is not its file plus its trim: distance (`unit_size`), a random level draw and the night's own roll took 4 to
  6 dB, so gusts levelled from the files stood 3 to 5 dB over a base that does not lose them. **Seen:** Deadnight #782,
  2026-11-03 (fix: trims from the Ambience-bus capture; the seed picked by a probe of the plan so the proof shows every
  part).
- **Approach:** Level a wind bed by its integrated loudness over the whole loop and leave its gusts in: a wind is a
  slow rise and fall of level and colour with a whistle in the gusts, not an even bed
  ([A wind that reads as wind](../../gamedev/audio/sound-effects.md#wind)). Measure the movement as well as the level
  (the 100 ms level's p5 to p95, gusts a minute, spectral flatness, the share over 4 kHz) and make the loop 20 s or
  longer. **Watch out for:** a wind evened out to one level reads as white noise in the background: the template's
  generated wind was divided by its own level every 0.25 s, so it moved 0.7 dB with 29% of its energy over 4 kHz, and
  the maintainer heard a hiss, not wind; the regenerated loop moves 9.3 dB at the same -50 LUFS in the game, its lulls
  at -56 and its gusts at -46 LUFS-M. **Seen:** gdstudio #1101, 2026-11-11 (review of #1083's sounds).

## A crowd's voices (the dead) {#a-crowds-voices-the-dead}

- **Ration at the source, not only in the pool.** A per-zombie random timer plus one gate for the whole horde (one
  idle voice every 0.6 to 1.6 s, from the nearest three that are due) keeps 28 groaning zombies readable; the pool's
  group limit (six voices) is the second guard. Priority puts the cue that matters first: a snarl (65) or a swing (62)
  takes a voice from a groan (30), the boss has a group of its own so it is always heard, and feet are a group of
  their own below the player's steps.
- **Front from back.** Panning cannot tell them apart on two speakers. A low-pass by how far behind the listener a
  sound is (5 kHz at the side to 1.8 kHz straight behind) does: measured, the centre of energy of a horde was 1.2 kHz
  in front and 0.7 kHz behind, with 0 dB of left-right difference either way and about 6 dB at the side.
- **Time a cue to the blow:** start it `windup - lead` after the swing begins, where `lead` is how far into the file
  the effort peaks. Feet: advance the clip's phase at its own cadence (a foot per half cycle) from the same per-id
  phase the view starts the clip at.
- **`unit_size` is a loudness, not a size.** Inverse attenuation is `unit_size / distance`, above 1 inside `unit_size`,
  held only by `max_db` (3 dB): a boss with `unit_size` 14 roaring 3 m away was +13 dB and clipped the mix (268 clipped
  samples); 7, and the roar trimmed 6 to 7 dB, peaked at -0.4 dBFS. Find it with a per-second peak and clip count of the
  mix, not the file's peak.
- **Analyse a capture per second:** left minus right in dB, centre of energy, peak and clipped samples, against the
  act on screen; a loud case (the boss close by) shows a clip a whole-file peak hides in a long mix.
- **`AudioStreamPlayer3D` ignores trims up close.** Its inverse-distance attenuation boosts by `unit_size / distance`
  (a gun 1.7 m away with `unit_size` 14 is 18 dB up) and the only ceiling is `max_db`, +3 dB over the file by default.
  So every sound inside a few metres plays at the ceiling whatever its `volume_db`, and three layers of a shot sum past
  full scale. Set `max_db = volume_db + n` per play (0 for "the trim is the level") and leave far sounds alone. Measured:
  a shotgun trimmed to -23 dB still peaked at -5 dBFS in the mix until `max_db` was set. A loop whose level you move
  needs `max_db` moved with it.
- **A negative offset trims the near field only.** `max_db = volume_db - n` holds a close sound `n` dB under its trim
  and leaves everything beyond where the boost falls under that (about `unit_size * 10^(n/20)` metres) as it was: how a
  loud file (a scream, a board, a blast) is made to leave room for a gun shot without a quieter trim, which would also
  quiet it far away (Deadnight #753: 20 sounds, caps -0.5 to -9 dB, every file of them at most -9.8 dBFS up close,
  from -0.6 to -3). How much of a file's peak reaches the mix is not the file's peak: a voice 1.2 m ahead is 0 to 3 dB
  under its file (the pan), a 70 ms impact click is 10 to 14 dB under (its peak is high-frequency and the distance
  low-pass takes it), so a level rule built from file peaks over-cuts clicks. Measure each sound alone, in a window that
  ends where the next one starts (see [Close and powerful sounds](#close-and-powerful-sounds)).
- **A level capture needs a listener.** A Movie Maker recording with no `Camera3D` (or `AudioListener3D`) in the tree is
  silent: nothing hears the 3D players.

## Leaks at exit in a test run {#leaks-at-exit-in-a-test-run}

- **A passing GdUnit4 run can still print `ObjectDB instances were leaked at exit` and `resources still in use at
  exit`.** Nothing fails, so nobody looks. The lines belong to whichever suite left something alive: a test lambda that
  held itself through an array (a cycle that keeps the test script in use), or a night whose ambience beds only fade
  out when it is freed. Run the test folders one at a time with `--verbose` to see which stream or script it is. Cut
  the cycle at the end of the test, stop the audio after each test that builds a night, wait `Audio.wait_for_mixer()`
  once, and have CI grep the test log for `leaked at exit|still in use` (Deadnight #378).
- **The check can fail a passing run at random.** A process that quits at once (a test run: GdUnit exits itself)
  leaks whatever voice is playing or just stopped, because the audio server frees a playback only after its mixer
  has stepped a few times. A suite cannot wait after the last test, so wait in the audio autoload's `_exit_tree`:
  block the main thread, counting `AudioServer.get_time_since_last_mix()` falls (the mixer has its own thread). A
  child Godot that starts sounds and quits is a deterministic test for it. `--verbose` makes the engine list every
  leaked instance and resource, and CI keeps those lines as an artifact. One Ogg voice is exactly 4 instances and 2
  resources, which is how the CI counts read.

- **Approach:** Stop every voice, loops included, when the scene that owns it ends, and make the audio autoload wait on
  the mixer in `_exit_tree`; keep CI's grep for `leaked at exit|still in use` as it is. **Watch out for:** a looping bed
  that outlives its scene holds its stream, and a process that quits at once leaks the voice playing or just stopped
  until the mixer has stepped, at random and more often under load; people rerun until green and learn to ignore the
  check, and loosening the grep hides the next real leak. **Seen:** Deadnight #378, 2026-11-01; Deadnight #487,
  2026-11-02 (fix: the waiting `_exit_tree`; a test runs a child Godot that starts sounds and quits at once and fails
  on any leak line, as it did before the fix every time).

## Sound through windows, not walls (Deadnight #657) {#sound-through-windows-not-walls-deadnight-657}

The second map is a shut-in building with a yard outside, and the yard is heard only through the windows. One ray from
the listener to a source cannot say that (a wall with a gap in it blocks the ray unless it threads the gap), so the
router (`SmallMapWays`) asks the question the other way round:

- **Route through the windows of the listener's room.** For each window that the listener can see (a ray from the ear to
  just inside the opening) and whose outside can see the source, the sound's way is *listener to window plus window to
  source*. Take the window with the shortest way and the kinder state (boarded, open). Play the loop **at that window**,
  so it comes from the window's direction. An `AudioStreamPlayer3D` falls off as `unit_size / distance` (a boost inside
  `unit_size`, not `unit_size / (unit_size + distance)`, which is only `AudioService`'s voice ranking), so to be as loud
  as the whole way round, add `20 log(distance to the window / whole way)` and the window's cost. Rank windows by the
  whole way, not by that remainder, which is larger for a window farther away (a loop 1.3 m from the listener was 18 dB
  up, and a test checks that the engine's gain plus the extra equals the whole-way level). No window: play it where it
  is, quieter and duller, as through a wall. Outside the building: where it is.
- **Fences and the ground are not walls.** The rays read the same layers as the walls; ask again past a hit under the
  outside group by adding its `rid` to `exclude`, and exclude the windows' own blockers.
- **A bed that follows a room** needs a level, not only start and stop: `Audio.set_bed_level(id, db)` moves a bed's target
  (dB under its own level) at the bed's fade rates, and silence parks it like `stop_bed`.
- **Loops out of reach stop** (a 3D loop beyond its `max_distance` costs a voice for nothing) and start again at a stored
  offset; several copies of one wind loop in different corners start at different offsets and pitches so they are not
  one sound four times.
- **Prove it with a walk.** A Movie Maker capture of the player's camera through the rooms, with `STAGE` and `SOUND`
  lines printed on the movie's clock, and a script that reads the mix's level in each stage
  (Deadnight's `tools/audio/smallmap_levels.py capture`) shows the room tone, the yard behind boards, with the boards
  gone and behind a wall, each at its own level, in the real engine. A table from the bank, the files and the engine's
  fall-off (`... table`) gives how far each carries before the audible floor.

## Web: samples or streams {#web-samples-or-streams}

Godot 4.3+ plays an `AudioStreamPlayer` in a web export as a *sample* by default
(`audio/general/default_playback_type.web`): the browser's own `AudioBufferSourceNode`s. Measured on Deadnight's
export (#421) with a tap on the browser's audio output:

| | Samples (default) | Streams |
| --- | --- | --- |
| Bus effect (a -12 dB `AudioEffectAmplify`) | ignored (0.1 dB) | applied (-11.8 dB) |
| Player `attenuation_filter_cutoff_hz` (800 Hz on a bright sound) | ignored (0.0 dB) | applied (-31 dB) |
| Hard limiter on Master (ceiling -9 dB, tommy gun at -6 dBFS) | ignored (-6.0 dBFS) | not measured (native: -9.0) |
| Bus volume | works (-11.9 dB) | works (-11.6 dB) |
| 32 positional voices | 3.7 dB lower | reference |
| Main thread stalls 60 ms every 0.5 s, no threads build, 44 voices | no dropped blocks | 4 to 10% of 128-sample blocks dropped (crackle) |

- `audio/driver/output_latency.web` of 100 or 150 ms (default 50) did not stop the streams' crackle. 44 voices cost
  about 0.5 ms a frame either way.
- Anything designed with bus effects (a duck, a low-pass for occlusion) has to be heard in the browser before it is
  called done; with samples it is lost.
- To tap the output, wrap `AudioNode.prototype.connect` so connections to an `AudioDestinationNode` go through a
  `GainNode` feeding an `AudioWorklet` that counts zero blocks and sample jumps.

### What to build instead (Deadnight #423) {#what-to-build-instead-deadnight-423}

- **The duck is bus volume.** Effects and Ambience send to a `Duck` bus (listed before the buses that send to it);
  the service moves its volume. Measured through the real service in the browser: -11.9 dB for -12 asked, and desktop
  unchanged. Nothing of the player's sliders is touched.
- **A low-pass has a volume stand-in** where players are samples: a fully blocked sound took 4 dB more and one straight
  behind the listener 3 dB, chosen at run time (`players_apply_filters`). Stand-ins are middles, not matches: the
  low-pass costs a bright loop 13 dB and a rifle shot about 1 dB.
- **Measure through your own service**, not a bare player: a probe that plays one bright voice through the game's
  audio service and prints each effect against the open voice found all three effects missing in one run.
- **A probe's project setting** goes under `[audio]` without its `audio/` prefix, and the playback-type values are
  0 stream, 1 sample.

## Menu sounds {#menu-sounds}

The interface's sounds (which component takes one, weights, repetition, levels, touch, accessibility, how to wire a table
of roles and cues) are [Menu and interface sounds](../../gamedev/audio/ui-sounds.md). Two facts from making them:

- **A sound's name is not unique across folders.** A generator run with `--only deny` rendered the menu's new `deny`
  *and* the existing `world/deny_1.ogg`, overwriting the committed file. Give a new sound a name nothing has (grep the
  registries first) and run `git status` after a render: a file outside the folder you meant is the sign.
- **A bed under the menu plays the night's own files.** A bed is a looping Ogg stream (`start_bed`), never decoded to
  samples, so the menu's ambience (#926) plays `projector_1.ogg` and `crickets_1.ogg` under new, quieter sounds in the
  beds bank: no new file, 0 files for the night's warm-up to read (it finds both read), 2.9 and 3.7 ms to open them in
  the menu, 0.02 ms a frame to mix. Do not put a loop in a `deferred` bank: the bank's queue would decode 36 s of it to
  samples for nothing. A bed has a pool of players (`AudioService.POOL_BEDS`) and `start_bed` returns null, silently,
  when none is free: size it for the beds of the scene you leave still fading out plus the beds of the one you enter
  (the night's seven still fading plus the menu's two: `POOL_BEDS` 10, with a test that leaves a night at once and
  expects the bed).
- **Check a bed against the hints in the hints' band**, through a laptop and a phone speaker model
  ([the method](../../gamedev/audio/ui-sounds.md#4-level-the-bus-and-the-mix)).
- **Measure a menu sound on the real service**, one play at a time through the buses (a capture that plays each variant
  file of each row of the table, 0.7 s apart, 60 frames a second, no picture), and read peak and K-weighted loudness of
  every play from the recording; a test that predicts the peak from the decoded file, the trims and the bus agreed with
  the recording within 0.1 dB, so the level is pinned in a plain test.

**3D Third Person's menu sounds** (gdstudio #1100). The `MenuSounds` autoload (`ui/menus/menu_sound_service.tscn`,
script `MenuSoundService`) takes `UIAudio.handler` when it enters the tree, so every `gds_ui` control, the router and
the inventory's slots (`InventoryCell` sends `focus`, `hover` and `select` itself) sound through it. Its children are
twelve `AudioStreamPlayer` nodes on `UI`, one a sound, each an `AudioStreamRandomizer` decoded while loading
(`DecodedSounds`, [Starting sounds](#starting-sounds)): `Hint` (hover, focus), `Tick` (a slider step: the hint's files,
pitch from the value), `Press`, `Back` and `Refuse` (the press's files at 0.8 and 0.67), `Confirm` (a primary button),
`Tab` and `Select` (one family at two pitches), `ToggleOn` and `ToggleOff` (one switch at two pitches), `Open` and
`Close` (one swish). A role comes from the control's `ui_sound_role` metadata, else its `ui_sound_role()`, and the
script's `TABLE` maps role and cue to a player or to a written silence; the rules (one hint for hover and focus, a
`hint_gap`, nothing for a finger, a disabled control or a screen still moving, a swish only with no press just before it,
spaced ticks) are exports. 3D Blank has no menus, so it ships none. Levels in a game made from the template (real keys,
Movie Maker at 60 fps; loudest 400 ms at the mix, median of three plays): hint -45.4, tick -46.4, tab -40.4, select
-40.8, toggles -41.3 and -41.8, swish -42.0 and -43.3, press -37.3, back -38.9, confirm -33.0 LUFS-M, against a pistol
shot at -28.4; a hint's peak sits 23 dB over the wind's loudest 400 ms in the pause menu.

- **Approach:** Install a template's menu sound service as an autoload scene whose name differs from its script's
  `class_name` (`MenuSounds` and `MenuSoundService`, as `Settings` and `SettingsService`), give it
  `PROCESS_MODE_ALWAYS`, and let a suite instance its own copy (it takes the hook on entering the tree) and give the
  hook back to the autoload in `after_test`. **Watch out for:** the pause menu runs over a paused tree, where a player
  under a pausable node stops; an autoload and a class of one name do not both load. **Seen:** gdstudio #1100, 2026-11-11
  (`tests/ui/test_menu_sounds.gd`, `test_menu_sound_rules.gd`).

## Music that holds a long stay {#music-that-holds-a-long-stay}

A menu is left open, so the question is repetition, not the first minute (Deadnight #979;
[the game's page](https://github.com/Ryubara/deadnight/blob/main/docs/research/menu-music.md)). What worked, all
synthesised so there is no licence to ask about:

- **Three loops of unequal length, not one long one.** A 76 s pad, a 113 s sparse bell loop and a 47 s wind share no
  factor, so they come back together after about 4.7 days; each plays as its own bed (a looping stream), so a minute
  of the menu never repeats a minute before it. The method is Eno's *Music for Airports* (loops of differing
  lengths, no pulse, silence at least as long as the sound).
- **Every note in one scale over a held root and fifth**, so any meeting of the loops is in key. Tune each voice as a
  just ratio of the root, or its partials beat against its neighbours' (the D's third harmonic, 440.5 Hz, against an
  equal-tempered A at 440.0 Hz made a 5 dB tremolo every two to three seconds; read it from the file's own loudness
  curve).
- **A seamless loop from sines**: move each frequency to the nearest whole number of cycles in the loop, make every
  slow control (vibrato, level drift, harmonic opening) a whole number of cycles of it, and build reverb and echo as a
  circular convolution and a circular shift, so the last sample is followed by the first. Check the step across the seam
  against the largest step inside, and the level 400 ms either side.
- **Keep it dark** (nothing over 1.5 kHz to speak of) when interface hints live at 1.5 to 8 kHz; the pad's own
  loudness curve should move only a few dB over the loop. A phone speaker loses what is under 500 Hz, so a pad of low
  notes is silent there: give it harmonics and an octave above, and put the wind in the mids.

## A queue of lines said one after another {#a-queue-of-lines-said-one-after-another}

A helper that says "after the line that speaks" (`wait = director.wait()` at the call) is right for one caller and
wrong for two in the same instant: both read the wait of a free channel, both start together, and the second is refused
by the busy channel. Several lines due together (two players levelling up in one tick, Deadnight #1063) go through one
queue: say the front one, schedule the next after the channel's wait when it started, retry after that wait (at least
0.05 s, so a big test step cannot spin) when the channel held it back, drop it when the channel is free and it was
still refused (its cooldown, a downed speaker). Lines that arrive within a short window for the same player are
collapsed to the best one first, so a level, its tier and its item are one cheer. Test two speakers at once with
small steps, not one big step.
