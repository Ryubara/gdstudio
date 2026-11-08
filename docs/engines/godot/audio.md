# Audio

Draft for `docs/engines/godot/audio.md` in the kit (from Deadnight's sound design, issue 43). Game specifics are in Deadnight's
`docs/design/audio.md` and `docs/research/audio.md`.

## Making sounds with code

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

## Service shape that worked

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

- **Approach:** Capture to an absolute path of a folder that exists, smoke the run with `--quit-after 25` first, and for
  a long run write `x.avi`, pull the track with `ffmpeg -i x.avi -vn -c:a pcm_s32le x.wav` at once and delete the avi
  only after the wav exists; split a long capture into runs of a few minutes of sound. **Watch out for:** a relative
  path is relative to `--path`, not the shell, and the writer makes no folder, so a run with script errors still records
  every frame (1500 took 100 s) and no audio; an avi holds the audio inside, the track is finished only when the run
  ends, and `gds godot` stops a run at 900 s (an avi encodes at about 15 ms a frame). **Seen:** Deadnight, 2026-11-01
  (the relative path); Deadnight #718, 2026-11-03 (fix: runs of one case each, three at a time; five minutes of sound
  and 40 minutes were lost to a deleted avi).

## Layered gunshots and event-timed sounds

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

A gun "sounding distant" is measured on a recording of the real shot through the real buses, not read off the files
(Deadnight #455):

- Measure per sound: peak, loudness (LUFS) against the bed it plays over, the share of energy in the first 50 ms,
  band energies, and the spread of pitch and level across a burst. Give every family of sounds one written pitch and
  level rule and pin it in a test.
- A centred sound in an `AudioStreamPlayer3D` is 6 dB under the same file in an `AudioStreamPlayer` (the engine's 3D
  pan law): the player's own gun plays flat.
- A hard-clipped file decodes from Ogg Vorbis up to +1.5 dB over its PCM peak (ffmpeg `astats` on the decoded float):
  leave 2 to 3 dB of headroom in the trim.
- Never put a sound's power in a bus effect: the web build plays samples, which ignore bus effects and the distance
  filter (see [Web: samples or streams](#web-samples-or-streams)).
- ffmpeg's `ebur128=framelog=verbose` prints its momentary values only at `-v verbose`.

- **Approach:** Record a sound that must read close through the real service and measure peak, LUFS against its bed, the
  first-50 ms share, bands and the spread across a burst; give each family one written pitch and level rule pinned in a
  test; play own sounds flat; never put power in a bus effect. **Watch out for:** closeness is a property of the
  recording through the buses, and we had measured only that nothing clipped: the tommy gun had 33 % of its energy in
  the first 50 ms and nothing under 120 Hz, every gun peaked 5 to 13 dB under full scale, the own gun was a centred 3D
  voice (6 dB down) and pitch moved up to 3.4 semitones across a burst. **Seen:** Deadnight #407, 2026-11-02 (fix:
  Deadnight #455, one close report with a short quiet tail, own shots flat, one pitch and one level rule, a bench scene
  that measures it natively and in the browser).
- **Approach:** When one recording is cut into a window per sound, end each window where the next sound starts and give
  every sound its file's length plus 0.2 s; read one sound twice (alone, then with the others) before trusting a table
  of them. **Watch out for:** a constant gap lets a long sound's window hold its successor's onset and a short one's hold
  the blast before it: the dead's voices read 0.0 dBFS (the engine's ceiling), so the caps were set 3 dB too deep, and a
  70 ms impact read -0.6 dBFS one run and -16.7 the next. **Seen:** Deadnight #753, 2026-11-03 (fix: a `--close` capture
  and windows that end at the next play; the pinned table of close levels comes from that clean run with the caps it
  was measured at, so a cap moved without measuring again fails a test).

## Headroom without a limiter

Measured in Deadnight #718, where the player's own gun peaked at -1.5 dBFS and anything landing on a shot clipped:

- **A limiter on Master does not act in the web build.** A probe (a tommy gun fired without a break through the audio
  service; a hard limiter, ceiling -9 dB, on Master; then Master turned down 9 dB) read -6.0 dBFS plain, -9.0 with the
  limiter and -15.0 turned down natively, and -6.0, -6.0 and -15.0 in headless Chromium with a tap on the page's
  output: only the bus volume acts there (`tools/web_smoke/limiter_web.py`, `tools/bench/audio_limiter_probe.tscn`).
  So the headroom is in the trims. It also keeps the mix a plain sum, which the audibility measurement relies on.
