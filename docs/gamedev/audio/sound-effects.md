# Sound effects

<!-- new section: voice-lines.md covers speech and, in its zombie section, one use of sound effects; nothing
     said how to ask for, cut, level and check a short effect or a loop -->

How to make short effects and ambient beds with ElevenLabs Sound Effects (`POST /v1/sound-generation`): the request,
what it costs, how a long take is cut into single sounds or made into a loop, how the files are levelled and checked,
and what the licence allows. The worked example is the first set of the templates (kit
[#835](https://github.com/Ryubara/gdstudio/issues/835)): a coin pickup, ten footsteps and a wind loop. The recipe is
[`tools/audio/sfx.py`][recipe] and everything about the sounds is in [`template_sounds.json`][data]; the files are in
the templates' `assets/audio/` folders, each with a `LICENSE.md`.

| Sound | Where | Request | Result |
| --- | --- | --- | --- |
| Coin pickup | `3d-third-person` `assets/audio/coin/` | 4 takes of 0.5 s | 4 files of 0.35 to 0.36 s, a shake of coins into a soft pop |
| Footsteps | `3d-third-person` `assets/audio/footsteps/` | 2 takes of 5 s | 10 single steps of 0.13 to 0.19 s, kept from 16 cut |
| Wind | `3d-blank` `assets/audio/wind/` | 1 take of 12 s, `loop` | one seamless loop of 10.5 s |

The wind is in the base because the base owns the `Ambient` bus (and has the sky it blows under); the coin and the
steps belong to the character, so they are in the third-person template.

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
| Footsteps (10) | loudest momentary | -29 LUFS-M | -29.3 to -29.0, peak -3.9 to -2.2 dBFS |
| Wind (1) | integrated | -33 LUFS | -33.0, peak -16.1 dBFS |

The coin is the most present effect and the steps, which play all the time, the quietest: 9 LU apart on the same bus,
with the wind a bed under both. Within a set the files match to 0.3 LU (`check` fails over 1 LU). Every file starts
within 5 ms of its first sample and none peaks over -1 dBFS decoded.

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

## 7. Proof {#proof}

- `check` output (length, lead-in, peak, loudness per file, the loop's seam and spread) in the pull request.
- A [listening clip](../../studio/capture.md#sound-a-clip-you-can-listen-to): an mp4 with the sounds as its track, one
  card a section, the sounds in order and then together, nothing normalised.
- The credits before and after, the plan, and the sum of the requests against the budget.

[recipe]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/sfx.py
[data]: https://github.com/Ryubara/gdstudio/blob/main/tools/audio/template_sounds.json
