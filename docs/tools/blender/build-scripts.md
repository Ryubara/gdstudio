# Build scripts

<!-- new section: no page held how Blender build scripts are run from an agent's shell and how the files they made are
rebuilt and imported again; key-art.md#files covers render runs only -->

How GDStudio runs the Blender scripts that build its assets (`gds tool path blender`, headless `-b -P script.py --
<args>`) from an agent's shell on Windows, and how a file they made is rebuilt and imported again without changing what
the task did not mean to change. A game keeps its scripts in its own `tools/blender/`.

## Running a build {#running}

Pass Blender every path absolute: a script resolves a relative path itself, not the shell that started it, so a render
given `--out out` wrote somewhere else (make it absolute in the shell, `"$(pwd)/out"`, before the call).

- **Approach:** From Git Bash, pass Blender and Godot every path as a Windows path with forward slashes
  (`C:/Repositories/...`), inside a `Title=path` argument too. **Watch out for:** Git Bash converts a `/c/...` path
  only where it starts an argument; inside `Title=/c/...` it converted for one model and not the next (`Ray=` against
  `"Ray gun="`), and Blender failed with `Please select a file`. **Seen:** Deadnight, 2026-11-01; Deadnight #797,
  2026-11-03 (fix: `render_sheet.py --model` is given `C:/` paths).
- **Approach:** Run a build with `--python-exit-code 1` before `-P`, and prove a rebuild by the line the script
  prints when it has written its file, never by the exit code alone. **Watch out for:** Blender exits 0 when the
  script raises: after a refactor cut an attribute, three builds "passed" with exit 0 and the committed files'
  hashes unchanged, because nothing had been written. **Seen:** gdstudio #1294, 2026-11-11 (`build_vault.py`; the
  `AttributeError` was in the log).
- **Approach:** Edit a script that a running batch or loop reads only between runs, or run a copy and edit the
  original; land a change that has to be whole (a use and its import) in one write, and read every log of a background
  loop for `Traceback`, not only its exit code. **Watch out for:** bash reads a script as it runs, so an edit shifted
  the bytes under a render batch (`line 44: ue: command not found`), and one of seven builds in a loop started between
  two edits and died on a name used before its import was written. **Seen:** Deadnight #438, 2026-11-01; Deadnight
  #939, 2026-11-04 (fix: the batch was run again and the failed file rebuilt).

- **Approach:** Write a script, or a patch to one, to a file with the write tool and run the file; keep shell
  heredocs for a few lines with no apostrophe, and open text files with `newline=""` when a Python one-liner rewrites
  them. **Watch out for:** a quoted heredoc holding an apostrophe (a docstring's "the clip's") failed in the agent's
  Bash tool with `unexpected EOF while looking for matching`, twice, and Python's text mode on Windows rewrote a
  script's line ends as CRLF. **Seen:** gdstudio #1009, 2026-11-10; gdstudio #1150, 2026-11-11 (a page section
  written through a heredoc); gdstudio #1149, 2026-11-11 (a heredoc that wrote `styles.py` held "an artist's"; and a
  patch that matched whole lines stopped matching once `gdformat` had rewritten the file with CRLF: read the file
  with its line ends folded to LF before matching); gdstudio #1151 and #1154, 2026-11-11 (the same).
- **Approach:** Run every build stage with `--python-exit-code 1` and stop on a non-zero exit. **Watch out for:**
  without it Blender exits 0 when the script raises, so a runner that reads the exit code printed `exit 0` above a
  traceback and the next stage opened the last good file. **Seen:** gdstudio #1151, 2026-11-11 (fix: the flag in
  `sandbox/realistic-character/build.py`).
- **Approach:** Keep the probes and one-off scripts you write in your own scratch folder
  (`<workspace>/scratch/<repo>/<branch>/probes/`) and run them from there. **Watch out for:** Python puts the
  script's folder first on its import path, so a probe written to the machine's shared temp folder imported
  another agent's `inspect.py` in place of the standard library's, and numpy failed to load with
  `No module named 'bpy'`; a probe that imported a template's script left a `__pycache__` folder beside it, which
  the layout test refuses (run probes with `python -B`). **Seen:** gdstudio #1150, 2026-11-11 (fix: the probes
  moved to the scratch folder; the cache folder was deleted before the push); gdstudio #1151, 2026-11-11 (the same
  numpy failure from a script in the shared temp folder).
