---
areas: [tools, process]
---

# New GDScript files failed gdlint's line limit, and `--attach` needed the image's own folder

- **Symptom:** the first `pre-commit` run on Deadnight #787 failed `gdlint` on 33 lines over 100 characters (doc
  comments written as long single lines, files written with CRLF by the editor tool), and the first two `gh pr create`
  calls were refused: the body named `./image.png` while `--attach` held an absolute path, and the check
  `Before:`/`After:` capture was missing until the images were really uploaded.
- **Cause:** comments were written at the length the prose came out, not wrapped at 100; the hook compares the body's
  reference with the `--attach` path as written, so two spellings of one file count as two files.
- **Fix:** wrap comments at 98 columns when writing (a small script re-wrapped the ones flagged), then run
  `uvx pre-commit run --all-files` before the commit, not after. For the screenshots: `cd` into the folder that holds
  the images, write `![alt](./name.png)` in the body, and run `gh pr create -R <owner/repo> --head <branch> --attach
  ./name.png` there, after the branch is pushed; read the body back with `gh pr view N --json body`.
- **Documented:** [Surface materials](../godot/surface-materials.md#re-skinning-a-model-that-is-already-painted) for the
  skin work itself; this lesson holds the two process traps.
