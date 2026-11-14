# Capture: proof you can look at

Every visual change needs proof attached to its pull request. `gds capture` does the three steps with the pinned
tools, so nobody writes Movie Maker command lines by hand: record frames, tile them into a contact sheet that can be
read in one look, and encode a clip. A sound needs a clip you can listen to ([Sound](#sound-a-clip-you-can-listen-to)).

```text
gds capture frames --project <game>/game --scene res://x.tscn --seconds 6 --fps 10 --name hud
gds capture sheet  <folder> --every 5 --columns 5
gds capture clip   <folder> [--gif] [--max-seconds N]
```

Run them with `uv run --project <workspace>/repos/gdstudio/python gds capture ...`.

## frames {#frames}

Runs the pinned Godot with [Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)
in a real window (not `--headless`: Movie Maker needs a renderer). The window opens on a private Windows desktop, so
it never takes the keyboard or cursor from the person at the machine ([why](../engines/godot/no-focus.md)). The scene
runs on a
fixed timestep, so a seeded scene gives the same frames every time. To record with your own command line (several
scenes, extra arguments) use `gds godot -- --path <game> --write-movie ...`, never the Godot program itself. Both add
`++ --quit-after=N` to a Movie Maker run's command line, so the game can silence its last frames before Godot stops it
and the log ends with nothing `still in use` ([why](../engines/godot/audio.md#capturing-sound)).

| Option | Meaning |
| --- | --- |
| `--project` | The game's project folder, the one holding `project.godot` (required). |
| `--scene` | A scene to run instead of the main scene, e.g. `res://ui/hud.tscn`. |
| `--seconds`, `--fps` | Length and rate; the capture is at most `ceil(seconds * fps)` frames: a scene that calls `quit()` ends it sooner, so `--seconds` is an upper bound. Defaults 5 s at 10 fps. |
| `--name` | The folder name (default `capture`). |
| `--out` | Write the frames to exactly this folder instead of the scratch folder below. |

The frames go to `<workspace>/scratch/<repo>/<branch>/<name>/` as `<name>00000000.png`, `<name>00000001.png`, ...
next to Movie Maker's `<name>.wav`, a `capture.json` holding the frame rate and `godot.log`, the game's whole output
(each line is also printed as `godot: ...`, the game's own `print` lines and errors with the engine's; gdstudio #1472).
The repository and branch come from
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

- **Approach:** Record a capture of an online rig (a server and its clients in one process, `OnlineRig`) at
  `--fps 60`, one physics tick a frame, and crop or slow the clip afterwards. **Watch out for:** at `--fps 10` Movie
  Maker runs six ticks in each frame, and a client that judges its stalls by process frames (`StallGuard`) no longer
  plays as it does at a game's frame rate, so the clip is not the game: the AI rewind's tour hit 1 of 3 at 10 frames
  a second, 2 of 3 at 30 and 3 of 3 at 60, where the same scene run headless hit 3 of 3. **Seen:** gdstudio #1198,
  2026-11-11 (`tools/capture/ai_rewind_tour.tscn`).
- **Approach:** Count a capture scene's waits in physics ticks and size `--quit-after` (which counts rendered frames)
  as ticks / 6 at `--fixed-fps 10`; make effects in a captured scene live 0.2 to 0.3 s, look at single frames next to
  a shot (not only a sheet), and cross-check them against a headless log of the events. **Watch out for:** Movie Maker
  renders one image per 1 / fixed-fps seconds while the physics step stays 60 a second, so six physics frames pass
  between two images: 150 `physics_frame` waits for a 2.5 s action ended after 25 frames, and a tracer or flash that
  lives 0.1 s fell between two frames and was in none. **Seen:** Deadnight, 2026-11-01 (fix: waits in ticks, effects
  that live 2 to 3 frames).
- **Approach:** After a capture script moves its camera to the next view, let one frame draw before it saves (await
  `RenderingServer.frame_post_draw` twice, or take the shot twice and keep the second). **Watch out for:** the first
  image saved after the move still showed the view before it, so a close-up sheet had one stale tile per view.
  **Seen:** gdstudio #1081 (PR #1103), 2026-11-11.
- **Approach:** When a tour's printed lines are part of the proof (each step's name, a measured number), have the
  scene also write them to a file under the capture folder, or record with `gds godot -- --path <game> --write-movie
  ...`, which keeps the game's output in the terminal (Godot's
  `--log-file <path>` after `--` keeps it in a file). **Watch out for:** `gds capture frames` kept Godot's output
  to itself and showed only its `ERROR` lines, so a tour's `print` step lines never appeared and its log could not be
  read beside the frames. **Seen:** gdstudio #1111 (PR #1191), 2026-11-11; #1037 (PR #1239), 11-11 (fix: since
  gdstudio #1472 it prints every line and writes `godot.log` beside the frames).
- **Approach:** Run `gds capture frames` on a game made from the template (`gds template test <t> --keep` or `gds
  template game <t>`), never on the template's own `game/` folder. **Watch out for:** a template's `game/` folder has no
  GdUnit4 and is not a game one opens (a new game gets its addons and its import when it is made), so a capture pointed
  at it does not film the game. **Seen:** gdstudio #1160 (PR #1285), 2026-11-11.

- **Approach:** Give `gds capture frames --project` an imported game: for a template, the kept game of `gds template
  test <template> --suite <one suite> --keep` (run from its folder with `--out` into your scratch folder; remove the
  kept folder afterwards), and look at a frame of every variant's turn before making the clip. **Watch out for:** a
  worktree's own `templates/<t>/game/` was never opened by the editor, so the run logged 547 errors and wrote
  `.godot` and `.import` files into the worktree; the 3D Third Person spawn pad ends 4.6 m ahead, so bodies filmed
  walking off it played their fall (`OWN_AHEAD`); and that offset, read from the camera at each turn's start while
  it still looked back at the body, put later variants 6 m behind the spawn. **Seen:** gdstudio #1155, 2026-11-11.

## sheet {#sheet}

Tiles every `--every`-th frame (default 1) in `--columns` columns (default 4) into `sheet.png` in the folder. Tiles
are 480 px wide with the frame number in the corner. Pick `--every` so that the sheet has about 8 to 24 tiles, then
read it with the Read tool and fix what looks wrong.

`sheet` and `clip` read any folder of frames, not only one `frames` wrote: a frame is a PNG named
`<prefix><number>.png`, with one prefix and one number width for the whole folder, numbered in order from the first
(`capture00000000.png`, `capture00000001.png`, ... as Movie Maker writes them; `shot001.png`, `shot002.png` also works).
The number is at most 8 digits, so a prefix may end in a digit (`run200000000.png` is `run2` and frame 0; it was read as
one 9-digit number and ffmpeg found no frames, #1132). The first frame may have any number: `clip` tells ffmpeg where to
start, which by itself looks for a first frame numbered 0 to 4 only (Blender's `legs20001.png` in a folder `legs2` is
read as `legs` and frame 20001, and a folder starting at `16.png` is fine too; both failed before #1190). Frames
recorded another way are renamed to that pattern first: a folder whose PNG files are named otherwise (`walk-front.png`)
has no frames, and the error lists the files it skipped.

## clip {#clip}

Encodes the folder's frames into `<name>.mp4` (H.264, `yuv420p`, no audio) or, with `--gif`, `<name>.gif`. Which
of the two a clip should be is [GIF or MP4](#gif-or-mp4). The clip is cut at 30 s (`--max-seconds N` for another cut)
and has to stay under 9 MB (GitHub takes 10 MB for most attachments): an MP4 is encoded at 1280 px wide and, while too
big, again at 960, 720 and 480 px, then the command fails. When frames run past the cut, it prints a line with how many
frames and seconds were left out (`clip cut at 30 s: 120 frames (12 s) of 420 left out`): read it before you attach
the clip, since the part you meant to show may sit in what was cut (#1090 sent such a clip before the line
existed, #1132). Raise `--max-seconds`, or capture a shorter run that starts nearer the moment.

The frames play at the rate `gds capture frames` recorded in `capture.json`, or 10 fps for a folder without one;
`--fps N` names the rate they were recorded at (frames from Blender or another tool at 24, 30 or 60 fps). `--slow N`
plays them N times slower with every frame kept, to show a jitter or a fast pose change: `gds capture clip <folder>
--slow 4` turns 2 s of 30 fps frames into an 8 s clip at 7.5 fps (N may be a fraction, `--slow 2.5`). The cut and a
GIF's length and budget count the slowed clip, so a slowed GIF passes 10 s soon; a slowed clip is usually an
[MP4](#gif-or-mp4). Before #1190 a slowed clip was made with ffmpeg by hand.

A GIF has a budget of its own, measured for [GIF or MP4](#gif-or-mp4): 512 KB for each second of it, counted for at
least 2 s and at most 10 s (1 to 5 MB). It is encoded with a 128-colour palette at 800 px wide (GitHub's description
column is 814 px) and, while over the budget, again at 640 and 480 px. Its frame rate is 10 fps, or 20 fps from frames
recorded at 20, 40 or 60 fps, because a GIF's delays are whole hundredths of a second; a slowed rate whose delay is
already whole keeps every frame (10 fps with `--slow 3` plays at 10/3 fps, 30 hundredths a frame). Every encoding
prints its size. A GIF longer than 10 s, or still over its budget at 480 px, is kept with a `warning:` line that names
the MP4; one over 9 MB fails.

A clip has no sound: `gds capture frames` writes the run's audio beside the frames as a `.wav` when the scene plays
any, and a gameplay clip whose sound matters is muxed from the two with the pinned ffmpeg (`gds tool path ffmpeg`),
scaled to the 1280 px `clip` uses:

```text
ffmpeg -framerate <fps> -i <folder>/<prefix>%08d.png -i <folder>/<name>.wav -vf scale=1280:-2 \
  -c:v libx264 -pix_fmt yuv420p -crf 23 -c:a aac -b:a 192k -shortest -movflags +faststart <name>.mp4
```

Match `%08d` to the frame names' digits, and read [Sound](#sound-a-clip-you-can-listen-to) for a clip made to be
listened to.

- **Approach:** Give a failing `clip` run a new name, or copy the clip that works aside before encoding again into the
  same folder. **Watch out for:** `clip` deletes `<folder>.mp4` or `<folder>.gif` before each encoding, so a run that
  fails (ffmpeg's error, still too big at 480 px) leaves no clip at all where a good one was. **Seen:** gdstudio
  #1190 (PR #1197), 2026-11-11.
- **Approach:** For a GIF of several bodies side by side (a grid of variants), capture at 20 fps or more so the GIF
  keeps 20 fps, and plan on 480 px: give each body the frame's full height and few pixels of empty floor, or make an
  MP4 when the detail matters. **Watch out for:** `--gif` plays 60 fps frames at 20 fps (whole hundredths), and three
  bodies on a grid fitted the GIF budget only at 480 px, where a hand or a foot is a few pixels. **Seen:** gdstudio
  #1172, 2026-11-11.

## GIF or MP4 {#gif-or-mp4}

<!-- new section: clip said how to make a GIF and never when a clip should be one; agents chose by habit (#1153) -->

Choose for every clip, on a pull request and on an issue. A GIF plays inline the moment the page opens, loops and
needs no click, so the maintainer prefers it for simple things; an MP4 carries sound, length and detail.

| The clip | Make | Write it in the body as |
| --- | --- | --- |
| Short (10 s or less), silent, showing one thing: a UI change, a pose, a short motion | a GIF: `gds capture clip <folder> --gif` | an image on the `Before:` or `After:` line: `![after](./<name>.gif)` |
| Any sound (the [listening clip](#sound-a-clip-you-can-listen-to)) | an MP4 with its audio track | `![listen](./<name>.mp4)` alone on its line, which `--attach` turns into the bare upload address (a player) |
| Longer than 10 s, or a change that unfolds over time | an MP4: `gds capture clip <folder>` | `![clip](./<name>.mp4)` alone on its line under `After:`, a still or [sheet](#sheet) on `After:` |
| Detail a 128-colour palette loses (gradients, fog, light falloff, fine texture), fast or fine motion, slowed playback | an MP4 | the same |
| A loop that helps the reader beside detail that needs the MP4 | both | the GIF on `After:`, the MP4's address below it |

A GIF that `gds capture clip --gif` warns about is the wrong choice: make the MP4, or capture a shorter run that starts
nearer the moment. [Attaching](#attaching) and [Images](pull-requests.md#attach) have how each is uploaded.

What the budget rests on (gdstudio #1153, 2026-11-11): Chromium 1243 playing GIFs of a 3D Third Person capture with
the download throttled, the picture's changes read from the compositor's screencast (a canvas cannot sample it: drawing
an animated image draws its first frame).

- **A GIF plays while it downloads**, frame by frame as the bytes arrive, so it stalls on its first play when its bytes
  a second outrun the connection, and plays at its own rate once it has arrived, whatever its size: every GIF up to
  1280 px kept its 100 ms frames (p95 under 135 ms) after loading. So the budget is a rate, not a size.
- **Frame delays are whole hundredths of a second.** ffmpeg wrote 12 fps as delays of 8, 8 and 9 and 15 fps as 6, 7
  and 7, an uneven step; 10 and 20 fps are even.
- **GitHub's description column is 814 px** (signed out, windows from 1280 to 2560 px wide), and an image in a list
  item (`- **After:**`) is drawn 758 px wide; a wider GIF only costs bytes.
- **GitHub serves the upload as it is**: the address redirects to the stored file (`image/gif`, the same 4,055,821
  bytes as the local one), so a GIF plays on a pull request as it played here. On gdstudio #1167 the `After:` GIF
  showed 27 different frames in 3 s of the page.

Stalls on the first play (a frame held over 150 ms while the file arrived) and the time until all of it had arrived,
GIFs at 10 fps cut from one capture:

| GIF | Size | Mbit/s | 3 Mbps | 5 Mbps | 10 Mbps | 25 Mbps |
| --- | --- | --- | --- | --- | --- | --- |
| 480 px, 10 s | 1.7 MB | 1.4 | | 0 (2.9 s) | 0 (1.5 s) | 0 (0.6 s) |
| 640 px, 10 s | 2.6 MB | 2.2 | | 1 (4.5 s) | 0 (2.3 s) | 0 (0.9 s) |
| 800 px, 5 s | 2.1 MB | 3.5 | 20 (6.0 s) | 0 (3.6 s) | 0 (1.8 s) | |
| 800 px, 10 s | 3.8 MB | 3.2 | 36 (10.6 s) | 0 (6.4 s) | 0 (3.3 s) | |
| 960 px, 10 s | 5.0 MB | 4.2 | 40 (14.0 s) | 9 (8.4 s) | 0 (4.3 s) | |
| 1280 px, 5 s | 4.3 MB | 7.3 | | 23 (7.4 s) | 3 (3.7 s) | 0 (1.5 s) |
| 1280 px, 10 s | 7.8 MB | 6.6 | | 40 (13.3 s) | 2 (6.7 s) | 0 (2.7 s) |

So the budget is 512 KB a second (4.2 Mbit/s): every GIF up to 4.6 Mbit/s played its first loop without a stall at
10 Mbps, and those of 5.7 Mbit/s and more stalled. On 5 Mbps the clean ones were 3.5 Mbit/s or less, so a GIF near
the budget stalls a few times on its first play there and loops smoothly after. The 8 s capture of the pull request
that added this was 7.9 MB at 1280 px from the old `--gif` (39 stalls at 5 Mbps, 4 at 10) and 3.9 MB at 800 px from
the new one (2 and 0).

- **Approach:** To measure how a GIF plays, read the changes of the picture from the compositor (CDP
  `Page.startScreencast`, a hash of each frame), throttle with `Network.emulateNetworkConditions` in full Chromium, and
  split a long sweep into runs under `gds quiet`'s 900 s (or pass `--timeout`). **Watch out for:** a canvas
  `drawImage` of the GIF saw no frame change at all, since drawing an animated image draws its first frame, and
  headless shell showed the same; a 68-run sweep was stopped at 900 s with its rows printed and its JSON never
  written. **Seen:** gdstudio #1153, 2026-11-11.
- **Approach:** For a loop of a gait, record whole cycles at 60 fps (the GIF is then an even 20 fps, and a cycle of
  0.667 s ends on a frame), compare the last frame with the first, and frame the scene in Godot as the GIF should
  show it. **Watch out for:** cropping the frames to win a wider GIF made every file larger at each width (2.2 MB
  became 2.8 MB at 640 px), because the encoder scales what is left to the same width and the moving bodies cover
  more of it: three bodies on a grid floor fit the budget at 480 px either way; and a jump clip that is in place
  reads as a body standing on one leg until the scene lifts it as the game would. **Seen:** gdstudio #1149,
  2026-11-11 (`tools/capture/mannequin_parade.gd` of 3D Third Person).
- **Approach:** Give every file on an `--attach` its own `![name](./<file>)` reference inside `## Screenshots`, a
  video as well as a picture, and write a video's reference in image form alone on its line. **Watch out for:** the
  guard refuses an attached file the section does not refer to, and a bare `./clip.mp4` line or a plain-text name is
  not a reference; written as `![clip](./clip.mp4)`, `--attach` turns it into the bare upload address that plays
  inline, so the old advice to write the bare address yourself misled. **Seen:** gdstudio #1154 (PR #1195), #1190
  (PR #1197) and #1203 (PR #1215), 2026-11-11 (the guard refused each, three times on #1215).

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
- **Approach:** For an MP4, put a still or a [sheet](#sheet) on the `After:` line and the clip as
  `![clip](./<name>.mp4)` alone on the line below it (a GIF is the image itself: [GIF or MP4](#gif-or-mp4)); run
  `gds pr check-body` with the same `--attach` files as `gh pr create`, from the same folder. **Watch out for:** the
  uploaded video becomes a bare address, which the screenshots rule does not count as the `After:` picture, and before
  the upload the rule refuses every local `./file` (only a `github.com/user-attachments/` address counts); a body with
  no image reference got past the guard (`--repo`, run from scratch) to CI. **Seen:** gdstudio #847, 2026-11-08;
  #937, #880 and #886, 2026-11-10 (the uploads moved onto `After:`; the guard now refuses that command, checked for
  #1003).
- **Approach:** Read the `## Screenshots` section of the body file back (`sed -n '/## Screenshots/,/## AI/p'`) after
  editing it and before the send. **Watch out for:** a scripted edit that was to add the image references matched
  nothing and said nothing, so the guard's "no reference" was true for three tries. **Seen:** gdstudio #1012,
  2026-11-10.
- **Approach:** Write the body file in an earlier command and name it by its absolute path, spelled out (not a shell
  variable), when the `gh` command starts with `cd <folder>`; run `gds pr check-body` by hand from that folder with
  `--repo <worktree>` and the same `--attach ./<file>` arguments as `gh pr create` (kit #1188). **Watch out for:** the
  hook reads `--body-file` as written, so a relative path is read from the folder after the `cd` ("does not exist
  yet") and a `$BODY` it cannot expand is not read; without `--repo`, the hand check run from a captures folder finds
  no checkout. **Seen:** gdstudio #1001, #1031, #1137 (PR #1170), #1203 (PR #1215) and #1035 (PR #1217),
  2026-11-11; the hand check refused `Before:`/`After:` before it took `--attach` (#1011 to #1090, PRs #1165 to
  #1175, 11-10 and 11-11).

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

Write it as `![listen](./<name>.mp4)` alone on its line under `## Screenshots`, with a blank line on each side, and
attach it from its folder: **GitHub draws a player only for the bare upload address on its own line**, and `gh pr
create|edit --attach` turns such a line into exactly that, so no second edit is needed (gdstudio #970 and #1190,
2026-11-11; before them this page said to replace a plain link by hand). Check it with `gh api
repos/<owner>/<repo>/pulls/<N> -H 'Accept: application/vnd.github.html+json' --jq .body_html`: the body holds a
`<video` tag.

- **Approach:** To let a listener hear a whole loop, or several versions of one bed, record them through the game's
  own player: a probe scene loads each version in turn into that player (its bus and volume, the default settings)
  for longer than one loop, Movie Maker writes the run's audio track, and a script cuts one section per version from
  it at the times the probe logged. **Watch out for:** an asset file played alone skips the bus, the volume and the
  loop point the player applies, so the clip compares files, not what the player hears; a run shorter than the loop
  never reaches its seam. **Seen:** gdstudio #1101, 2026-11-11 (the wind beds: a probe swapped the stream on the Wind
  player, Ambient bus, -20 dB, and the old bed and three candidates were cut from one Movie Maker track).
- **Approach:** For a sound that replaces another, attach a Before clip and an After clip, each referenced on its own
  line right under the `Before:` and `After:` lines of `## Screenshots`; a clip that alternates both can follow them.
  **Watch out for:** the PR-create hook refuses a body whose only clip is a combined before-and-after one: it needs a
  capture between `Before:` and `After:`. Cut both from the same tour in two games (old and new) so each event lands at
  the same second. **Seen:** gdstudio #1414, 2026-11-13 (single shots, a burst and held fire of the pistol and rifle).

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
phone's 844 by 390 and the web export), then `git worktree remove` it. An old sound or model alone is a Git LFS file:
take it with `git checkout <rev> -- <file>` into a scratch checkout, never `git show`, which prints the pointer
([Reverting and checking out](shell.md#checkout)).

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
  the same capture scripts with `--label=before`); gdstudio #1346, 2026-11-12 (main's hold files swapped into a kept
  game for the `Before:` tour, which broke its clips' import twice before it filmed).

## Tests {#tests}

`python/tests/test_quiet_run.py` runs the real pinned Godot and Movie Maker on Windows with a test window holding the
foreground. `python/tests/test_capture.py` replaces Godot and ffmpeg with fakes that record the command line and
write files, so the tests run anywhere. The real programs are exercised by hand on a game, as in the pull request
that added this.
