# Capture: proof you can look at

Every visual change needs proof attached to its pull request. `gds capture` does the three steps with the pinned
tools, so nobody writes Movie Maker command lines by hand: record frames, tile them into a contact sheet that can be
read in one look, and encode a clip. A sound needs a clip you can listen to ([Sound](#sound-a-clip-you-can-listen-to)).

```text
gds capture frames --project <game>/game --scene res://x.tscn --seconds 6 --fps 10 --name hud
gds capture sheet  <folder> --every 5 --columns 5
gds capture clip   <folder> [--gif]
```

Run them with `uv run --project <workspace>/repos/gdstudio/python gds capture ...`.

## frames {#frames}

Runs the pinned Godot with [Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)
in a real window (not `--headless`: Movie Maker needs a renderer). The window opens on a private Windows desktop, so
it never takes the keyboard or cursor from the person at the machine ([why](../engines/godot/no-focus.md)). The scene
runs on a
fixed timestep, so a seeded scene gives the same frames every time. To record with your own command line (several
scenes, extra arguments) use `gds godot -- --path <game> --write-movie ...`, never the Godot program itself.

| Option | Meaning |
| --- | --- |
| `--project` | The game's project folder, the one holding `project.godot` (required). |
| `--scene` | A scene to run instead of the main scene, e.g. `res://ui/hud.tscn`. |
| `--seconds`, `--fps` | Length and rate; the capture is at most `ceil(seconds * fps)` frames: a scene that calls `quit()` ends it sooner, so `--seconds` is an upper bound. Defaults 5 s at 10 fps. |
| `--name` | The folder name (default `capture`). |
| `--out` | Write the frames to exactly this folder instead of the scratch folder below. |

The frames go to `<workspace>/scratch/<repo>/<branch>/<name>/` as `<name>00000000.png`, `<name>00000001.png`, ...
next to Movie Maker's `<name>.wav` and a `capture.json` holding the frame rate. The repository and branch come from
the folder `gds` runs in, never from `--project`, so run it from your task's worktree: a throwaway game made by
`gds template game` is a git repository of its own, and naming the folder from it would put every agent's frames in
the shared `scratch/template-check/main/`. The rule is the hooks' one: the repository is the git top level's name (for
a worktree `worktrees/<repo>/<branch>`, the parent folder's name) and a `/` in the branch becomes `-`. Outside a git
repository, pass `--out <folder>`. Frames from an earlier
run of the same name are replaced. A project that was never imported is imported first.

Frames are the project's viewport size (Godot's `--resolution` has no effect on Movie Maker); the sheet and the clip
scale them down. Godot's `ERROR` lines are printed and flagged: a capture with errors is not proof.

- **Approach:** Take captures and recordings through the camera the player has (in Deadnight the over-the-shoulder
  camera), never a spectator camera. **Watch out for:** the bot was filmed through a spectator camera, which shows the
  game as no player sees it. **Seen:** Deadnight, 2026-11-01 (fix: deadnight's recordings come from the player's camera
  with the real devices switched off).

- **Approach:** For a phone-shaped window (844 x 390, a canvas of 2337 x 1080 units) save the viewport's own pixels
  from the capture scene (`await RenderingServer.frame_post_draw`, then
  `get_viewport().get_texture().get_image().save_png`), and keep Movie Maker for sizes whose canvas is 1920 units wide
  or less. **Watch out for:** Movie Maker writes frames of the project's size (1920 x 1080) whatever `--resolution`
  says and cuts a wider canvas at both sides, so the first phone captures of the menus showed the middle of every card
  and looked like a layout fault. **Seen:** gdstudio #881, 2026-11-10 (`tools/capture/menus_tour.gd`,
  `--shots=<folder>`).
- **Approach:** Read frame N-1 to see the state before a change made at step N; to record at a real smaller size (a UI
  test at 720p) write an uncommitted `game/override.cfg` with `window/size/window_width_override` and
  `window_height_override` (the stretch base stays 1920 x 1080, so the UI scales as for a 720p player), and delete it
  afterwards. **Watch out for:** frame N is written after that step's script ran, so it already shows the change; the
  movie is the project's viewport size, and `--write-movie` with `--resolution 1280x720`, or a window resized from a
  script, still wrote 1920x1080 frames (Godot 4.7.2). **Seen:** Deadnight #442, 2026-11-01 (fix: `gds capture sheet`
  and `clip` scale afterwards).
