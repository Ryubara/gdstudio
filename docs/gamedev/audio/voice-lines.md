# Voice lines

How to give a game's character a voice with ElevenLabs text to speech, so it sounds like a person in the moment and
not like a narrator. The worked example is Deadnight's soldier: 115 takes of 21 moments, cast, written, generated,
checked and wired into the night in one pull request ([Deadnight #442](https://github.com/Ryubara/deadnight/pull/442),
issue [#384](https://github.com/Ryubara/deadnight/issues/384)). The maintainer judged the result well generated.

The source of truth is Deadnight's files; this page explains them and does not copy them whole:

| File | What it holds |
| --- | --- |
| [`tools/audio/soldier_voice.json`][json] | voice, voice id, model, settings, target loudness, and every line by moment |
| [`tools/audio/elevenlabs_voice.py`][recipe] | the recipe: `plan`, `generate`, `encode`, `check`, `credits` |
| [`game/assets/audio/voice/soldier/manifest.json`][manifest] | per take: moment, text, characters, model, voice, settings, seed, seconds, loudness before levelling |
| [`game/assets/audio/voice/soldier/LICENSE.md`][licence] | the licence entry for the takes |
| [`game/core/audio/soldier_voice_catalog.gd`][catalog] | moments, takes, priority, cooldown and chance; bus and level |
| [`game/gameplay/night/soldier_voice.gd`][node], [`voice_director.gd`][director] | what triggers a moment; which take plays, and whether |
| [`game/tests/core/test_soldier_voice_catalog.gd`][catalog-test] | the data checks: approved settings, budget, no caption lines, lengths |
| [`tools/audio/voice_report.py`][report], [`voice_sheet.py`][sheet] | the voice's loudness in a night capture; the script as a contact sheet |
| [`docs/design/audio.md`][design], [`docs/research/audio.md`][research] | the design of the soldiers' voices; settings, characters and measurements |

## 1. Casting {#1-casting}

**Start from the brief, then list what the account offers now.** The maintainer's brief for Deadnight asked for a
tough male soldier: a deep, calm, steady voice with some expression that changes with the line. Before any
sample, list the account's voices (`GET /v1/voices`) and models (`GET /v1/models`) and pick from those lists, never
from memory: the first samples were made on `eleven_v3` from an earlier session's notes while the account already
offered `eleven_v4`, "most emotive", and the maintainer had to ask whether it was the best model available.
Say in the pull request which model and why.

**Send two or three voices, one line each, and let the maintainer choose.** Deadnight sent two premade voices (Adam and
Brian) reading the same line; the maintainer chose Brian and no custom or cloned voice. The voice is a maintainer
decision, and so is generating the rest: nothing more is requested until a sample is approved. The two approved
samples (`round_clear_1`, `streak_1`) became takes of the game, encoded like the rest, not requested again.

What Deadnight shipped (`soldier_voice.json`):

| Setting | Value | Why |
| --- | --- | --- |
| Voice | Brian, the ElevenLabs premade voice `nPczCjzI2devNBz1zQrb` | deep, calm and steady at rest, so the expression the lines add reads as a change |
| Model | `eleven_v4` | the account's most emotive model, and it performs audio tags |
| `stability` | 0.0 | the low stability is what lets the tags act: the delivery moves with each line instead of settling into one even read. The first plan used about 0.3 on v3; 0.0 on v4 was what the maintainer approved |
| `similarity_boost` | 0.8 | keeps the takes on Brian's timbre while the delivery swings, so 115 takes sound like one man |
| `style` | 0.6 | exaggerates the speaker's own style, so a shout and a mutter differ more; chosen by ear on the samples, with the other two |
| Output | `mp3_44100_128`, then Ogg Vorbis (see [Encode](#encode)) | the free tier's format; the game ships Ogg |
| Target loudness | -20 LUFS integrated, peak -1 dBFS | one level for every take, whispered or shouted |

The approved model, voice and settings are pinned in a test
([`test_soldier_voice_catalog.gd`][catalog-test]: every manifest entry must carry them), so a later run with other
settings fails instead of slipping in a second voice.

## 2. Writing the lines {#2-writing-the-lines}

**A line is the character reacting, not a caption for the event.** The first sample said "Reload... catch your breath"
and read like a narrator; the maintainer wanted a person reacting out loud, in the first person, with expression,
fillers and plenty of variety (Deadnight #384). So each line is:

- first person, with contractions (`gotta`, `'em`, `outta`, `I'm`);
- a filler, a breath or a repeat where a person under stress would have one ("Come on, come on", "Okay, okay");
- an exclamation where it fits, a question where the character would ask one;
- uneven: some barks are two words, the calm moments are two sentences (10 to 139 characters in Deadnight);
- read aloud by whoever writes it before a character is spent.

**The feeling goes in the words first, the audio tag second.** A tag (`[breathing hard]`, `[tired laugh]`,
`[muttering]`) adds a performance to a line that already carries the emotion; it cannot rescue a caption. Choose the tag
from what the character feels at that moment, not from the event's name:

| Moment's emotion | Tags Deadnight used |
| --- | --- |
| effort, pain | `[grunts]`, `[pained grunt]`, `[sharp inhale]`, `[hissing in pain]`, `[groans in pain]` |
| urgency, alarm | `[shouting]`, `[urgent]`, `[alarmed]`, `[panicked]`, `[tense]` |
| exhaustion, relief | `[breathing hard]`, `[exhales]`, `[sighs]`, `[tired]`, `[relieved laugh]`, `[tired laugh]` |
| triumph, swagger | `[laughs]`, `[excited]`, `[shouting, triumphant]`, `[breathless laugh]`, `[chuckles]`, `[grinning]` |
| fear, awe | `[stunned, whispering]`, `[nervous laugh]`, `[shaky]`, `[gasps]`, `[low, grim]` |
| resignation, aside | `[muttering]`, `[groans]`, `[quiet, thoughtful]`, `[low]` |
| fading | `[weak, gasping]`, `[faint]`, `[pained, fading]`, `[groaning, wheezing]` |

57 different tags across 115 lines; the commonest were `[laughs]`, `[shouting]` (6 each), `[breathing hard]` and
`[grunts]` (5 each). 27 lines have no tag at all ("Reloading!", "Dry! I'm dry, I'm dry!"): a short bark that is
already shouted in its punctuation needs none. Tags combine (`[panting, grinning]`), and a tag can sit mid-line
("HA! Get some! [laughs] Come on, who's next?!").

**Several takes per moment, more for the commonest.** Every moment has at least three (the test fails fewer); Deadnight
has 4 to 10: the most frequent moments have the most (kill 10, reload 9, hurt 8), the rare ones 4 or 5. The director
never replays one of a moment's last three takes (see [In game](#4-in-game)), so with four takes or fewer only one is
ever allowed and the order is nearly fixed; the moments heard most need five or more to stay unpredictable.

**Length follows how often and how urgently it is said.** Measured in Deadnight's takes: kill 1.1 to 2.7 s (mean 1.9),
grenade 2.1, hurt 2.2, reload 0.8 to 3.8 s (mean 2.4); the calm moments run long: round clear 6.6 to 8.5 s, idle
musings 5.3 to 6.8 s. The test fails any take over 9 s ("a speech, not a bark") or under 0.3 s, and fails reload, kill,
grenade and hurt if their mean is 3.5 s or more.

**The caption test.** [`test_a_line_is_written_as_speech_not_as_a_caption`][catalog-test] strips the tags from each
line and fails it if what is left has none of `!`, `?`, `...`, `,` or an apostrophe **and** fewer than four words.
"Reload" fails; "Reloading!" passes. It is a floor, not a judge: the reading aloud is the real check.

**Original lines only.** The brief named another game's soldier as the feel; no line of that game is quoted or
paraphrased (the kit's "original work" rule in `AGENTS.md`).

- **Approach:** Write each line as the character speaking under stress (first person, contractions, a filler or breath,
  an exclamation where it fits), read it aloud before generating, and plan many takes per event so nothing repeats.
  **Watch out for:** a bark is a person reacting in the moment, not a caption: the first line was written as
  instructions to the player, short and clipped, so the voice read it like a narrator and sounded robotic. **Seen:**
  Deadnight #384, 2026-11-01 (fix: the caption test fails a line with no performance mark and fewer than four words
  (Deadnight #442)).

### Deadnight's lines, as the reference {#deadnights-lines-as-the-reference}

A representative set per moment; every line is in [`soldier_voice.json`][json].

| Moment (takes) | Lines |
| --- | --- |
| `round_start` (5) | "[exhales] Okay... here we go again. Stay sharp, everybody!" / "[tense] Here they come. Here they come! Hold the line!" / "[muttering] Oh, great. More of 'em. Of course there's more of 'em." |
| `round_clear` (5) | "[breathing hard] Phew... okay, okay. [tired laugh] Gotta catch my breath real quick, man. These things just don't quit!" / "[relieved laugh] Heh, still standing. Barely, but still standing. Let's patch that fence while we can." |
| `reload` (9) | "Reloading!" / "Reloading, cover me!" / "[grunts] Changing mags, changing mags!" / "[muttering] Come on, come on, load, you stupid thing." |
| `low_ammo` (5) | "[worried] I'm running low here, almost out!" / "Ah, jeez, I'm nearly dry over here!" |
| `dry` (5) | "Dry! I'm dry, I'm dry!" / "[groans] Of course. Of course it's empty." |
| `kill` (10) | "[grunts] Got one!" / "Yeah! Stay down!" / "[through gritted teeth] And stay dead this time." / "Nice, nice. Next!" |
| `streak` (7) | "HA! Get some! [laughs] Come on, who's next?! I got plenty more where that came from!" / "[breathless laugh] Oh, that felt good. Do that again, do that again!" |
| `close_call` (5) | "[gasps] Whoa! Too close, way too close!" / "[breathing hard] Jeez, that one nearly had me. Back off, back off!" |
| `hurt` (8) | "[pained grunt] Ugh!" / "[grunting] Ngh! Get off me!" / "[groans in pain] Ah, son of a... ugh!" |
| `downed` (4) | "[weak, gasping] No... no, no... I'm down... somebody... help..." / "[faint] Not like this... not like this..." |
| `revived` (5) | "[coughs] Jeez, I thought that was it for me. Thanks for the pull!" / "[groans, then laughs weakly] You came back for me. Heh. I won't forget that." |
| `teammate_down` (5) | "[shouting] Man down! We got somebody down!" / "Stay with me, stay with me! I'll get you up!" |
| `buy_weapon` (5), `buy_big` (4) | "[pleased] Oh, now we're talking. Come to papa." / "[laughs] Wallet's empty, but I've never felt so safe." |
| `door` (5) | "Door's open! More room to run, more room to get flanked." / "[low] Easy now. Easy. Don't know what's in there." |
| `power_on` (5), `power_low` (4) | "[laughs] Come on, come on, stay lit. I hate the dark." / "Uh-oh, the lights are flickering. Fuel, we need fuel!" |
| `grenade` (5) | "Frag out! Heads down!" / "[grunts] Catch! Think fast!" |
| `boss_arrive` (5), `boss_dead` (4) | "[stunned, whispering] Oh no. Oh, that's big. That is really, really big." / "[panting, laughing] Is it dead? Tell me it's dead. Oh, thank God it's dead." |
| `idle` (5) | "[sighs] Anyone else hear that? ...No? Just me. Great. I'm losing it." / "[tired chuckle] Funny thing is, I used to hate quiet. Now it scares me more than the noise." |

Notice the patterns: the frequent barks are short and repeat a word ("I'm reloading, I'm reloading!"), a line often
turns halfway ("Quiet. Too quiet. I don't trust it, but I'll take it."), and humour and fear sit side by side, which is
what makes one man out of 115 files.

## 3. The pipeline {#3-the-pipeline}

One recipe, [`elevenlabs_voice.py`][recipe], reads everything from the data file and never from its own code: lines,
voice, model, settings, output format, target loudness. The key comes from `ELEVENLABS_API_KEY` in the environment and
is never printed or written.

```text
ELEVENLABS_API_KEY=... uv run --with requests python tools/audio/elevenlabs_voice.py \
    --ffmpeg <pinned ffmpeg> --cache <workspace>/scratch/<game>-voice-cache <command> [--only event,...] [--budget N]
```

```text
plan ──> generate ──> encode ──> check ──> (flagged?) retake only those ──> encode
```

### Plan {#plan}

`plan` prints every take (file, moment, characters, text) and the characters still to request, sends nothing, and
refuses when that is over `--budget`. Take names are `<moment>_<n>` in the order of the data file, so a file name is
stable as long as lines are appended, not inserted. `--only reload,kill` limits any command to some moments.

### Generate {#generate}

- **One request per take**, `POST /v1/text-to-speech/{voice_id}` with the text, `model_id`, `voice_settings` and a
  **seed**. The seed is `1958 + n`, `n` counting every take in order (the approved samples hold their numbers), and is
  written to the manifest, so a take can be asked for again with the same input.
- **Never request a take twice.** The raw mp3 and the exact request body (`<take>.json`) are kept in the cache folder;
  `generate` only requests takes not in the cache, so a rerun after an error costs nothing. Keep the cache in the
  workspace's `scratch/` (it is not committed), and do not delete it until the pull request is merged.
- `generate` runs `plan` first, so it too refuses over budget.

- **Approach:** Before generating with a vendor API, list its current models (`GET /v1/models`), pick from that list,
  and say in the pull request which model and why. **Watch out for:** the first soldier voice samples were made on
  ElevenLabs `eleven_v3`, chosen from memory, while the account offered `eleven_v4`, listed as the most emotive.
  **Seen:** Deadnight #384, 2026-11-01 (fix: the maintainer asked whether it was the best model available).

### Encode {#encode}

From the cached mp3 to the committed Ogg, with the pinned ffmpeg (`gds tool path`):

1. Mono, 44.1 kHz; trim the lead-in (`silenceremove`, -48 dB) and the tail (reversed, -50 dB, 0.12 s), so a take starts
   when the voice does.
2. Measure its integrated loudness (`ebur128`) and apply the gain to **-20 LUFS**. Before levelling the takes ran
   from -33.5 LUFS (the whispers) to -16.7 LUFS (the shouts); after, a whisper and a shout play at one loudness and the
   performance is in the voice, not the level.
3. Peak-limit to **-1 dBFS** (`alimiter`), fade 4 ms in and 60 ms out.
4. Ogg Vorbis quality 3 with `-fflags +bitexact -flags:a +bitexact`, so two runs give the same bytes.
5. Write `manifest.json`: per file the moment, text, characters, model, voice, voice id, settings, output format, seed,
   source (`text-to-speech` or `maintainer-approved sample`), seconds and loudness before levelling.

### Check {#check}

A tag the model reads aloud ("laughs" spoken as a word) is easy to miss across a hundred takes. `check` transcribes
each take with ElevenLabs Scribe (`POST /v1/speech-to-text`, `scribe_v1`), which writes the sounds it hears in
brackets: a performed tag comes back as `[laughs]`, a spoken one as plain words (Deadnight #442: 0 of 115 flagged).
A take is flagged when a tag's word
appears in the transcript outside brackets (and is not also a word of the line), or when more than a quarter of the
line's words (at least three) are missing. Transcripts are cached (`<take>.stt.json`) and never fetched twice.

Deadnight: 0 of 115 flagged. Some tags are heard as a different sound than written (`[sharp inhale]` as `[inhales]`,
`[through gritted teeth]` as nothing), which is fine for a bark; what matters is that no tag is spoken.

### Retake only what was flagged {#retake-only-what-was-flagged}

Delete the flagged take's mp3, its request and its transcript (`<take>.mp3`, `<take>.json`, `<take>.stt.json`) from
the cache and run `generate` again: nothing else is requested. Leave the transcript and `check` reads the old one. The
same text, settings and seed may well give the same take back, so change something first: reword the tag or the line
in the data file, or give the take a new seed and record it. (Deadnight never needed a retake, so this path is
untested.) Then `encode` and `check` again.

### Adding moments to voices that exist {#adding-moments-to-voices-that-exist}

New moments for a finished cast (Deadnight's eight progression cheers, [#1063](https://github.com/Ryubara/deadnight/issues/1063),
24 takes a voice) go to the **end** of each voice's data file, so that every earlier take keeps its file name and its
seed (names and seeds count takes in file order). Then, with `--only <the new moments>` on every command: `plan` (the
budget is for these takes alone), `generate`, `check`, `encode`. `encode --only` keeps the other takes in the manifest
and writes only what it encoded, so a partial run no longer loses the rest. `encode --plan free --generated <date>`
writes the plan and the day into each new manifest entry: when a game cheers on the free tier now and means to
regenerate under a commercial plan later, that field is the list to regenerate from, and the folder's `LICENSE.md`
names the same files with their prompts. Read the plan from `GET /v1/user/subscription` (`tier`) before and after the
requests, not from the account page: the tier is what made the file. A game that has the moments table as a resource
adds a row per moment, the take count with the files, and the tests that count takes (a total of 278 sounds for two
voices of 139) move with it.

### Credits and budget {#credits-and-budget}

| Deadnight, 113 requested takes (two were approved samples) | Characters |
| --- | ---: |
| Written, with tags (what `plan` counts) | 5,738 |
| Written, without tags | 4,674 |
| Billed for the 113 requests | 5,054 |
| Billed for Scribe on all 115 takes (about 8.5 a take of about 4 s) | 976 |

- **Audio tags are not billed**; the plan counts them anyway, the safe number.
- **Scribe bills the same character quota as speech.** Budget for the check before generating, or it may not fit.
- **The counter lags the requests.** A reading right after a batch is too low (Deadnight's female set read 3,419, then
  6,333, then 6,457 for the same work); read the total once, after a pause, and record that (Deadnight #679: 6,457 of
  10,000 for 115 lines and their check; estimate a batch from what the last set billed, about 1.08 times the characters
  without tags for speech and 8.5 a take for Scribe).
- **A second voice is a second data file.** Deadnight's female soldier (#679) is `soldier_voice_female.json` and
  `--voice female` on the same recipe: the same moments and takes, another premade voice, the same settings, her own
  words only where a line names a sex. Compare loudness per moment against the first voice (within 0.1 LU there).
- The budget (6,500 for this work) is in the recipe's `--budget` and in a test that sums the manifest's
  `text-to-speech` characters, so a later change cannot overspend silently. Read `credits` (`GET /v1/user/subscription`)
  before and after, and put both numbers in the pull request.
- The free tier allows no commercial use and needs attribution: the game records it in the folder's `LICENSE.md` and
  on its Credits screen, and relicensing before a commercial release is the maintainer's call. The studio is now on a
  paid plan (Starter, kit #889), whose output is licensed for commercial use: read `tier` and record it, and the
  route is the one on [Sound effects](sound-effects.md#paid-plan).
- **Generated sounds from the free tier go into a template only with the maintainer's yes and a replace note** (a
  `tier` other than `free` needs neither: [Sound effects](sound-effects.md#paid-plan)). A
  template is copied into every game, so a non-commercial sound there is every game's problem: read the plan first
  (`GET /v1/user/subscription`), stop on `free` and ask; the first set (kit #835, 2026-11-08) went in with a yes, marked
  temporary, a `LICENSE.md` per folder and the line "Replace or relicense before any commercial release" on the
  template's assets page and design page ([Sound effects](sound-effects.md#licence)).

### Proof {#proof}

- [`voice_sheet.py`][sheet] draws the script (moment, line, characters, seconds) as a contact sheet for the pull request,
  so the lines can be read without opening the data.
- A night capture with the soldier speaking records the Voice, Effects and Ambience buses as stems (an
  `AudioEffectRecord` on each bus; [Capturing sound](../../engines/godot/audio.md#capturing-sound));
  [`voice_report.py`][report] measures them. Deadnight's: a line -24.0 LUFS while it speaks, a shot -19.2, the beds
  -34.6, so the voice sat 4.8 LU under the guns and 10.6 LU over the beds. Attach the chart, the sheet and a clip with
  sound.

## 4. In game {#4-in-game}

Three pieces, each with its own tests ([design][design]):

- **The catalog** ([`SoldierVoiceCatalog`][catalog]) is the table of moments. Each has `takes` (the file count),
  `priority`, a per-speaker `cooldown` in seconds and a `chance` that the moment is voiced at all. Every take is its own
  sound (`vox_<moment>_<n>`), so the director, not the audio service's random pick, chooses which plays.
- **The node** ([`SoldierVoice`][node]) turns what the server sent into moments: `reload_started` is `reload`, four
  kills within six seconds are a `streak` (else a `kill`), a blow that leaves a third of health adds a `close_call`,
  a player going down makes the nearest standing teammate say `teammate_down` 0.4 s after the fallen one's line,
  `round_start` waits 1.6 s for the sting. `idle` plays after five quiet seconds in a break with eight more to run, or
  ten seconds of a round with no dead within 30 m. A downed player says nothing but `downed`.
- **The director** ([`VoiceDirector`][director]) decides, on a clock the owner moves (no wall time, so tests run at any
  speed):
    - **One voice at a time.** A line owns the channel until it ends plus 0.5 s; a request that meets a busy channel is
      dropped, never queued: a bark belongs to its moment. Teammates share the channel, so four players reloading are
      one voice.
    - **Priority.** `downed` 100 and `hurt` 90 may cut any lower line; any other line may cut one 25 ranks below it
      (a streak 60 over a kill 30). Boss 75, close call 70, ... reload 45, kill 30, idle 10.
    - **Cooldown and chance.** Reload 6 s and 70%, kill 5 s and 45%, streak 20 s, idle 40 s: the commonest moments are
      not a running commentary.
    - **Variety.** A moment never repeats one of its last three takes, from a seeded generator, so a night replays the
      same way in a test.

**Buses and level.** The takes play on a **Voice** bus that is never ducked (what you hear of yourself is never pushed
under a sting), at -4 dB (`VOICE_DB`). The player's own voice is flat (in their head) and another 2 dB lower
(`LOCAL_DB`); a teammate's comes from where they stand, at head height, heard to 40 m with `unit_size` 6. Those two
numbers were set from the stems capture above. Pooling, groups and the slot budget are the audio service's
([Godot: Audio](../../engines/godot/audio.md#service-shape-that-worked)).

- **Approach:** Bound how often one speaker talks with a window (at most N lines in T seconds) as well as each line's
  cooldown, and test the worst case (every kind of trouble at once for minutes), not a typical night. **Watch out
  for:** twelve bot callouts, each with a 20 to 60 s cooldown and a short gap before an urgent one, let a bot say 1.4
  lines in ten seconds. **Seen:** Deadnight #229, 2026-11-02 (fix: a window of lines, 0.8 lines in ten seconds at
  most by construction).

## 5. The zombies are different {#5-the-zombies-are-different}

The dead have no words, so they do not use text to speech: their voices are mostly synthesised (one throat model,
[Godot: Audio](../../engines/godot/audio.md#making-sounds-with-code)) and ElevenLabs **Sound Effects** adds extra variants
(`POST /v1/sound-generation`, [`elevenlabs_zombies.py`][zombies], every prompt and model in
[`zombie/eleven.json`][zombie-json]):

| | Soldier (text to speech) | Zombies (sound effects) |
| --- | --- | --- |
| Input | a written line with audio tags | a prompt describing the sound |
| Model | `eleven_v4` | `eleven_text_to_sound_v3`, falling back to `v2` when the API does not know it |
| Repeatable | a seed per take | no seed: variety comes from asking again |
| Selection | every take kept; Scribe flags tags read aloud | three candidates a slot, picked by analysis: hiss above 5 kHz, silence inside the take, a slow onset on the short sounds; any clipping is rejected |
| Clean-up | trim, -20 LUFS, -1 dBFS peak | trim, low-pass at 8 kHz on the voices, fades, normalised to the synthesised variants' peak (-3 dBFS) |
| Cost | characters (tags free) | 40 credits per second of requested length planned; billed 10 a second on the free tier and on the paid starter plan in 2026 ([Sound effects](sound-effects.md#what-a-request-costs)) |
| Bus | Voice, never ducked | Effects, ducked under a sting like every sound of the lot |
| Playback | one at a time, by the director | rationed: one idle voice every 0.6 to 1.6 s for the whole horde, six zombie voices at most ([Godot: Audio](../../engines/godot/audio.md#a-crowds-voices-the-dead)) |

The prompts that worked name a single sound and keep the room out: "One-shot, an undead man's short rising rasping
snarl as he spots prey, guttural, close-mic, dry, no reverb" (`prompt_influence` 0.45). The game places the sound
itself (distance attenuation and low-pass, a rear cue), so a take should arrive dry and close; "no music" keeps a
score out of it.

## 6. Checklist for the next game {#6-checklist-for-the-next-game}

1. Write the brief for each voice (who, how they sound at rest, what moments they react to) and get it from the
   maintainer.
2. List the account's models and voices (`GET /v1/models`, `GET /v1/voices`); pick the most expressive model that
   performs audio tags; name it and why in the issue.
3. Send two or three voices reading one line in character; wait for the maintainer to choose the voice and the settings.
   Start from Deadnight's (stability 0.0, similarity 0.8, style 0.6).
4. List the moments from the game's events, with a priority, cooldown and chance each; plan 4 to 10 takes per moment,
   most for the commonest.
5. Write the lines as the character speaking (contractions, fillers, breaths, exclamations, uneven length), the feeling
   in the words, a tag only where it adds; read every line aloud. Original lines only.
6. Put voice, model, settings, target loudness and lines in a data file; copy Deadnight's recipe and change only its
   paths and seed base.
7. `credits`, then `plan` with a `--budget` that leaves room for the Scribe check (about 8.5 characters a take).
8. `generate` (cache in `scratch/`), `encode` (-20 LUFS, -1 dBFS, Ogg q3 bit-exact), `check`; retake only what was
   flagged, with a changed tag or seed.
9. Commit the Oggs, `manifest.json` and a `LICENSE.md` entry; name the service on the Credits screen; the licence
   question goes to the maintainer.
10. Wire catalog, node and director; tests for approved settings, budget, caption lines, lengths, every take on disk
    and in the catalog, and the director's priority, cooldown, variety and no overlap.
11. Capture a night with stems, measure the voice against the guns and the beds, and attach the chart, the script's
    contact sheet and a clip with sound to the pull request.

[json]: https://github.com/Ryubara/deadnight/blob/main/tools/audio/soldier_voice.json
[recipe]: https://github.com/Ryubara/deadnight/blob/main/tools/audio/elevenlabs_voice.py
[zombies]: https://github.com/Ryubara/deadnight/blob/main/tools/audio/elevenlabs_zombies.py
[zombie-json]: https://github.com/Ryubara/deadnight/blob/main/game/assets/audio/zombie/eleven.json
[manifest]: https://github.com/Ryubara/deadnight/blob/main/game/assets/audio/voice/soldier/manifest.json
[licence]: https://github.com/Ryubara/deadnight/blob/main/game/assets/audio/voice/soldier/LICENSE.md
[catalog]: https://github.com/Ryubara/deadnight/blob/main/game/core/audio/soldier_voice_catalog.gd
[node]: https://github.com/Ryubara/deadnight/blob/main/game/gameplay/night/soldier_voice.gd
[director]: https://github.com/Ryubara/deadnight/blob/main/game/gameplay/night/voice_director.gd
[catalog-test]: https://github.com/Ryubara/deadnight/blob/main/game/tests/core/test_soldier_voice_catalog.gd
[report]: https://github.com/Ryubara/deadnight/blob/main/tools/audio/voice_report.py
[sheet]: https://github.com/Ryubara/deadnight/blob/main/tools/audio/voice_sheet.py
[design]: https://github.com/Ryubara/deadnight/blob/main/docs/design/audio.md#the-soldiers-voices
[research]: https://github.com/Ryubara/deadnight/blob/main/docs/research/audio.md#the-soldiers-voice-384
