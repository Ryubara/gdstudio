# Sound effects

<!-- new section: voice-lines.md covers speech and, in its zombie section, one use of sound effects; nothing
     said how to ask for, cut, level and check a short effect or a loop -->

How to make short effects and ambient beds with ElevenLabs Sound Effects (`POST /v1/sound-generation`): the request,
what it costs, how a long take is cut into single sounds or made into a loop, how the files are levelled and checked,
and what the licence allows. The worked example is the first set of the templates (kit
[#835](https://github.com/Ryubara/gdstudio/issues/835)): a coin pickup, footsteps and a wind loop; the steps were
redone in [#857](https://github.com/Ryubara/gdstudio/issues/857) and the pistol shot added to it. The recipe is
[`tools/audio/sfx.py`][recipe] and everything about the sounds is in [`template_sounds.json`][data]; the files are in
the templates' `assets/audio/` folders, each with a `LICENSE.md`.

| Sound | Where | Request | Result |
| --- | --- | --- | --- |
| Coin pickup | `3d-third-person` `assets/audio/coin/` | 4 takes of 0.5 s | 4 files of 0.35 to 0.36 s, a shake of coins into a soft pop |
| Footsteps | `3d-third-person` `assets/audio/footsteps/` | 2 takes of 5 s | 4 single steps of 0.08 to 0.13 s, soft low thuds, kept from 4 cut (#857; #835's 10 boot steps are gone) |
| Pistol shot | `3d-third-person` `assets/audio/pistol/` | none: Deadnight's House Pistol, synthesised | 5 shots of 0.10 s, MIT, no ElevenLabs licence (#857) |
| Wind | `3d-blank` `assets/audio/wind/` | 1 take of 12 s, `loop` | one seamless loop of 10.5 s |

The wind is in the base because the base owns the `Ambient` bus (and has the sky it blows under); the coin and the
steps belong to the character, so they are in the third-person template. Each is played by a scene of its own (kit
[#836](https://github.com/Ryubara/gdstudio/issues/836)): the wind by `main.tscn` in both templates, the coin by
`pickup.tscn` and the steps by `footsteps.tscn`, timed to the feet of the walk, run, sprint and crouch-walk clips
([Audio](../../engines/godot/audio.md#template-buses)).

## 1. The request {#the-request}

```text
POST https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128
{"text": <prompt>, "duration_seconds": 0.5, "prompt_influence": 0.6, "model_id": "eleven_text_to_sound_v2", "loop": true}
```

- **Model.** `GET /v1/models` lists the speech models only, so a sound-effects model is named from the API
  documentation: `eleven_text_to_sound_v2` (the only one that takes `loop`) and `eleven_text_to_sound_v3`
  ([zombies](voice-lines.md#5-the-zombies-are-different) try v3 and fall back). The templates' set is all v2.
- **Length is always explicit**, 0.5 to 30 s. Never ask for automatic length: it costs more and you cannot plan it.
  A request shorter than the sound is what you want to cut from is fine: a coin shake is under half a second, and
  the shortest request is already 0.5 s.
- **No seed.** Variety comes from asking again; keep every raw take (`<sound>_t<n>.mp3`) and its request file in the
  scratch cache, and never request one twice. The recipe's request file also keeps the response headers.
- **The key** is `ELEVENLABS_API_KEY` in the environment; the recipe never prints or writes it.

### What a request costs {#what-a-request-costs}

- **Approach:** Plan every request at 40 credits a second of requested length (the quoted figure), stop the total at
  the budget in the data file, and record what the API says it billed (the response's `character-cost` header); read
  the balance once, a few seconds after the last request. **Watch out for:** on the free tier on 2026-11-08 the header
  said 5 credits for 0.5 s, 50 for 5 s and 120 for 12 s (10 a second) and the balance moved by exactly that, 240 for
  the set, a quarter of the plan; it read zero right after the coin takes and 20 a few seconds later. Planning at 40
  stays safe, but a budget counted from the plan would refuse retakes the account can afford, so the ledger counts
  `billed`. **Seen:** gdstudio #835, 2026-11-08 (planned 960, charged 240).

## 2. Prompts and what came back {#prompts}

One sound a prompt, the room left out ("dry, close, no echo, no voice, no music"), `prompt_influence` 0.5 to 0.6.

| Prompt (shortened) | What it gave |
| --- | --- |
| a quick shake of a few coins in a hand, then a single subtle soft bubblegum pop | 0.48 s of coin clinks all through; no clear pop in the envelope, so the file is cut where the sound falls 34 dB under its peak (0.35 to 0.36 s) |
| one person walking at a steady pace in hard leather shoes on a hard concrete floor, each step clear and separate | 9 and 11 steps in 5 s, 0.4 to 0.6 s apart, each a heel strike then a toe 80 to 130 ms later |
| soft steady outdoor wind in an open field, no gusts, no howling, constant level | **gusts anyway**: the level moved from -21 to -38 dB across the 12 s |
| (#857) eight quiet footfalls on a padded floor, one every 0.6 seconds, each a short low soft thud with a gentle round body and almost no click | two takes of 5 s held 2 hits each (4 steps in all) of 0.09 to 0.13 s; the model ignored the count and the spacing in every prompt (2 to 5 hits in 5 s; the "fingertip on a table" prompt gave 3 in one take and 11 in the next) |
| (#857) a slow even series of gentle muffled thumps, one every half second, like a soft mallet on a thick rug | 5 hits in each take, with their energy at 20 to 35 Hz, below what a phone or a laptop plays |

- **Approach:** Ask for the loop in the prompt and with `loop: true`, and expect to take the swells out afterwards.
  **Watch out for:** "no gusts, constant level" in the prompt did not keep the take level: half-second readings ran
  from -21 to -38 dB, a 17 dB swing that would call attention in a game. The recipe divides the take by its own level
  over 0.25 s (held to 14 dB either way), after which half-second readings stay within 2 dB. **Seen:** gdstudio #835,
  2026-11-08 (the first encode of the take measured 9.9 LU of spread; after flattening 2.8 LU; `check` fails a bed
  over 3 LU).
- **Approach:** Write the prompt as what the sound is (a soft, even hush of air over open grass, steady from start to
  end), not what it is not, ask for two or more takes, and keep the one whose measured spread is smallest. **Watch out
  for:** a negative does not steer the model and can name the very thing, so "no gusts, no howling" gave a take with
  gusts in it; only measuring the takes shows what came back. **Seen:** gdstudio #835, 2026-11-08 (one take was asked
  for, so the recipe had to flatten its swells).

- **Approach:** Describe a step by its weight and floor, not the shoe (a short, low, soft thud on a padded floor), ask
  for more steps than you need, and measure what came back before cutting: the spectrum (centroid, shares under 250 Hz
  and over 2 kHz) as well as length and loudness. High-pass at 110 Hz so the body left is one a phone plays, and report
  a short set instead of padding it. **Watch out for:** #835's hard leather shoes gave heels that read as boots, and its
  wind had its energy at 20 to 60 Hz (centroid 28 Hz), a rumble that reads as breath on a microphone; a take asked for
  eight steps held 2 to 5, so two takes gave the four steps of A3 that ship. **Seen:** gdstudio #857, 2026-11-09
  (the maintainer picked A3 steps, none of five winds, the Deadnight shots from a listening clip).

## 3. The recipe {#the-recipe}

```text
ELEVENLABS_API_KEY=... uv run --with numpy python tools/audio/sfx.py --cache <workspace>/scratch/<repo>/<branch>/sfx-cache \
    --ffmpeg <pinned ffmpeg> <credits|plan|generate|encode|check> [--only coin_pickup,...]
```

```text
credits ──> plan ──> generate ──> encode ──> check
```

- `credits` reads `GET /v1/user/subscription` and prints the plan and the credits left. **Read it before and after**,
  and put both in the pull request. The plan (`tier`) is what decides the licence (section 6).
- `plan` prints every take with its seconds and cost (cached takes cost 0) and the total against the budget; it
  sends nothing and refuses over the budget. `generate` runs it first, requests only takes not in the cache, and prints
  the balance before and after.
- `encode` cuts, levels and encodes (below) and writes each folder's `LICENSE.md` from the request files (model, plan,
  date) and the prompts. `check` measures the committed files and exits 1 on a failure.

**Where it lives.** It is a script in the kit's `tools/audio/`, laid out as Deadnight's voice recipe is (a script and
a data file that holds every prompt, length and target), not a `gds` subcommand: it needs numpy for the cutting and
the checks and the kit's Python depends on Pillow alone, so a subcommand would add a package to every agent's
environment for one recipe. `uv run --with numpy` fetches it for the run. The parts that need no package (cost, budget,
names) are tested in `python/tests/test_sfx_recipe.py`.

## 4. Trimming, cutting and looping {#trimming}

All of it is in the recipe, from the cached mp3, mono 44.1 kHz:

1. **A single hit** (the coin): cut the lead-in to 4 ms before the first sample within 34 dB of the peak, the tail
   where the sound falls `tail_db` (-34) under its peak, never over the sound's `max_seconds` less 30 ms, fade 2 ms in
   and 60 ms out.
2. **Single steps from a longer take:** find where each step starts (the 5 ms envelope crosses a quarter of the take's
   loud level, with a 0.28 s gap so a heel and toe are one step), cut from 4 ms before it to 20 ms before the next, at
   most 0.45 s, drop pieces far quieter than the take's median (a scuff), then keep the number the data file asks
   for, spread over both takes so the set is not all the first one.
3. **A loop:** high-pass at 40 Hz, take the swells out, then cross-fade the last 1.5 s into the first 1.5 s with equal
   power and drop them, so the file's end runs on into its start (12 s in, 10.5 s out). The check reads the step from
   the last sample to the first against a typical step (0.8 times one) and the level of the last 400 ms against the
   first (0.5 dB).

## 5. Levels {#levels}

Generated takes vary wildly in level and lead-in, so every file is levelled and measured as
[the audio rule](index.md) asks:

| Set | Reading | Target | Measured |
| --- | --- | --- | --- |
| Coin pickup (4) | loudest momentary (400 ms, zero-padded) | -20 LUFS-M | -20.3 to -20.0, peak -3.8 to -2.1 dBFS |
| Footsteps (4, #857) | loudest momentary | -33 LUFS-M | -33.0 to -32.9, peak -13.3 to -9.2 dBFS |
| Wind (1) | integrated | -33 LUFS | -33.0, peak -16.1 dBFS |

The files are levelled to each other, not to what the game plays: a 3D player's `volume_db` then sets the rest. The
steps (-33) sit 4 LU under the old hard ones (-29) because the soft thuds keep all their energy under 300 Hz, which the
player's distance filter leaves alone, while the filter took the 2 to 5 kHz out of the hard steps. In the game, at the
maintainer's player volumes (steps -20, crouch steps -29, landing -15 and wind -20 dB) and the coin at -16 and the shot
at -22 dB, the loudest 400 ms at the mix, through the camera and the buses, is, played with the real input: step -40,
crouch step -46, landing -37, coin -37, shot -31 LUFS-M and the wind -50 LUFS integrated ([Audio](../../engines/godot/audio.md#template-buses)
has how it was measured). Within a set the files match to 0.3 LU (`check` fails over 1 LU). Every file starts within
5 ms of its first sample and none peaks over -1 dBFS decoded, apart from the pistol's: the five Deadnight shots are
full-scale files (peak about 0 dBFS), made to be played at a trim, and play here at -22 dB.

- **Approach:** Read short sounds as the loudest momentary loudness (the file zero-padded to one second) and level to
  that, with `framelog=info` in ffmpeg's `ebur128` filter to get the per-frame `M:` lines. **Watch out for:** the
  default `ebur128` prints only the summary, whose integrated loudness gates a sound under 400 ms to -70 LUFS; parsing
  it gave "-120" for every file and a gain of +60 dB, "peak limited" on all of them. **Seen:** gdstudio #835,
  2026-11-08 (the first encode; `check` prints both readings per file).
- **Approach:** Encode to 0.5 dB under the ceiling you check (`-1.5` dBFS encoded, `-1` dBFS decoded) and cut a hit
  30 ms under its length limit. **Watch out for:** libvorbis overshoots a peak by up to 1 dB when decoded (a file
  encoded at -1.0 read -0.65) and pads the end by up to a frame, so a 0.37 s cut decoded at 0.393 s and Godot read 0.4
  s from a 0.397 s file, outside "0.3 to 0.4 s". **Seen:** gdstudio #835, 2026-11-08 (the first coin set failed the
  length and the peak check; `check` runs on the decoded Oggs).

## 6. Licence {#licence}

The plan is read from the subscription (`tier`), never from the account page. On the **free tier** a sound needs
attribution and is not licensed for commercial use; on a paid plan it is. The templates' set was made on the free
tier with the maintainer's yes (kit #835, 2026-11-08), marked temporary: each folder's `LICENSE.md` lists every file with
its prompt and length, the generator, model, plan and the attribution, and says **Replace or relicense before any
commercial release**; a game made from the template says the same on its assets page and design page, and its Credits
screen names ElevenLabs. Regenerating under a paid plan is the same command (delete the cache and the files) and
fixes the licence with no code change.

The pistol shots in `assets/audio/pistol/` are not ElevenLabs output: they are Deadnight's House Pistol shots,
synthesised by its own code (`tools/audio/gun_recipes_2.py`, nothing sampled) and covered by the same MIT licence as
the kit, so their `LICENSE.md` names no generator and asks for no attribution and no replacement
([#857](https://github.com/Ryubara/gdstudio/issues/857)). Check how a sound's source documents its origin before
copying it across repositories; only the folders its design page lists as synthesised (here `guns/`) are plain MIT.

## 7. Proof {#proof}

- `check` output (length, lead-in, peak, loudness per file, the loop's seam and spread) in the pull request.
- A [listening clip](../../studio/capture.md#sound-a-clip-you-can-listen-to): an mp4 with the sounds as its track, one
  card a section, the sounds in order and then together, nothing normalised.
- The credits before and after, the plan, and the sum of the requests against the budget.

## 8. A fire sound that stays pleasant {#fire}

<!-- new section: the template's pistol had an empty ShotSound and nothing said what a basic fire sound should do so it
     does not tire the ear (gdstudio #857) -->

What makes a basic fire sound read well when it is heard hundreds of times, from the sources and from measuring the
five shots the template ships (Deadnight's House Pistol shots, picked by the maintainer after listening to five
generated low thumps).

- **Approach:** Build a basic shot from a transient and a body only, and keep every layer short and tightly enveloped:
  a game weapon is a few short variants of a transient (the crack or click), a body (weight and character), an
  optional sub layer, a mechanical layer and a tail kept as a separate sound so the room can change
  ([Splice][splice], [Krotos][krotos]). The template's shot is the report alone, 0.10 s with no tail, so quick fire
  does not turn muddy. **Watch out for:** stacked transients are the muddiness and the peaking risk; the five shots
  peak at about 0 dBFS as files (made to be trimmed), so play them at a trim, not at 0 dB. **Seen:** gdstudio #857,
  2026-11-09.
- **Approach:** Know where the energy sits and decide on purpose. The ear is most sensitive between 2 and 5 kHz and
  much less at 50 to 100 Hz, where loudness falls by up to 24 dB an octave ([equal-loudness contours][eq]), so energy
  in 2 to 5 kHz reads louder and sharper than the same energy low; a thump puts its weight under about 300 Hz, and
  small speakers do not play under 80 Hz ([Ortega][ortega]), so add harmonics at 150 to 700 Hz to a deep one.
  **Watch out for:** the shipped shot is not a thump: 22 to 29% of its energy is under 250 Hz and 21 to 33% at 2 to
  5 kHz (centroid 1.9 to 2.5 kHz), at -31 LUFS-M, 10 LU over a step; the generated thumps held theirs at 20 to 100 Hz,
  below a laptop. Measure a shot's band shares before calling it pleasant or harsh. **Seen:** gdstudio #857.
- **Approach:** Vary every shot: at least 3 to 5 files, and a small random pitch and volume spread
  (about +-2 semitones and +-1.5 dB for a general sound, [sfxengine][sfx]). In Godot an `AudioStreamRandomizer` does
  it with no code: `random_pitch` is a multiplier (the pitch is chosen between 1/x and x) and `random_volume_offset_db`
  is +-x dB ([Godot docs][rand]). For a short report 4% (`random_pitch = 1.04`, about +-0.7 semitone) and +-1 dB keep
  it the same gun. **Watch out for:** identical repeats cause auditory repetition fatigue; the randomizer's default
  playback mode already avoids the same file twice in a row. **Seen:** gdstudio #857.
- **Approach:** Match a fire rate to the voices. An `AudioStreamPlayer3D` plays one sound at a time (`max_polyphony`
  1) and a further `play()` cuts the oldest voice ([Godot docs][p3d]); give the weapon about the sound's length over
  the fire interval, rounded up, plus one: three for a 0.10 s report at 4 shots a second. **Watch out for:** with one
  voice each shot cuts the tail of the one before, which clicks when the cut is not at silence; a longer tail or a
  faster rate needs more voices, and voices are a cost on the web. Dynamic balancing that lowers a sustained burst is
  used in some games ([a mod's description][dab]); a template needs only the variation. **Seen:** gdstudio #857
  (`ShotSound`: `max_polyphony = 3`).
- **Approach:** Level the shot against the other effects by measurement in the game: a few LU over the loudest
  ordinary effect and not 15. The shot is the loudest effect, at -31 LUFS-M against a coin and a landing at -37 and a
  step at -40. **Watch out for:** the sources give no number for the tail length or for how much a pleasant shot may
  overlap, and none measured ear fatigue; the lengths and levels here are measured on the files and are the
  maintainer's to hear. **Seen:** gdstudio #857.

Sources: [Splice, how to design a weapon sound][splice]; [Krotos, Weaponiser and Gun Sound Design][krotos]; [Lior
Ortega, FPS gun sound design][ortega]; [sfxengine, common game audio mistakes][sfx]; [equal-loudness
contour][eq]; Godot docs: [AudioStreamRandomizer][rand], [AudioStreamPlayer3D][p3d]; [Dynamic Audio Balancing
(H3VR mod)][dab].

[splice]: https://splice.com/blog/?p=16617
[krotos]: https://www.krotosaudio.com/?p=1057976
[ortega]: https://www.liortega.com/post/first-person-shooter-gun-sound-design
[sfx]: https://sfxengine.com/blog/common-game-audio-mistakes
[eq]: https://en.wikipedia.org/wiki/Equal-loudness_contour
[rand]: https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html
[p3d]: https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html
[dab]: https://thunderstore.io/c/h3vr/p/Sirdoggy/Dynamic_Audio_Balancing/

[recipe]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/sfx.py
[data]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/template_sounds.json