- **Approach:** Keep a Python package inside a game free of `__init__.py` (a folder of modules imports as a
  namespace package) and start Blender with `PYTHONDONTWRITEBYTECODE=1` in its environment when its script imports
  a module of the game. **Watch out for:** the template's layout check refuses a file named `__init__.py` (not
  snake case), and `-B` covers only the Python you start: Blender importing `limb_overlap.py` left a `__pycache__`
  folder in the game, which the commit would have taken. **Seen:** gdstudio #1154, 2026-11-11 (fix: the toolkit's
  rate moved from `gdsanim/__init__.py` into `maths.py`; `build_own.py` passes the variable).
- **Approach:** Take a build's output only after reading its exit code or its last line (`EXPORTED`), or delete the
  old output before the build. **Watch out for:** a build that fails its checks exits before it exports and leaves the
  last good file in place, so the next step copied and rendered the old clips as if they were the new ones.
  A patch chained before a solve in one background command fails the same way: its assert stopped the patch, the
  solve ran the old code for 13 minutes and gave the old pose to the last digit. Patch in the foreground, read its
  result, then start the run. **Seen:** gdstudio #1009, 2026-11-10 (caught by the file's time; no stale file was
  committed); gdstudio #1084, 2026-11-11 (fix: the patch run alone).
- **Approach:** Lint and format a template's Python (its build scripts and benches under `templates/<t>/game/`)
  by hand before the push, with the settings a game made from it uses: `uvx ruff check --no-cache --config
  templates/repo/ruff.toml <files>` and the same with `ruff format` (120 columns). **Watch out for:** the kit's ruff
  pre-commit hooks cover only `python/` and `.claude/hooks/`, so a template script is never linted in the kit, and
  ruff run on it without `--config` finds no settings above it and wraps at 88. **Seen:** gdstudio #1150 (PR #1165),
  2026-11-11; gdstudio #1084, 2026-11-11 (a bare `ruff format` rewrapped the hold's solver; formatted again at 120);
  gdstudio #1293, 2026-11-11 (a bare `ruff format` rewrapped the 120-column `limb_overlap.py`, 150 lines of noise in
  the commit, put back by hand; the prone build scripts are still wrapped at 88).

## Rebuilding a committed file {#rebuilding}