- **Approach:** Look at every spot's frame of a tour before believing it: give each spot the floor and collision a
  player would stand on (a hidden floor under every spot outside the room), and when comparing variants loop over full
  triples (name, player look, teammate look), print each run's looks in its log and read one picture of each run.
  **Watch out for:** a yard shot showed sky and a band of horizon because the backdrop's ground has no collision and
  the player fell through; a him-and-her pair that varied only the player's preset passed the teammate as a literal, so
  both runs showed two Carhops. **Seen:** Deadnight, 2026-11-03 (backdrop tour); Deadnight, 2026-11-02 (shoulder views)
  (fix: `[female] loadout character: ...` is printed by each run).

- **Approach:** Count a capture scene's waits in physics ticks and size `--quit-after` (which counts rendered frames)
  as ticks / 6 at `--fixed-fps 10`; make effects in a captured scene live 0.2 to 0.3 s, look at single frames next to
  a shot (not only a sheet), and cross-check them against a headless log of the events. **Watch out for:** Movie Maker
  renders one image per 1 / fixed-fps seconds while the physics step stays 60 a second, so six physics frames pass
  between two images: 150 `physics_frame` waits for a 2.5 s action ended after 25 frames, and a tracer or flash that
  lives 0.1 s fell between two frames and was in none. **Seen:** Deadnight, 2026-11-01 (fix: waits in ticks, effects
  that live 2 to 3 frames).

## sheet {#sheet}

Tiles every `--every`-th frame (default 1) in `--columns` columns (default 4) into `sheet.png` in the folder. Tiles
are 480 px wide with the frame number in the corner. Pick `--every` so that the sheet has about 8 to 24 tiles, then
read it with the Read tool and fix what looks wrong.

`sheet` and `clip` read any folder of frames, not only one `frames` wrote: a frame is a PNG named
`<prefix><number>.png`, with one prefix and one number width for the whole folder, numbered in order from the first
(`capture00000000.png`, `capture00000001.png`, ... as Movie Maker writes them; `shot001.png`, `shot002.png` also
works). Frames recorded another way are renamed to that pattern first: a folder whose PNG files are named otherwise
(`walk-front.png`) has no frames, and the error lists the files it skipped.

## clip {#clip}

Encodes the folder's frames into `<name>.mp4` (H.264, `yuv420p`, no audio) or, with `--gif`, `<name>.gif` with a
128-colour palette at up to 12 fps. The clip is cut at 30 s and has to stay under 9 MB (GitHub takes 10 MB for most
attachments): it is encoded at 1280 px wide and, while too big, again at 960, 720 and 480 px, then the command fails.

## Attaching {#attaching}

```text
cd <folder> && gh pr create -R <owner>/<repo> --body-file <folder>/body.md --attach ./sheet.png --attach ./<name>.mp4
```