- **Peaks add.** The loudest continuous source (the player's own gun) peaks at least 4.5 dB under full scale alone, so
  one more sound at -6 dBFS lands at -2 or lower rather than at full scale. Check the sum: fire that source without a
  break and play each class of other sound on it (a teammate's reload, a teammate's gun, the dead's voices, doors and
  boards, a blast), then count the samples over -1 dBFS (`tools/audio/headroom.py`, from the capture
  `tests/captures/audio_headroom.tscn`).
- **Measure on a warm pool and on a clean one.** Pooled players keep what the last sound set: Deadnight's
  `max_db` of a sound with no near cap stayed at the gun trim that last used the slot, so the same zombie voice read
  4 to 10 dB higher played alone than after the guns, and moved with the gun trims (Deadnight #718, fixed in #752, with
  a test that plays a capped sound and then an uncapped one on one slot). Play each cell alone and after
  the others, and set every pooled property on every play.
- **A sound's variant files differ by 3 to 9 dB in peak** (a zombie voice's loudest and quietest take): to bound the
  worst case point the definition at one file for each play (`path_format = def.path_for(k)`, `variants = 1`) and put
  it back.
- **Measure on the merged tree, before and after from one base.** Merge `main` before measuring a mix and keep a second
  worktree on `origin/main` for the "before" runs: two sets of headroom measurements (40 minutes each) were made before
  main gained a reload rework and a new shotgun, and had to be redone (Deadnight #718). Capture in runs of a few
  minutes of sound (see [Capturing sound](#capturing-sound)).
- **A gain cut is not a loss of punch.** Lowering a trim moves loudness and peak together, so the crest factor of a
  burst is unchanged; what limits the cut is the loudness rule against the beds (Deadnight: 14 LU for a shot, 17 for a
  burst).
- **A limiter in the recipe lowers the crest, and the close peak moves by more than the crest it took off.** A sharp
  sound (a board snapping, a door's bolt: 16 to 23 dB between its loudest 400 ms and its peak) held under a peak
  ceiling is quiet, and the way to a louder body at the same peak is a look-ahead limiter in the synthesising recipe
  (a web build ignores the bus kind). Use a smooth gain curve (the minimum of the needed gain over a 2 ms window, then
  its average over the same window: never steps, never rises into a peak, so Vorbis does not overshoot a flat top) and
  hold the highest sample a number of dB over the loudest 400 ms, so every variant gets the same crest. Then measure the
  close peak again: the distance low-pass had been taking the crack's peak off, so the limited file's peak (the body's)
  reaches the mix 0 to 3 dB higher than the old close peak, and the old cap does not carry over: after a change to a
  file's dynamics, record the close peak again and pin the new table. Deadnight #762: crest of a file 15 to 23 dB
  before, 12.6 to 16.6 after; the loudest 400 ms at 1.2 m up 3.5 to 6.4 LU at the same -9.9 dBFS.
- **Tune a reshape on a model of the bench, then let the bench decide** (Deadnight #761, the flare gun: crest 20 dB, so
  a trim for -5.5 dBFS broke the 17 LU burst rule; limited and given a fuller body it is 17.5 dB, burst 17.9 LU over the
  beds at a -5.2 dBFS peak). Render the files with the real pipeline, Vorbis-encode and decode them with the pinned
  ffmpeg, play the bench's burst, and put the shots where the bench's recording has them: the integrated loudness of a
  sharp sound depends on where the 400 ms blocks fall (the flare gun read -17.3 LUFS offline against the bench's -18.6
  until the model's shots sat at the onset the recording shows, 0.0687 s in, with a spread of +-10 ms). Three more traps
  on the way: a driven, limited file decodes up to 3 dB over its PCM peak (a -2 dBFS file at +1.2), so set the trim from
  the decoded peak; a low sine is the cheapest way to loudness at a given peak and turned a pop into a boom (91 percent
  of its energy under 250 Hz against the other guns' 44 to 69), so read `low_end_share` and the centroid in the bench
  beside the LU; and a table that pins the bench's numbers should pin the files too (a SHA-256 of each, checked by the
  test), or a re-rendered file leaves the table describing other sounds.

## A layer over a sound that already peaks

Deadnight #791: one futuristic layer that plays over the shot of any upgraded weapon, so seventeen weapons need no
recipe each. Peaks add, so it has to be heard without taking the headroom the shots were given (the first layer lifted a
rifle's burst peak 0.7 dB and was not heard):

- **Put it where the sound is not.** A gun's energy is front-loaded (0.9 of it in the first 50 ms for a close shot), so
  start the layer 30 ms late (in the file: a game that schedules it has the same delay on every platform) and give it a
  ring that lasts half a second in a band the gun is thin in (2 to 8 kHz).
- **Make its body dense, not its peak high.** `limit_crest` once leaves the crest a few dB over what was asked, since the
  limit also lowers the loudest 400 ms it is read against: run it three times to hold a crest of 7 dB.
- **Choose the trim on a model of the bench, then let the bench decide.** Add the rendered layer to the recorded plain
  shots at a few gains (resample to the recording's 48 kHz, place it at each shot's measured onset) and read three
  numbers against the plain shot: the peak added (at most 1 dB: nothing may pass the headroom rule), the tail's
  level (0.08 to 0.5 s after the onset) and the 2 to 8 kHz band's energy there, which say whether it is heard.
- **A pitch rule still holds for the layer:** variants within 2 percent of one note, one level rule, one voice group of
  its own with a cooldown, so an automatic weapon plays a ring and not a rattle.
- **FM zaps alias.** A sweep with an FM index of 2 to 3 whose carrier reaches 3 kHz puts sidebands over Nyquist: the
  centroid of a "zap" read 10 to 12 kHz and it sounded like hiss. Keep the carrier under 2.5 kHz at an index under 2,
  and roll off the mix at 7 to 8 kHz.

## Is a sound heard under fire? {#is-a-sound-heard-under-fire}

Measured, not listened to (Deadnight #683, its `tools/audio/reload_audibility.py`):

- **Render the masker and the sound apart.** With no bus effects (a limiter or a compressor would break it) the mix is
  the sum of its parts, so two Movie Maker runs of one timeline, one with only the gunfire and one with only the
  reload, measure each part in the mix the player hears. Give each part its own random numbers (its own sound node and
  seed), or the second part shifts the first one's variants.
- **Find the sound in its own track, not at its call.** Under Movie Maker a sound starts 40 to 60 ms after the frame
  that played it, and its loudest moment may come later in the file (a lever's second clack 0.2 s in): a window at the
  call missed both (the pouch read -39 dBFS and the lever -23, though their files peak at -5 and -4). Bound the search
  by the next sound's call, and count the steps from the data, not from memory.
- **Compare by octave band over 80 ms** around the sound's loudest moment: heard when, in some band, it is louder than
  the fire there. At a tommy gun's 0.075 s every such window holds a whole shot, so this is strict; the best 20 ms
  frame (the gaps between shots, where hearing picks a click out) is generous and only worth reporting.
- **The player's own small sounds play flat**, as their own shots do: Deadnight's reload steps at the player's head,
  as 3D voices, were 6 dB down and partly lost; flat, 23 of 24 steps of five guns stood out under a teammate's tommy
  gun 3 m away (the revolver's empties, falling under a shot, did not). Lifting them 2 dB more made them as loud as
  the player's own shots: a teammate's steps take the lift instead (+6 dB, 23 of 24 heard through another's fire).

## Warnings that must carry through cover {#warnings-that-must-carry-through-cover}

The service dulls every sound with a wall in the way (9 dB down and a low-pass at 1.1 kHz; the web build, with no
filter, 13 dB down). A cue the player has to act on, such as a grenade's fuse beep, must not disappear behind a wall:
make it a low tone with some harmonics (a 2.6 kHz beep measured at -40 to -80 dBFS behind a wall) and give its
`SoundDef` an `occlusion_scale` under 1, so cover takes only that share of the dulling. Prove it from a recording of the
real service from behind a wall, reading the tone's level in the mix.

- **Approach:** Record a sound the player must act on (a fuse, a siren, a revive call) through the real service from
  behind a wall and from across the lot, and read its level in the mix; build it to survive the mix (a low tone with
  harmonics, an `occlusion_scale` under 1). **Watch out for:** every sound behind a wall is 9 dB down and low-passed at
  1.1 kHz, so a 2.6 kHz beep was gone (-40 to -80 dBFS) while a test that asserts "the sound was played at the grenade"
  passed whatever the mix did to it. **Seen:** Deadnight #680, 2026-11-03 (fix: 1.1 kHz with two harmonics and
  `occlusion_scale` 0.35; a test asserts the beep keeps more level and cutoff than a shot behind the same wall).

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

A capped start returns no player: Deadnight's `Audio.play` answers null both for a dropped sound (too far, over its
voice limit) and for one put off to the next frame by the starts-per-frame cap, which then plays. Code that schedules
from the returned player (a gust that times the next one by its length) takes null as "length unknown", never as "not
played" (Deadnight #782).

## Swelling a bed with an event

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

## A crowd's voices (the dead)

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

## Sound through windows, not walls (Deadnight #657)

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

## Web: samples or streams

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

### What to build instead (Deadnight #423)

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

## Menu sounds

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

## Music that holds a long stay

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

## A queue of lines said one after another

A helper that says "after the line that speaks" (`wait = director.wait()` at the call) is right for one caller and
wrong for two in the same instant: both read the wait of a free channel, both start together, and the second is refused
by the busy channel. Several lines due together (two players levelling up in one tick, Deadnight #1063) go through one
queue: say the front one, schedule the next after the channel's wait when it started, retry after that wait (at least
0.05 s, so a big test step cannot spin) when the channel held it back, drop it when the channel is free and it was
still refused (its cooldown, a downed speaker). Lines that arrive within a short window for the same player are
collapsed to the best one first, so a level, its tier and its item are one cheer. Test two speakers at once with
small steps, not one big step.