A rebuild changes only what the task changes. Blender's glTF export does not keep the triangle order from run to run,
so compare a rebuilt model by its nodes, vertex buffers and triangle set ([Weapons](weapons.md#building-by-script)) and
its clips by their animation accessors, read in Python, never by bytes; commit only the files the change is for.

- **Approach:** Give every build that exports clips a frozen list of the clips its file carries and assert it; before
  rebuilding a file a clip module feeds, compare its clip list with the committed one, and before tuning a clip, find
  every built file that carries its name and confirm which copy plays by swapping one file. **Watch out for:** a build
  that exports every action the clip module makes picks up clips added since (55 for 39, then 67 for 35), and the game
  keeps the first copy a library gets, so a clip rebuilt in its own file changed nothing while the parts file's copy
  played. **Seen:** Deadnight #678, 2026-11-02; Deadnight #939, 2026-11-04; Deadnight #1282, 2026-11-05 (fix:
  `FILE_CLIPS` and `--clips main`, and both files rebuilt from one source).
- **Approach:** Import only a model its script wrote whole: after a conflict on a Git LFS model, fix the script and
  build until it exits clean, take an old copy with `git checkout <rev> -- <file>` or `git show <rev>:<file> | git
  lfs smudge > <out>` (`git show` alone prints the pointer),
  and read `git diff` of `*.import` before committing. **Watch out for:** pointer text (`version ...`) imported as a
  model fails and writes `valid=false` with no `dest_files` into the `.import`, which Godot keeps trusting after the
  model is good: restore the `.import`, delete `.godot/imported/<file>.glb-*` and import again. **Seen:** Deadnight,
  2026-11-04; Deadnight #1282, 2026-11-05 (fix: the import files restored and the models imported again); gdstudio
  #1016, 2026-11-11 (an old glb read back with `git show`).
- **Approach:** When a change touches a measure that builds solve against (`limb_overlap.py`), rebuild every file
  whose build imports it in the same pull request and read the numbers again; a branch that merges such a change
  rebuilds before it lands. **Watch out for:** the fixed clips' test holds `fixed.glb` to the hash its build wrote,
  so it stays green while the measure under it changes: once the measure turned the `form` bodies' twist bones, a
  rebuild keyed the dash's leg swivel at 34 degrees for 41 and the combo's at 28 for 22, and the library's own
  numbers moved 0.1 mm. **Seen:** gdstudio #1325 after #1323, 2026-11-12 (fix: rebuilt after merging `main`; the
  build does not yet record the measure's hash).

## Checks in the build {#checks}

A clip build also checks that limbs do not pass through each other: `limb_overlap.py`
(`templates/3d-third-person/game/assets/animation/`, from kit #1016 and #1020) measures, on every frame and on each
mannequin's skinned mesh, how deep any body part is inside another, and a build calls its `measure()` on the baked
actions before it exports (its header has the command line and the limit). The command line measures a clip file
on the same frames as the build, at the rate it reads from the file's key times
([how it samples](animation.md#solved-clips)); after a change to the script, run `test_limb_overlap.py` beside it
with the pinned Blender (it keys a clip, measures it both ways at 30 and 24 frames a second and exits 1 on a
difference).

A clip that passes an obstacle is also read between its keys, as a game draws it
([A clip that touches the world](animation.md#contacts)).

- **Approach:** Make a build script fail on its triangle budget and on its lowest vertex before it exports, read the
  count on the first build, and chamfer only what is big and seen: parts under about 0.2 m on an asset seen from afar
  are plain boxes. Lift a part pitched about its centre by half its length times the sine of the pitch plus half its
  thickness times the cosine. **Watch out for:** a chamfered box costs 44 triangles against 12 and a chamfered
  12-sided cylinder 92 against 44, so a carbine came out at 1,576 of 1,500 and a helicopter's rails cost more than its
  hull (1,768), and a pitched skid went 11 mm under the ground. **Seen:** Deadnight #795, 2026-11-03; Deadnight #1057,
  2026-11-04 (fix: plain small parts, 1,236 and 1,288 triangles, and the skid lifted by that sum).
- **Approach:** Make the build check what its kind of asset can get wrong, not only a budget: a re-texture asserts the
  triangle count and bounds did not change, a clip asserts the lowest vertex of the deformed mesh on every frame and
  that a foot is on the floor, a rig asserts every vertex is weighted. **Watch out for:** a build that checks only its
  triangle budget exports a barrel whose geometry moved or a walk whose foot goes through the floor, and the first to
  see it is a reviewer or the game. **Seen:** gdstudio #774, 2026-11-07 (the baseline runs of the `uv-palette` and
  `clip-walk` evals added these checks to their own builds).
- **Approach:** Call `bpy.context.view_layer.update()` before a check reads `matrix_world` of objects the script has
  just parented or moved, and compare the build's printed size with the exported file read back. **Watch out for:** a
  child's `matrix_world` keeps its old value until the update, so the pistol's check measured its slide and magazine
  where they were made and printed a size 1 cm short (0.186 m against the file's 0.196 m), and a budget or lowest-vertex
  check would read the same stale place. **Seen:** gdstudio #834, 2026-11-08 (fix: the update in `build_pistol.py`'s
  check).
- **Approach:** Run a new measuring script first on a clip whose answer is known (a loop the file closes exactly
  reads a 0 mm seam; a standing clip reads no ground speed) and print one joint on the first, second and last
  frame beside the script's number. **Watch out for:** numpy puts the axes of two index lists first when a slice
  sits between them (`world[:, joints, :3, 3]` is joint by frame, not frame by joint), so the first audit read a
  906 mm seam on every closed loop, the pelvis's height. **Seen:** gdstudio #1150, 2026-11-11 (fix:
  `world[:, joints][:, :, :3, 3]` in `audit_clips.py`).
- **Approach:** Compare two poses in a check by matrix distance (the largest difference of the two matrices' entries,
  or of their axes) with a limit in millimetres, not by the angle from `acos` of a dot product. **Watch out for:**
  `mathutils` is single precision, so an arc cosine of a dot product near 1 reads 0.04 to 0.09 degrees between two
  poses that are the same, and a pose-gap check failed on noise. **Seen:** gdstudio #1081 (PR #1103), 2026-11-11.
