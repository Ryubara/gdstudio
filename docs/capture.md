# Capture: proof you can look at

Every visual change needs proof attached to its pull request. `gds capture` does the three steps with the pinned
tools, so nobody writes Movie Maker command lines by hand: record frames, tile them into a contact sheet that can be
read in one look, and encode a clip.

```text
gds capture frames --project <game>/game --scene res://x.tscn --seconds 6 --fps 10 --name hud
gds capture sheet  <folder> --every 5 --columns 5
gds capture clip   <folder> [--gif]
```

Run them with `uv run --project <workspace>/repos/gdstudio/python gds capture ...`.

## frames

Runs the pinned Godot with [Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)
in a real window (not `--headless`: Movie Maker needs a renderer). The window opens on a private Windows desktop, so
it never takes the keyboard or cursor from the person at the machine ([why](godot/no-focus.md)). The scene runs on a
fixed timestep, so a seeded scene gives the same frames every time. To record with your own command line (several
scenes, extra arguments) use `gds godot -- --path <game> --write-movie ...`, never the Godot program itself.

| Option | Meaning |
| --- | --- |
| `--project` | The game's project folder, the one holding `project.godot` (required). |
| `--scene` | A scene to run instead of the main scene, e.g. `res://ui/hud.tscn`. |
| `--seconds`, `--fps` | Length and rate; the capture is `ceil(seconds * fps)` frames. Defaults 5 s at 10 fps. |
| `--name` | The folder name (default `capture`). |

The frames go to `<workspace>/scratch/<repo>/<branch>/<name>/` as `<name>00000000.png`, `<name>00000001.png`, ...
next to Movie Maker's `<name>.wav` and a `capture.json` holding the frame rate. The repository and branch come from
the project folder with the rule the hooks use: the repository is the git top level's name (for a worktree
`worktrees/<repo>/<branch>`, the parent folder's name) and a `/` in the branch becomes `-`. Frames from an earlier
run of the same name are replaced. A project that was never imported is imported first.

Frames are the project's viewport size (Godot's `--resolution` has no effect on Movie Maker); the sheet and the clip
scale them down. Godot's `ERROR` lines are printed and flagged: a capture with errors is not proof.

## sheet

Tiles every `--every`-th frame (default 1) in `--columns` columns (default 4) into `sheet.png` in the folder. Tiles
are 480 px wide with the frame number in the corner. Pick `--every` so that the sheet has about 8 to 24 tiles, then
read it with the Read tool and fix what looks wrong.

## clip

Encodes the folder's frames into `<name>.mp4` (H.264, `yuv420p`, no audio) or, with `--gif`, `<name>.gif` with a
128-colour palette at up to 12 fps. The clip is cut at 30 s and has to stay under 9 MB (GitHub takes 10 MB for most
attachments): it is encoded at 1280 px wide and, while too big, again at 960, 720 and 480 px, then the command fails.

## Attaching

```text
cd <folder> && gh pr create -R <owner>/<repo> --body-file <folder>/body.md --attach ./sheet.png --attach ./<name>.mp4
```

`--attach` (on `gh pr create` and `gh pr edit`) appends the images at the end of the body, outside `## Screenshots`,
and the body check refuses `Before:`/`After:` until they sit there. Write `![before](./before.png)` on the `Before:`
line and `![after](./sheet.png)` on the `After:` line so `--attach` replaces each reference with the upload in place.
**`gh` swaps a reference only when it names the same file as an `--attach` path**, and it reads a relative path from
the folder it runs in, not from the body file. Captures live in `<workspace>/scratch/...` and the command usually runs
in the worktree: `--attach <scratch>/before.png` with a `./before.png` reference is two different files, so the
reference stays local and the upload is appended after `## AI use` (Deadnight #611, #637 and more reached CI that way).
So `cd` into the folder that holds the images first and attach `./<file>` (any form of the path works there:
`./sheet.png`, `sheet.png`, the absolute path), or write the reference with the same absolute path as `--attach`. Then
read the body back and check the image lines sit under the bullets
([lesson](lessons/2026-11-01-gh-attach-puts-images-outside-screenshots.md),
[lesson](lessons/2026-11-03-attach-matched-the-file-name-and-gh-matches-the-file.md)).

The hooks enforce it ([Hooks](hooks.md)): `gh pr create|edit --attach` is refused before it runs unless the body file
named with `--body-file` (or a literal `--body`) already refers to every attached file inside `## Screenshots`, with an
image between `Before:` and `After:` (or `Before: none (reason)`) and one below `After:`. The refusal names the missing
files and the line to write. Write the body file first (with the Write tool, not in the same command), and an existing
body is copied from `gh pr view N --json body -q .body`. A reference whose path is not the attached file's, from the
folder the command runs in, is refused with both places named ([Hooks](hooks.md#attach-paths)). Say "attached" in a
report only after reading the body back.

## Before captures

A `Before:` capture needs the code from before the change, and the task's worktree has no copy of it after the first
edit (`git stash` is refused by the hooks). Take them from `main` checked out beside the change: `git worktree add
--detach <workspace>/scratch/<repo>/<task>/baseline origin/main`, `godot --headless --path game --import` once, and run
the same tours and probes there with `--label=before` for every size the pull request shows (the desktop window, the
phone's 844 by 390 and the web export), then `git worktree remove` it
([lesson](lessons/2026-11-03-a-before-capture-needs-main-checked-out-beside-the-change.md)).

## Tests

`python/tests/test_quiet_run.py` runs the real pinned Godot and Movie Maker on Windows with a test window holding the
foreground. `python/tests/test_capture.py` replaces Godot and ffmpeg with fakes that record the command line and
write files, so the tests run anywhere. The real programs are exercised by hand on a game, as in the pull request
that added this.