`--attach` (on `gh pr create` and `gh pr edit`) appends the images at the end of the body, outside `## Screenshots`,
and the body check refuses `Before:`/`After:` until they sit there. Write `![before](../before.png)` on the `Before:`
line and `![after](../sheet.png)` on the `After:` line so `--attach` replaces each reference with the upload in place.
**`gh` swaps a reference only when it names the same file as an `--attach` path**, and it reads a relative path from
the folder it runs in, not from the body file. Captures live in `<workspace>/scratch/...` and the command usually runs
in the worktree: `--attach <scratch>/before.png` with a `./before.png` reference is two different files, so the
reference stays local and the upload is appended after `## AI use` (Deadnight #611, #637 and more reached CI that way).
So `cd` into the folder that holds the images first and attach `./<file>` (any form of the path works there:
`./sheet.png`, `sheet.png`, the absolute path), or write the reference with the same absolute path as `--attach`. Then
read the body back and check the image lines sit under the bullets
([Writing checks](writing-checks.md#same-input)). Seven Deadnight pull requests hit the appended images before the
guard below existed (#448 to #565); the written lesson alone did not stop it.

The hooks enforce it ([Hooks](hooks.md)): `gh pr create|edit --attach` is refused before it runs unless the body file
named with `--body-file` (or a literal `--body`) already refers to every attached file inside `## Screenshots`, with an
image between `Before:` and `After:` (or `Before: none (reason)`) and one below `After:`. The refusal names the missing
files and the line to write. Write the body file first (with the Write tool, not in the same command), and an existing
body is copied from `gh pr view N --json body -q .body`. A reference whose path is not the attached file's, from the
folder the command runs in, is refused with both places named ([Hooks](hooks.md#attach-paths)). Say "attached" in a
report only after reading the body back.

- **Approach:** Attach uploaded before and after captures (screenshots or a clip) to every issue and pull request that
  changes something a player sees. **Watch out for:** work was judged from its text, so nobody saw what had changed.
  **Seen:** Deadnight, 2026-11-01 (fix: the pull request body check refuses a visual change without its `Before:` and
  `After:` images ([Hooks](hooks.md#pr-body))).
- **Approach:** Give `--attach` the very file name the body links: when a capture is renamed or swapped (a `.png` for
  an `.mp4`), change the `./<file>` reference in the body file in the same step. **Watch out for:** `gh` swaps a
  reference by name only, so `![after](./gate-after.mp4)` beside `--attach ./gate-after.png` stays a local path and
  the upload goes to the end of the body. **Seen:** gdstudio #847, 2026-11-08 (its first body linked
  `./gate-after.mp4`; the one sent links `./gate-after.png`, the file attached).
- **Approach:** Put an image on the `After:` line (a still, or a [contact sheet](#sheet) of the clip) and the clip's
  bare upload address beside it, as for [sound](#sound-a-clip-you-can-listen-to); run `gds pr check-body` on the body
  read back after `gh pr create --attach`, not on the body file. **Watch out for:** `![after](./x.mp4)` becomes a
  plain link after the upload, which the screenshots rule does not count as a capture, and before the upload the rule
  refuses every local `./file`, since only a `github.com/user-attachments/` address counts; a body with no image
  reference got past the guard (`--repo`, run from scratch) to CI. **Seen:** gdstudio #847, 2026-11-08; gdstudio
  #937, 2026-11-10 (the uploads moved onto `After:` with `gh pr edit --body-file`); gdstudio #880 and #886, 2026-11-10
  (the guard of today refuses that `--repo` command with no reference: checked for gdstudio #1003).

## Sound: a clip you can listen to {#sound-a-clip-you-can-listen-to}

Every pull request that adds or changes a sound carries a clip with the sound in it, because a spectrogram and a
loudness chart prove the numbers and nobody can hear them. `gh --attach` takes images and videos only, so an `.ogg` or
`.wav` is not attached: the sound goes in as the audio track of an `.mp4`. `gds capture clip` has no audio, so this one
is made with the pinned ffmpeg (`gds tool path ffmpeg`).

- **Use the game's recording.** Take the sound from a capture of the real audio service at the default settings, as the
  player hears it, not the asset file. **Never normalise**: a limiter or a loudness filter hides the question the
  listener is there to answer. Compare the source's peak and the encoded clip's (`-af volumedetect`): they match to
  about 0.1 dB.
- **Name what is playing.** One title card a section, a gap of about half a second between sounds, the waveform below
  the title.
- **Put it in its context.** A sound heard in a fight is also played beside what it must not hide (a shot, a groan,
  the night's bed), with the reference alone first. A sum of two recordings is the recording of both when the buses
  have no effects; a level the game applies at run time (a trim in a fight) is applied to the sound and said on the
  card.

```text
ffmpeg -i mix.wav -f concat -safe 0 -i cards.txt \
  -filter_complex "[0:a]showwaves=s=1280x300:mode=cline:rate=30:scale=sqrt:colors=white[w];[1:v]fps=30,format=yuv420p[b];[b][w]overlay=0:330:shortest=1,format=yuv420p[v]" \
  -map "[v]" -map 0:a -c:v libx264 -crf 26 -c:a aac -b:a 192k -movflags +faststart <name>.mp4
```

`mix.wav` is the sounds and gaps in order. `cards.txt` is an ffmpeg concat list, `file 'card_01.png'` and
`duration <seconds>` for each section (repeat the last `file` line). A 36 s clip of twelve sections is about 5 MB; keep
it under the 9 MB of [clip](#clip).

Attach it in two steps. `--attach` with `![listen](../<name>.mp4)` under `## Screenshots` uploads the file, but the
reference becomes a plain link, not a player: **GitHub draws a player only for the bare upload address on its own
line.** Read the body back, replace the link with the address alone, with a blank line on each side, and `gh pr edit
--body-file` again. Check it with `gh api
repos/<owner>/<repo>/pulls/<N> -H 'Accept: application/vnd.github.html+json' --jq .body_html`: the body holds a
`<video` tag.

## What proves a feature {#feature-proof}

<!-- new section: the sections above say how to take a capture; none says that every feature names its own proof and
that agents run it -->

- **Approach:** Name each feature's own proof when the work starts (input simulation, a bot run, audio analysis, a
  browser run) and run it yourself; nothing is handed to the maintainer to try. **Watch out for:** asking the maintainer
  to try it had become the default proof. **Seen:** Deadnight, 2026-11-01 (fix: agents prove features with GdUnit4 input
  simulation, autopilot bots, audio analysis and browser probes, and the `Stop` hook holds back a visual change without
  a capture ([Hooks](hooks.md#proof))).

## Before captures {#before-captures}

A `Before:` capture needs the code from before the change, and the task's worktree has no copy of it after the first
edit (`git stash` is refused by the hooks). Take them from `main` checked out beside the change: `git worktree add
--detach <workspace>/scratch/<repo>/<task>/baseline origin/main`, `godot --headless --path game --import` once, and run
the same tours and probes there with `--label=before` for every size the pull request shows (the desktop window, the
phone's 844 by 390 and the web export), then `git worktree remove` it.

- **Approach:** Capture a feature's payoff (a machine's reveal, a prompt) from the player's camera at the spot the
  player stands on to use it, on desktop and phone, before it ships. **Watch out for:** the prize crane's reveal floated
  3.25 m up, spun end on for half of each turn in front of the brightest beam, and from the shoulder camera on the use
  marker sat at the top of the frame behind the player's own body; it had been filmed from a spot no player stands on.
  **Seen:** Deadnight #830, 2026-11-03 (fix: every pool weapon's reveal is captured from the use marker).

- **Approach:** Take every `Before:` capture from `main` checked out beside the change, for every size the pull request
  shows at once (desktop, phone, web), and never put old files back under a running test. **Watch out for:** the first
  "before" frames covered the desktop window only, and once the code had changed the phone and web ones could not be
  taken, while `git stash` is refused by the hooks; old weapon files checked out for a capture were read by a suite that
  started during the swap. **Seen:** Deadnight, 2026-11-03 (two cases; fix: a detached baseline worktree under scratch,
  the same capture scripts with `--label=before`).

## Tests {#tests}

`python/tests/test_quiet_run.py` runs the real pinned Godot and Movie Maker on Windows with a test window holding the
foreground. `python/tests/test_capture.py` replaces Godot and ffmpeg with fakes that record the command line and
write files, so the tests run anywhere. The real programs are exercised by hand on a game, as in the pull request
that added this.
