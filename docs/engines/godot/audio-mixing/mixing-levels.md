# Mixing levels

<!-- new section: audio.md passed the 50 KB limit (gdstudio #1067), so its sections on levels, headroom and being
     heard in a mix moved here; audio.md keeps a short section per anchor that links to each -->

How loud a sound is in the mix, as the player hears it: closeness, headroom without a limiter, a layer over a shot,
whether a sound is heard under fire and a warning through cover. The rest of audio is on [Audio](../audio.md).

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
  filter (see [Web: samples or streams](../audio.md#web-samples-or-streams)).
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

## Headroom without a limiter {#headroom-without-a-limiter}

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
  minutes of sound (see [Capturing sound](../audio.md#capturing-sound)).
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

## A layer over a sound that already peaks {#a-layer-over-a-sound-that-already-peaks}

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
