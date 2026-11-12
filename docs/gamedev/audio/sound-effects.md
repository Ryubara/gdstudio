# Sound effects

<!-- new section: voice-lines.md covers speech and, in its zombie section, one use of sound effects; nothing
     said how to ask for, cut, level and check a short effect or a loop -->

How to make short effects and ambient beds with ElevenLabs Sound Effects (`POST /v1/sound-generation`): the request,
what it costs, how a long take is cut into single sounds or made into a loop, how the files are levelled and checked,
and what the licence allows. The worked example is the first set of the templates (kit
[#835](https://github.com/Ryubara/gdstudio/issues/835)): a coin pickup, footsteps and a wind loop; the steps were
redone in [#857](https://github.com/Ryubara/gdstudio/issues/857) and the pistol shot added to it. Kit
[#1083](https://github.com/Ryubara/gdstudio/issues/1083) regenerated the set on the paid starter plan with
`eleven_text_to_sound_v3` and replaced the synthesised fists, impacts and pistol mechanics too. The recipe is
[`tools/audio/sfx.py`][recipe] and everything about the sounds is in [`template_sounds.json`][data]; the files are in
the templates' `assets/audio/` folders, each with a `LICENSE.md`.

| Sound | Where | Request (#1083) | Result |
| --- | --- | --- | --- |
| Coin pickup | `3d-third-person` `assets/audio/coin/` | 6 takes of 0.5 s | 4 files of 0.31 to 0.32 s, one coin's chime and sparkle, starting at once |
| Weapon pickup | `3d-third-person` `assets/audio/weapon_pickup/` | 4 takes of 1.0 s, `eleven_text_to_sound_v3`, paid plan | 2 files of 0.64 and 0.56 s kept from takes 4 and 1, a grab and a bolt pulled back and let go; billed 10 credits each (#889) |
| Footsteps | `3d-third-person` `assets/audio/footsteps/` | 3 takes of 5 s | 4 single steps of 0.10 to 0.24 s, soft sneakers on stone, from 9 to 17 steps a take |
| Fists | `3d-third-person` `assets/audio/fists/` | 4 takes of 0.5 s | 3 punch whooshes of 0.15 to 0.17 s, high-passed at 120 Hz |
| Impacts | `3d-third-person` `assets/audio/impacts/` | 6, 8 and 8 takes of 0.5 s | 3 files each for stone, wood and metal, 0.15 to 0.31 s |
| Pistol mechanics | `3d-third-person` `assets/audio/pistol/` | 2 to 4 takes of 0.5 s each | 2 empty clicks, magazine out and in, the slide, the draw (0.06 to 0.30 s) |
| Pistol shot | `3d-third-person` `assets/audio/pistol/` | none: Deadnight's House Pistol, synthesised | 5 shots of 0.10 s, MIT, kept (picked by ear in #857) |
| Menu sounds | `3d-third-person` `assets/audio/ui/` | 5 + 3 hint, 5 press, 4 confirm, 4 move, 4 toggle and 4 swish takes, of 0.5 to 1 s (#1100) | 14 files: 3 hints of 0.05 s (a low wooden tock), 3 presses of 0.07 to 0.14 s, 2 confirms of 0.42 s (a click into a two-note marimba chime), 2 tab moves of 0.13 s, 2 switch snaps of 0.06 to 0.07 s, 2 swishes of 0.36 to 0.39 s |
| Wind | `3d-blank` `assets/audio/wind/` | 2 takes of 30 s, `loop` (and 3 of a second prompt) | one seamless loop of 28 s: gusts every 7 s or so, with a soft whistle layered in them ([A wind that reads as wind](#wind)) |

The wind is in the base because the base owns the `Ambient` bus (and has the sky it blows under); the coin and the
steps belong to the character, so they are in the third-person template. Each is played by a scene of its own (kit
[#836](https://github.com/Ryubara/gdstudio/issues/836)): the wind by `main.tscn` in both templates, the coin by
`pickup.tscn` and the steps by `footsteps.tscn`, timed to the feet of the walk, run, sprint and crouch-walk clips
([Audio](../../engines/godot/audio.md#template-buses)).

## 1. The request {#the-request}

```text
POST https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128
{"text": <prompt>, "duration_seconds": 0.5, "prompt_influence": 0.6, "model_id": "eleven_text_to_sound_v3", "loop": true}
```

- **Model.** `GET /v1/models` lists the speech models only, so a sound-effects model is named from the API
  reference and the changelog: `eleven_text_to_sound_v3` (SFX v3, every workspace since 2026-11-02, the default in the
  app; it takes `loop`, follows prompts of several instructions more closely and clips less on bright sounds) and
  `eleven_text_to_sound_v2`, deprecated and removed on 2027-03-01 ([API reference][api], [changelog][changelog]). The
  data file names the model for the set (`model`) and a sound may name its own; the request file of every take records
  the one it was made with. The templates' set is all v3 since #1083.
- **Output.** `mp3_44100_128` works on every plan; WAV and PCM at 44.1 kHz need the Pro plan, MP3 at 192 kbps the
  Creator plan. The recipe decodes the mp3 and encodes Ogg itself.
- **Generated, not the library.** ElevenLabs' premade sound-effects library has no API to search or download from
  (the API reference and changelog list none, 2026-11-11), so every sound here is generated; a library sound would be a
  download by hand with its own terms to read.
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
  `billed`. **Seen:** gdstudio #835, 2026-11-08 (planned 960, charged 240); #1083, 2026-11-11 (paid starter plan, v3:
  the same 10 a second, 735 for 51 takes of 73.5 s).

## 2. Prompts and what came back {#prompts}

One sound a prompt, the room left out ("dry, close, no echo, no voice, no music"), `prompt_influence` 0.5 to 0.6.

| Prompt (shortened) | What it gave |
| --- | --- |
| a quick shake of a few coins in a hand, then a single subtle soft bubblegum pop | 0.48 s of coin clinks all through; no clear pop in the envelope, so the file is cut where the sound falls 34 dB under its peak (0.35 to 0.36 s) |
| one person walking at a steady pace in hard leather shoes on a hard concrete floor, each step clear and separate | 9 and 11 steps in 5 s, 0.4 to 0.6 s apart, each a heel strike then a toe 80 to 130 ms later |
| soft steady outdoor wind in an open field, no gusts, no howling, constant level | **gusts anyway**: the level moved from -21 to -38 dB across the 12 s |
| (#857) eight quiet footfalls on a padded floor, one every 0.6 seconds, each a short low soft thud with a gentle round body and almost no click | two takes of 5 s held 2 hits each (4 steps in all) of 0.09 to 0.13 s; the model ignored the count and the spacing in every prompt (2 to 5 hits in 5 s; the "fingertip on a table" prompt gave 3 in one take and 11 in the next) |
| (#857) a slow even series of gentle muffled thumps, one every half second, like a soft mallet on a thick rug | 5 hits in each take, with their energy at 20 to 35 Hz, below what a phone or a laptop plays |

- **Approach:** Ask for the loop in the prompt and with `loop: true`, and keep a wind's swells: they are what make it
  wind ([A wind that reads as wind](#wind)). Flatten (`flatten_seconds`) only a bed that must be even, such as a room
  tone or a machine hum. **Watch out for:** #835 and #1083 asked for a constant wind and then divided the take by its
  own level over 0.25 s; the level moved 0.7 dB in the end, and in #1101's review the maintainer heard white noise in
  the background, not wind. `check` now fails a loop whose level moves less than its `min_spread_lu`. **Seen:**
  gdstudio #835, 2026-11-08; #1101, 2026-11-11 (the gusty retake moves 9.3 dB).
- **Approach:** Write the prompt as what the sound is (gusts that swell and die away, a soft whistle through the
  edges, a deep body of moving air), not what it is not, ask for two or more takes, and pick by measuring them.
  **Watch out for:** a negative does not steer the model and can name the very thing, so "no gusts, no howling" gave a
  take with gusts in it; for the same reason #1101 left "no hiss" out of its prompts. **Seen:** gdstudio #835,
  2026-11-08; #1101, 2026-11-11.

- **Approach:** Describe a step by its weight and floor, not the shoe (a short, low, soft thud on a padded floor), ask
  for more steps than you need, and measure what came back before cutting: the spectrum (centroid, shares under 250 Hz
  and over 2 kHz) as well as length and loudness. High-pass at 110 Hz so the body left is one a phone plays, and report
  a short set instead of padding it. **Watch out for:** #835's hard leather shoes gave heels that read as boots, and its
  wind had its energy at 20 to 60 Hz (centroid 28 Hz), a rumble that reads as breath on a microphone; a take asked for
  eight steps held 2 to 5, so two takes gave the four steps of A3 that ship. **Seen:** gdstudio #857, 2026-11-09
  (the maintainer picked A3 steps, none of five winds, the Deadnight shots from a listening clip).

- **Approach:** With v3, ask for a count and a spacing of steps in the prompt; it keeps them. **Watch out for:** the
  same kind of prompt on v2 gave 2 to 5 hits in 5 s; on v3 the three takes held 9, 11 and 17 even steps, so one take is
  enough for a set and the rest are spare. **Seen:** gdstudio #1083, 2026-11-11.
- **Approach:** Ask for four or more takes of a short hit, measure each take's peak and onset before picking, and
  re-prompt a weak sound as one loud, instant event (a single bullet slamming into a thick wooden plank: an instant,
  sharp, dry crack). **Watch out for:** half the first impact takes came back near silent (stone peaks at -40 and
  -16 dBFS, metal at -32, -20 and -20) or as a slow 0.3 s crunch with its peak 50 to 110 ms in; the recipe would level a
  near-silent take up into noise. Pick with `use_takes`, and give a changed prompt only to new takes (`take_prompts`
  keeps the old one for the takes made with it, so the `LICENSE.md` names each file's real prompt). **Seen:** gdstudio
  #1083, 2026-11-11 (12 retakes, 60 credits; 3 good takes of each surface).
- **Approach:** Read a coin or a chime's spectrum and accept that it lives over 5 kHz; ask for a clear onset instead
  of warmth. **Watch out for:** "a clear, warm metallic chime" still gave 97 to 99% of the energy over 5 kHz (centroid
  11 to 13 kHz), as #835's coin; what improved was the start (the peak 9 to 37 ms in, against 40 to 180 ms). The
  distance filter of a 3D player takes more off a bright sound, so the coin is levelled by its reading in the game.
  **Seen:** gdstudio #1083, 2026-11-11.

- **Approach:** For a menu's quietest sound, ask for a low wooden tock (a single gentle tap on a small wooden block,
  rounded and warm) and measure the spectrum of every take before picking. **Watch out for:** "a gentle muted tap of a
  fingertip on a small plastic key" gave three of five takes with 89 to 99% of their energy over 4 kHz (a hint should be
  mostly under it, `ui-sounds.md#2-weight-a-sound-matches-its-component`); the tock gave three of three at a centroid of
  394 to 534 Hz, 76 to 103 ms, cut to 0.05 s. A sharp click (the press) levelled to -26 LUFS-M was peak limited:
  level clicks to -30. **Seen:** gdstudio #1100, 2026-11-11 (31 takes, 177 credits billed of 708 planned).

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
  date, the prompt of each take) with the licence of that plan, then the folder's `folder_notes` (the pistol's
  synthesised shots share its folder). `check` measures the committed files and exits 1 on a failure.
- **The data file's keys for picking:** `takes` is how many are asked for and `use_takes` (numbers from 1) which are
  cut, after listening and measuring; `take_prompts` holds an earlier prompt for the takes made with it; `names` gives
  fixed file names (`pistol_draw.ogg`) instead of `<prefix>_<n>.ogg`; `highpass_hz` works on a hit as on steps;
  `model` on a sound overrides the set's. A loop takes `flatten_seconds` (even it out; never for a wind),
  `min_spread_lu` and `max_spread_lu` (the range its momentary level may move, checked) and `whistle` (`hz`, `q`,
  `mix`, `seed`: a whistle layered over its gusts, [A wind that reads as wind](#wind)). `licence_free` and
  `licence_paid` are the two licence texts, chosen by the plan the take was made on.

- **Approach:** After adding a sound to the data file, run `uv run --project python pytest
  python/tests/test_sfx_recipe.py` and move the set's pinned plan (the whole set asked again from an empty cache) and,
  when it passes, the `budget`, in the same commit. **Watch out for:** a new cache holds only the new takes, so `plan`
  and `generate` passed while the whole set's plan went from 3900 to 4608 credits, over the 4000 budget, and the
  recipe's test failed after the commit. **Seen:** gdstudio #1100, 2026-11-11 (the budget is 5000 now).

**Where it lives.** It is a script in the kit's `tools/audio/`, laid out as Deadnight's voice recipe is (a script and
a data file that holds every prompt, length and target), not a `gds` subcommand: it needs numpy for the cutting and
the checks and the kit's Python depends on Pillow alone, so a subcommand would add a package to every agent's
environment for one recipe. `uv run --with numpy` fetches it for the run. The parts that need no package (cost, budget,
names) are tested in `python/tests/test_sfx_recipe.py`.

## 4. Trimming, cutting and looping {#trimming}

All of it is in the recipe, from the cached mp3, mono 44.1 kHz:

1. **A single hit** (the coin): cut the lead-in to 4 ms before the first sample within 34 dB of the peak, the tail
   where the sound falls `tail_db` (-34) under its peak, never over the sound's `max_seconds` less 30 ms, fade 2 ms in
   and 60 ms out. A cut is at least `min_seconds` plus 10 ms: a hit cut at exactly 0.300 s decoded at 0.297 s, under
   the check's 0.3 (#1083).
2. **Single steps from a longer take:** find where each step starts (the 5 ms envelope crosses a quarter of the take's
   loud level, with a 0.28 s gap so a heel and toe are one step), cut from 4 ms before it to 20 ms before the next, at
   most 0.45 s, drop pieces far quieter than the take's median (a scuff), then keep the number the data file asks
   for, spread over both takes so the set is not all the first one.
3. **A loop:** high-pass at 40 Hz, take the swells out only when the sound asks for it (`flatten_seconds`), then
   cross-fade the last `crossfade` seconds into the first with equal power and drop them, so the file's end runs on
   into its start (the wind: 30 s in, a 2 s cross-fade, 28 s out), and layer a whistle over it when it asks for one
   (`whistle`, worked round the loop so it wraps with it). The check reads the step from
   the last sample to the first against a typical step (0.8 times one) and the level of the last 400 ms against the
   first (0.5 dB).

## 5. Levels {#levels}

Generated takes vary wildly in level and lead-in, so every file is levelled and measured as
[the audio rule](index.md) asks:

| Set | Reading | Target | Measured |
| --- | --- | --- | --- |
| Coin pickup (4) | loudest momentary (400 ms, zero-padded) | -20 LUFS-M | -20.3 to -20.0, peak -3.8 to -2.1 dBFS |
| Weapon pickup (2, #889) | loudest momentary | -23.5 LUFS-M | -23.7 to -23.5, peak -3.5 to -1.8 dBFS (the first file is peak limited at -23.7, so the set's target sits under it) |
| Footsteps (4, #857) | loudest momentary | -33 LUFS-M | -33.0 to -32.9, peak -13.3 to -9.2 dBFS |
| Wind (1, #1101) | integrated | -33 LUFS | -33.1, peak -16.3 dBFS, its momentary level moving 9.3 LU |

The #1083 set is levelled to hold the mix the maintainer set by ear: each set's target is the one that makes it read in
the game as loud as the sound it replaced (`template_sounds.json` has them: coin -19, steps -31.8, wind -33, fists
-21.3, impacts -30.2, -33.7 and -26.7, empty click -42.1, reload -27.2 to -30.4, draw -32.7 LUFS). Played in a game
made from the template with the real input, the loudest 400 ms at the mix moved from the old files' (left) to the new
(right): step -40.9 to -41.2, crouch step -46.0 to -46.5, landing -36.3 to -35.3, coin -37.0 to -39.2 (peak limited),
punch -35.0 to -36.8 (peak limited), draw -29.8 to -29.9, impacts -47.3/-45.3/-41.8 to -43.8/-42.8/-41.1, wind -50.4
to -50.0; the click (-45.2) and the reload (-29 to -46) were hard to hear or uneven and now sit at -40 and -35, under
the shot at -29.

- **Approach:** Set a short sound's file target from its reading in the game, not from the file it replaces: measure
  both sets in a game made from the template (`gds template game`, a probe scene that presses the input and logs each
  event, Movie Maker at 60 fps), then move each target by the difference. **Watch out for:** a 20 ms synthesised click
  and a 60 ms generated one both read -34 LUFS-M as files and 13.6 LU apart in the game (-45.2 and -31.6), and the
  bright magazine release lost 8 LU more than the file said: the first encode made the empty click as loud as a shot.
  **Seen:** gdstudio #1083, 2026-11-11.

The files are levelled to each other, not to what the game plays: a 3D player's `volume_db` then sets the rest. The
steps (-33) sit 4 LU under the old hard ones (-29) because the soft thuds keep all their energy under 300 Hz, which the
player's distance filter leaves alone, while the filter took the 2 to 5 kHz out of the hard steps. In the game, at the
maintainer's player volumes (steps -20, crouch steps -29, landing -15 and wind -20 dB) and the coin at -16 and the shot
at -22 dB, the loudest 400 ms at the mix, through the camera and the buses, is, played with the real input: step -40,
crouch step -46, landing -37, coin -37, shot -31 LUFS-M and the wind -50 LUFS integrated ([Audio](../../engines/godot/audio.md#template-buses)
has how it was measured). The weapon pickup at -20 dB reads -35 LUFS-M in the rifle tour's mix (between the coin
and the shot, its draw sound right after it at -29) and the rifle's automatic burst at -27 dB -25 (#889). Within a
set the files match to 0.3 LU (`check` fails over 1 LU). Every file starts within 5 ms
of its first sample and none peaks over -1 dBFS decoded, apart from the pistol's: the five Deadnight shots are
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

<!-- the paid-plan route is its own subsection below: the studio moved from the free tier to a paid plan (kit #889) -->

The plan is read from the subscription (`tier`), never from the account page. On the **free tier** a sound needs
attribution and is not licensed for commercial use; on a paid plan it is, and no attribution is asked. ElevenLabs'
Sound Effects terms ([Exhibit 4, section 2][terms]) let the output be used, changed and distributed in films, games and
apps **combined with other material**, and forbid selling, licensing or distributing it on its own, as isolated audio
files or samples, or in a sound, sample or effects library. A template in a public repository ships the files as
files, so whether that counts as combined with the game or as isolated files is a licence question for the maintainer
(AGENTS.md): kit #1083 was opened on hold for it, and the same question stands for the free-tier files it replaces.
The paid `LICENSE.md` says what the terms allow in those words. The templates' set was made on the free
tier with the maintainer's yes (kit #835, 2026-11-08), marked temporary: each folder's `LICENSE.md` lists every file with
its prompt and length, the generator, model, plan and the attribution, and says **Replace or relicense before any
commercial release**; a game made from the template said the same on its assets page and design page, and its
Credits screen named ElevenLabs. #1083 regenerated the set under the paid starter plan (a new cache, the same
commands): `encode` writes the paid licence from the plan in the request files, so a game made from the template now
carries no replace note.

The pistol shots in `assets/audio/pistol/` are not ElevenLabs output: they are Deadnight's House Pistol shots,
synthesised by its own code (`tools/audio/gun_recipes_2.py`, nothing sampled) and covered by the same MIT licence as
the kit, so their `LICENSE.md` names no generator and asks for no attribution and no replacement
([#857](https://github.com/Ryubara/gdstudio/issues/857)). Check how a sound's source documents its origin before
copying it across repositories; only the folders its design page lists as synthesised (here `guns/`) are plain MIT.

### On the paid plan {#paid-plan}

<!-- new section: the studio's ElevenLabs account moved to a paid plan (Starter) in kit #889; nothing said which source
     to use then, which model, or what the licence entry says -->

The studio's account is on ElevenLabs' Starter plan (kit #889): everything generated on it may be used commercially,
and so may the sounds of ElevenLabs' own premade library of sound effects. That changes the route, not the recipe:

- **Generate, or take a premade sound: your judgement.** Generate when the sound is ours to describe and should be
  reproducible (the recipe keeps the prompt, length, model and takes in `template_sounds.json`, and anyone can make it
  again); take a premade library sound when one already fits better than takes would, and record its name and where it
  came from. The library is browsed and downloaded on the ElevenLabs site; the public API documents generation
  (`POST /v1/sound-generation`) and no library endpoint, so the recipe generates. Either way, listen-test it against
  the template's other sounds of its kind before keeping it ([Proof](#proof)).
- **The newest API model for each kind of sound**: the sound's own `model` in the data file (`eleven_text_to_sound_v3`
  for a short effect, the API's newest; v2 where v3 lacks a parameter the sound needs, such as `loop`), the newest
  text-to-speech model for voice ([Voice lines](voice-lines.md)). Read the API reference's model list when you start,
  not this page.
- **More takes, then keep the best.** Starter's credits (about 30,000 a month, billed 10 a second of requested
  length, the same as the free tier) make four takes of a short sound cheap; list the ones you keep in the sound's
  `keep` (numbers from 1) and `encode` makes files of those only.
- **The licence entry** is the folder's `LICENSE.md`, written by `encode` from the plan the take's request file
  recorded (`tier`, read from `GET /v1/user/subscription` at generation): on any plan other than `free` it says the
  output is licensed for commercial use, needs no attribution and has nothing to replace (the data file's `licences`).
  A premade library sound gets the same file by hand: its name in the library, the plan it was downloaded on, the date
  and the same licence line. Neither needs the maintainer's yes; a sound from anywhere else still does (a third-party
  asset is a maintainer decision).
- **Replace a free-tier sound** by generating it again on the paid plan with a fresh cache folder (the old cache's
  request files say `free`), then `encode`, `check` and a listening clip Before and After.

- **Approach:** Generate several takes on the newest model and pick by measurement and a look at each take's envelope
  and spectrum: the transients the prompt asks for (a grab, then a bolt back and forward), the band shares against the
  set it joins, the length after the cut. **Watch out for:** v3's takes of the weapon pickup came back with 0.15 to 0.44
  s of silence before the sound (the cut takes it off) and with their energy low (43 to 51% under 250 Hz, like the
  rifle's draw and shot), where the free tier's v2 takes were bright (44% at 2 to 5 kHz); one of four was clicks alone,
  too quiet for a pickup. Take 4 was peak limited at -23.7 LUFS-M, 1.7 LU under the set's old -22 target, so the set's
  target moved to -23.5 (`check` allows 1 LU inside a set) and the level in the game was measured again. **Seen:**
  gdstudio #889, 2026-11-10 (takes 4 and 1 kept).

## 7. Proof {#proof}

- `check` output (length, lead-in, peak, loudness per file, the loop's seam and spread) in the pull request.
- A [listening clip](../../studio/capture.md#sound-a-clip-you-can-listen-to): an mp4 with the sounds as its track, one
  card a section, the sounds in order and then together, nothing normalised.
- The credits before and after, the plan, and the sum of the requests against the budget.

- **Approach:** For a Before of sounds being replaced, copy the files from a checkout of `main` (the workspace's
  `repos/gdstudio`) or `git checkout <rev> -- <file>`, and play both sets in two games made from the two checkouts with
  one probe scene, so each event lands at the same second in both tracks. **Watch out for:** the audio is in Git LFS:
  `git show HEAD:<file>.ogg` writes the 130-byte pointer, which ffmpeg refuses with an exit code and no message worth
  reading. **Seen:** gdstudio #1083, 2026-11-11 (66 events, the same times to the millisecond in both passes).

## 8. A wind that reads as wind {#wind}

<!-- new section: the levelling section says how loud a bed is, and nothing said what makes a wind bed read as wind and
     not as noise (gdstudio #1101's review) -->

A wind is moving air, heard through what it moves and what it blows past. What makes it read as wind, from the sources
and from measuring the winds the template shipped or was offered (kit #1101):

- **Gusts several seconds long.** The speed of the air rises and falls slowly; Farnell's wind model drives everything
  from one speed signal at about 0.1 Hz with gusts and squalls on top ([Farnell, practical 18][farnell]). The template's
  wind rises 9 dB from a lull to a gust about every 7 s; the even hush it replaced moved 0.7 dB.
- **The colour moves with the speed.** In a gust the band widens upward (more air in the leaves and edges) and in a
  lull it narrows to a low body: band-passed noise whose centre and width wander, never one fixed filter. The hush held
  a fixed spectrum with 29% of its energy over 4 kHz (a hiss) and a spectral flatness of 0.39; the winds offered hold
  3% or less over 4 kHz and a flatness of 0.005 to 0.04.
- **A whistle in the wind's own pitch.** Air past an edge or a wire sheds vortices at f = St v / d (St about 0.2), so
  the tone rises with the speed ([Aeolian sound][aeolian], [Selfridge et al.][harp]); Farnell's howl is noise through a
  resonant band-pass (Q 60) swept from about 600 to 1000 Hz by the speed. The recipe's `whistle` does the same over a
  generated take: Q 45 noise from 0.7 to 1.6 times 560 Hz as the take's own level rises, faded in only in the gusts,
  with a fainter partner 2.37 times higher.
- **Layers.** A low body, a mid swirl and an occasional high whistle, each with its own level curve on the one speed,
  as Farnell's complete scene layers buildings, doorways, wires and leaves; one file alone tends to sound flat
  ([sfxengine][weather]).
- **A long loop.** A pattern of gusts is heard repeating in a short loop, so a bed loops over 20 s or more; one long
  file is the simple way ([CRIWARE][criware], [Splice][soundscape]). The template's is 28 s; in the designed candidate
  every modulator has a whole number of cycles in 40 s, so it wraps with no cross-fade at all.

| #1101 | Flatness (1 s) | Under 250 Hz | Over 4 kHz | Level moves (p5 to p95) | Gusts a minute | Whistle (p90) | Loop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| The first wind (#835, a rumble) | 0.018 | 92% | 2% | 2.9 dB | 0 | 7.4 dB | 10.5 s |
| The hush (#1083 until its review) | 0.394 | 12% | 29% | 0.7 dB | 0 | 5.3 dB | 10.5 s |
| A: ElevenLabs, gusts over a hillside | 0.023 | 57% | 2% | 14.9 dB | 6.4 | 4.9 dB | 28 s |
| **B: ElevenLabs round a building, whistle layered (ships)** | 0.042 | 56% | 3% | 9.3 dB | 8.6 | 8.9 dB | 28 s |
| C: designed in code (body, swirl, whistle) | 0.005 | 54% | 1% | 14.9 dB | 7.5 | 9.0 dB | 40 s |

Flatness is the Wiener entropy of 1 s average spectra from 60 Hz to 16 kHz (1 for white noise); a gust is a peak of
the 1 s level that rose 3 dB or more from the lowest point of the 5 s before it; the whistle is the strongest narrow
peak of 300 Hz to 4 kHz over the 30 bins around it in 1 s averages (noise alone reads 4 to 5 dB). All play at -50
LUFS integrated in the game, as the hush did; the measuring script is kept with #1101's listening clip.

- **Approach:** Ask for gusts and a whistle in the prompt (round the corners of a stone building and through long
  grass, swirling gusts that swell and die away, now and then a faint high whistle through the edges), keep the swells,
  measure the takes (flatness, level movement, gusts, the band shares) and layer the whistle the model leaves out.
  **Watch out for:** v3 gave gusts but no measurable whistle in any of five takes (4.2 to 5.2 dB, the reading of
  noise); one take of the hillside prompt was a single 12 s swell in 30 s, which reads more as a change of weather.
  **Seen:** gdstudio #1101, 2026-11-11 (B ships; why it beat C is in the pull request).

Sources: [Farnell, Designing Sound, practical 18 (wind)][farnell]; [Aeolian sound][aeolian]; [Selfridge, Moffat,
Reiss and Avital, a real-time physical model of an Aeolian harp][harp]; [sfxengine, the sound of weather][weather];
[CRIWARE, ambience design][criware]; [Splice, a soundscape for video games][soundscape].

[farnell]: https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/practical18.html
[aeolian]: https://en.wikipedia.org/wiki/Aeolian_sound
[harp]: https://www.ioa.org.uk/system/files/publications/R%20SELFRIDGE%20DJ%20MOFFAT%20JD%20REISS%20EJ%20AVITAL%20REAL-TIME%20PHYSICAL%20MODEL%20OF%20AN%20AEOLIAN%20HARP.pdf
[weather]: https://sfxengine.com/blog/sound-of-weather
[criware]: https://blog.criware.com/index.php/2020/12/14/ambience-design-in-atom-craft-part-1-2/
[soundscape]: https://splice.com/blog/audio-soundscape-for-video-games

## 9. A fire sound that stays pleasant {#fire}

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

[api]: https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
[changelog]: https://elevenlabs.io/docs/changelog
[terms]: https://elevenlabs.io/sound-effects-terms
[recipe]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/sfx.py
[data]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/template_sounds.json
