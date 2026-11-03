# Audio

Draft for `docs/godot/audio.md` in the kit (from Deadnight's sound design, issue 43). Game specifics are in Deadnight's
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

## Capturing sound

- `--write-movie <absolute folder>/name.png --fixed-fps 10` also writes `name.wav`: 32-bit integer PCM, stereo, 48 kHz.
  The folder must exist. Mux with ffmpeg; analyse by reading `<i4`.
- The headless GdUnit4 run uses the dummy audio driver: players report `playing`, nothing is heard.
- The listener is the current `Camera3D` unless an `AudioListener3D` is current; a high capture camera makes distances
  wrong.
- Movie Maker writes only the mix. For per-bus stems (voice against guns against beds), put an `AudioEffectRecord` on
  each bus to measure and save its recording at the end; it works under Movie Maker
  ([lesson](../lessons/2026-11-01-audio-effect-record-gives-per-bus-stems.md)).
- Transcribe generated voice takes with ElevenLabs Scribe to catch audio tags read aloud: performed sounds come back
  in brackets, spoken tags as words; Scribe bills the speech character quota
  ([lesson](../lessons/2026-11-01-speech-to-text-catches-audio-tags-read-aloud.md)). The whole voice pipeline, from
  casting to the game: [Voice lines](../audio/voice-lines.md).

- **Time a pattern of sounds at 60 fps, with no pictures.** A sound schedule follows the frames, so a recording at 10
  frames a second puts every start on a 0.1 s grid and stacks the quick ones in a frame. Use `--write-movie
  <abs>/x.avi --fixed-fps 60` and pull the track with `ffmpeg -i x.avi -vn -c:a pcm_s32le x.wav`; keep the PNG movie for
  pictures. To find a tone in a busy mix, correlate with a windowed carrier at its frequency (Deadnight's
  `tools/audio/beep_report.py`): a pure tone reads 0.58 and noise far less, and the tone's amplitude is its level in the
  mix whatever else sounds
  ([lesson](../lessons/2026-11-03-a-10-fps-recording-cannot-time-a-sound-that-follows-the-frames.md)).

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

## Close and powerful sounds

A gun "sounding distant" is measured on a recording of the real shot through the real buses, not read off the files
(Deadnight #455, [lesson](../lessons/2026-11-02-gun-shots-sounded-distant-by-the-numbers-nobody-took.md)):

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
  4 to 10 dB higher played alone than after the guns, and moved with the gun trims
  ([lesson](../lessons/2026-11-03-a-pooled-3d-player-kept-the-last-sounds-max-db.md)). Play each cell alone and after
  the others, and set every pooled property on every play.
- **A sound's variant files differ by 3 to 9 dB in peak** (a zombie voice's loudest and quietest take): to bound the
  worst case point the definition at one file for each play (`path_format = def.path_for(k)`, `variants = 1`) and put
  it back.
- **Measure on the merged tree, before and after from one base.** Merge `main` before measuring a mix and keep a second
  worktree on `origin/main` for the "before" runs
  ([lesson](../lessons/2026-11-03-a-baseline-was-measured-before-main-changed-the-sounds-under-it.md)). Capture in runs
  of a few minutes of sound and pull the track out of the avi before deleting it
  ([lesson](../lessons/2026-11-03-a-long-audio-capture-was-lost-to-a-deleted-avi-and-the-900-s-cap.md)).
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
  reaches the mix 0 to 3 dB higher than the old close peak, and the old cap does not carry over. Deadnight #762: crest of
  a file 15 to 23 dB before, 12.6 to 16.6 after; the loudest 400 ms at 1.2 m up 3.5 to 6.4 LU at the same -9.9 dBFS
  ([lesson](../lessons/2026-11-03-a-limited-crack-raised-the-close-peak-more-than-the-limiter-took-off.md)).

## Is a sound heard under fire?

Measured, not listened to (Deadnight #683, its `tools/audio/reload_audibility.py`):

- **Render the masker and the sound apart.** With no bus effects (a limiter or a compressor would break it) the mix is
  the sum of its parts, so two Movie Maker runs of one timeline, one with only the gunfire and one with only the
  reload, measure each part in the mix the player hears. Give each part its own random numbers (its own sound node and
  seed), or the second part shifts the first one's variants.
- **Find the sound in its own track, not at its call.** Under Movie Maker a sound starts 40 to 60 ms after the frame
  that played it, and its loudest moment may come later in the file (a lever's second clack 0.2 s in): a window at the
  call missed both ([lesson](../lessons/2026-11-02-a-step-measured-at-its-play-call-missed-its-sound.md)). Bound the
  search by the next sound's call.
- **Compare by octave band over 80 ms** around the sound's loudest moment: heard when, in some band, it is louder than
  the fire there. At a tommy gun's 0.075 s every such window holds a whole shot, so this is strict; the best 20 ms
  frame (the gaps between shots, where hearing picks a click out) is generous and only worth reporting.
- **The player's own small sounds play flat**, as their own shots do: Deadnight's reload steps at the player's head,
  as 3D voices, were 6 dB down and partly lost; flat, 23 of 24 steps of five guns stood out under a teammate's tommy
  gun 3 m away (the revolver's empties, falling under a shot, did not). Lifting them 2 dB more made them as loud as
  the player's own shots: a teammate's steps take the lift instead (+6 dB, 23 of 24 heard through another's fire).

## Warnings that must carry through cover

The service dulls every sound with a wall in the way (9 dB down and a low-pass at 1.1 kHz; the web build, with no
filter, 13 dB down). A cue the player has to act on, such as a grenade's fuse beep, must not disappear behind a wall:
make it a low tone with some harmonics (a 2.6 kHz beep measured at -40 to -80 dBFS behind a wall) and give its
`SoundDef` an `occlusion_scale` under 1, so cover takes only that share of the dulling. Prove it from a recording of the
real service from behind a wall, reading the tone's level in the mix
([lesson](../lessons/2026-11-03-a-fuse-beep-was-silent-behind-a-wall-because-the-mix-low-passes-it.md)).

## Starting sounds

Measured in Deadnight's web build (Chrome, RTX 5080, #402): starting an Ogg Vorbis `AudioStreamPlayer` costs about
0.8 ms (headers and codebooks are read again on every `play()`), a PCM one about 0.3 ms, and a 40 s Ogg bed 43 ms. A
frame that starts six sounds pays six times. Decode short sounds (up to 2.5 s) to `AudioStreamWAV` with
`AudioStreamPlayback.mix_audio` while loading, cap starts per frame and defer the rest, and start beds silent and
paused, then fade them in ([lesson](../lessons/2026-11-01-ogg-starts-cost-a-millisecond-in-the-browser.md)).

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
- **`unit_size` is a loudness, not a size.** Inverse attenuation is `unit_size / distance`, above 1 inside
  `unit_size`, held only by `max_db` (3 dB): see the lesson on the boss roar that clipped the mix.
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
  ends where the next one starts (see the lesson on the window).
- **A level capture needs a listener.** A Movie Maker recording with no `Camera3D` (or `AudioListener3D`) in the tree is
  silent: nothing hears the 3D players.

## Leaks at exit in a test run

- **A passing GdUnit4 run can still print `ObjectDB instances were leaked at exit` and `resources still in use at
  exit`.** Nothing fails, so nobody looks. The lines belong to whichever suite left something alive: a test lambda that
  held itself through an array (a cycle that keeps the test script in use), or a night whose ambience beds only fade
  out when it is freed. Run the test folders one at a time with `--verbose` to see which stream or script it is. Cut
  the cycle at the end of the test, stop the audio after each test that builds a night, wait `Audio.wait_for_mixer()`
  once, and have CI grep the test log for `leaked at exit|still in use`
  ([lesson](../lessons/2026-11-01-a-gdunit4-run-printed-leaks-at-exit-that-no-test-reported.md)).
- **The check can fail a passing run at random.** A process that quits at once (a test run: GdUnit exits itself)
  leaks whatever voice is playing or just stopped, because the audio server frees a playback only after its mixer
  has stepped a few times. A suite cannot wait after the last test, so wait in the audio autoload's `_exit_tree`:
  block the main thread, counting `AudioServer.get_time_since_last_mix()` falls (the mixer has its own thread). A
  child Godot that starts sounds and quits is a deterministic test for it. `--verbose` makes the engine list every
  leaked instance and resource, and CI keeps those lines as an artifact
  ([lesson](../lessons/2026-11-02-the-exit-leak-check-failed-a-passing-test-run-at-random.md)).

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
  whole way, not by that remainder, which is larger for a window farther away
  ([lesson](../lessons/2026-11-03-a-routed-yard-sound-used-the-wrong-fall-off.md)). No window: play it where it is,
  quieter and duller, as through a wall. Outside the building: where it is.
- **Fences and the ground are not walls.** The rays read the same layers as the walls; ask again past a hit under the
  outside group by adding its `rid` to `exclude`, and exclude the windows' own blockers
  ([lesson](../lessons/2026-11-03-a-yard-fence-counted-as-a-wall-for-sound.md)).
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
  `GainNode` feeding an `AudioWorklet` that counts zero blocks and sample jumps
  ([lesson](../lessons/2026-11-01-web-samples-ignore-bus-effects.md)).

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
  0 stream, 1 sample ([lesson](../lessons/2026-11-02-a-project-setting-written-with-its-section-prefix-was-ignored.md)).
