# Lessons

Problems we hit and how we solved them, newest first. One entry each: what you saw, why it happened, the fix, and
where it is documented. Before solving something, search this page: it may have happened before.

## 2026-11-01: helmet and shoulder pads floating after applying scale

- **Saw:** the cleaned Soldier rendered with a bare head; his helmet and pads floated far above him.
- **Cause:** `transform_apply(scale=True)` on the armature does not keep meshes parented to a bone in place.
- **Fix:** record their world matrices at rest pose before the apply and set them back after.
- **Docs:** [Rig sharing (Blender)](blender/rig-sharing.md#what-broke).

## 2026-11-01: Blender exported every clip as the rest pose

- **Saw:** the cleaned zombie's glTF had 16 clips of 150 channels each, none of them moving; Godot imported 4 tracks.
- **Cause:** the clean-up set `armature.data.pose_position = "REST"` before the export; the exporter samples clips
  through the pose, so it sampled the rest pose.
- **Fix:** leave `pose_position` at `POSE` and zero the pose bones instead.
- **Docs:** [Rig sharing (Blender)](blender/rig-sharing.md#what-broke).

## 2026-11-01: a bone renamed Body_2 in Godot

- **Saw:** the Soldier's Run named a bone `Body_2`, and `find_bone("Body")` returned -1 on him.
- **Cause:** the Soldier's mesh is called `Body` too; Godot's glTF importer makes node names unique.
- **Fix:** rename meshes that share a bone's name (`Body_Mesh`) in the Blender clean-up.
- **Docs:** [Rig sharing (Blender)](blender/rig-sharing.md#the-recipe).

## 2026-11-01: shared clip floats or sinks a character

- **Saw:** the zombie's Walk put the Soldier's feet through the floor; the Soldier's Run lifted the zombie.
- **Cause:** bone position tracks are absolute and carry the source's rest offsets (`Body` 0.32 m apart).
- **Fix:** rebase position keys per character at play time (`value - source rest + own rest`) in
  `_post_process_key_value`; the library stays one resource.
- **Docs:** [Rig sharing (Godot)](godot/rig-sharing.md#what-breaks).

## 2026-11-01: a hidden slider grabber drew a magenta square

- **Saw:** a themed HSlider showed a magenta and black square where the grabber was meant to be invisible.
- **Cause:** the invisible grabber was a PlaceholderTexture2D, which draws its checker pattern in game.
- **Fix:** a transparent ImageTexture of the same size.
- **Docs:** [UI controls](godot/ui-controls.md).

## 2026-11-01: the screen stretched after a UI scale round trip

- **Saw:** after 125% and back to 100%, a column was 1425 px tall and off centre.
- **Cause:** autowrap Labels report a tall minimum size while a container sizes them; a CenterContainer kept it.
- **Fix:** no autowrap in rows (trim with an ellipsis), and a round-trip test.
- **Docs:** [UI controls](godot/ui-controls.md).

## 2026-11-01: GdUnit4 refuses to run headless

- **Saw:** "Headless mode is not supported", exit code 103.
- **Cause:** GdUnit4 blocks headless runs unless told otherwise.
- **Fix:** pass `--ignoreHeadlessMode`; the port 0 remote-debug error line is harmless. A failing suite stops at its
  first failure: fix and rerun to see the rest.
- **Docs:** each game's `AGENTS.md` (Build and test).

## 2026-11-01: a Movie Maker frame shows the state one step late

- **Saw:** the frame numbered N already showed a change made at step N.
- **Cause:** frame N is written after that step's script code ran.
- **Fix:** read frame N-1 to see the state before a change; frames are always at the project viewport size.
- **Docs:** [Capture](capture.md).

## 2026-11-01: Movie Maker ignores `--resolution`

- **Saw:** `--write-movie` with `--resolution 1280x720` (or 960x540) still wrote 1920x1080 frames.
- **Cause:** the movie is the project's viewport size; the window resolution request does not change it (Godot 4.7.2).
- **Fix:** scale afterwards, which `gds capture sheet` and `gds capture clip` do.
- **Docs:** [Capture](capture.md).

## 2026-11-01: hooks judged text as commands

- **Saw:** the hooks refused harmless commands: a Python heredoc line starting `blender = ...`, and a `grep -E "a|godot"`.
- **Cause:** the guard split shell lines on `|` inside quotes and read heredoc bodies as commands.
- **Fix:** split only outside quotes; drop heredoc and here-string bodies before judging.
- **Docs:** Hooks (`docs/hooks.md`).

## 2026-11-01: new agent definitions invisible to a running session

- **Saw:** `.claude/agents/*.md` written mid-session; starting one failed with "agent type not found".
- **Cause:** Claude Code loads project agents when a session starts.
- **Fix:** restart with `claude --resume <session id>` (the conversation is kept).
- **Docs:** Agents (`docs/agents.md`).

## 2026-11-01: Blender's download site refuses scripts

- **Saw:** downloads from download.blender.org returned a browser-check page, not the file.
- **Cause:** the site sits behind a bot check.
- **Fix:** the official mirrors (same checksum file), pinned in `tools.toml`.
- **Docs:** [Workspace](workspace.md#tools).

## 2026-11-01: Godot rewrites project.godot

- **Saw:** a hand-written comment in `project.godot` vanished after the first import.
- **Cause:** Godot owns that file and rewrites it in its own format.
- **Fix:** never hand-comment it; local-only settings go in an untracked `override.cfg`.
- **Docs:** [Workspace](workspace.md).
