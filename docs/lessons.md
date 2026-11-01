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
