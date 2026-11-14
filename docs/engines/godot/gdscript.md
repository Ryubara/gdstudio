# GDScript and project-file traps

<!-- new section: no Godot page held how GDScript and the project's own files fail without a message; the entries
     were scattered over one-problem files -->

The mistakes that GDScript and Godot's own files let through without a warning: a name that means something else, a
lambda that works on a copy, a file Godot rewrites. Each entry is something an agent already lost time to; the
checks are in the entry. Testing traps are in [Running GdUnit4](running-gdunit.md), probes in
[Probes and tools in headless Godot](headless-probes.md).

## Names and types {#names-and-types}

- **Approach:** Name a static builder for what it builds (`reload_weapon`), never after an Object, Script or Node
  method (`new`, `free`, `reload`, `get_script`) or a virtual (`_set`, `_get`, `_get_property_list`,
  `_validate_property`, `_notification`, `_init`, `_ready`); a grep for those names in pre-commit can catch it.
  **Watch out for:** a script class is itself a `GDScript` object, so `GDScript.reload()` (it returns an `Error`) wins
  over `static func reload`, and a helper named `_set` overrides the virtual with the wrong signature and breaks
  compilation. **Seen:** Deadnight, 2026-11-01 (fix: `reload_weapon`); Deadnight #462, 2026-11-01 (a helper named
  `_set`); gdstudio #1073, 2026-11-11 (a capture tour's `_set(move)` helper: the tour did not load and the first
  capture was 180 black frames; renamed `_walk`).

- **Approach:** Name a local or parameter so it matches no member of its node class (`gravity_scale`, not
  `scale`; `earlier`, not `before`, in a GdUnit suite), no global function (`hash`, `snapped`) and no function of its
  class, and set `shadowed_variable`, `shadowed_variable_base_class` and `shadowed_global_identifier` to `2` in
  `[debug]` of `project.godot`, as templates do. **Watch out for:** the editor warned on
  opening 3D Third Person ("local variable "scale" is shadowing..."), which headless runs never show; as errors,
  `gds check scripts` fails the script. **Seen:** gdstudio #836, 2026-11-08 (a lambda's `_body`); #857, #877
  (`name`); #902 (`hash`, `snapped`, `world_hash` beside its function); #903 (`url`, `url()`); #901 (`before`);
  #966 (`mesh`); #970 (`rows`); #1186 (`show`: a web export failed); #1386 (`left` beside `NetEvent.left()`);
  #1420 (`newest`, `goal`); #1436 (`pole()`'s).

- **Approach:** Prune a typed array in place (`remove_at` from the end) or with `typed.assign(typed.filter(...))`, never
  `typed = typed.filter(...)`. **Watch out for:** `Array.filter()` returns an untyped `Array`, and assigning it to an
  `Array[Projectile]` passes the parser and fails at run time ("Trying to assign an array of type Array to a variable
  of type Array[Projectile]"), only on the path that runs it: the weapon's pool hit it once its live list was full.
  **Seen:** gdstudio #887, 2026-11-10 (`Weapon._take_projectile`, found by `test_weapon_ray.gd`; in the same task a
  tool's `root` and `sign` met the shadowing rule above); gdstudio #1198, 2026-11-11 (a ternary's `else []` is
  untyped too: every hitscan shot and blow failed in `_scan`; declare `[]`, then assign in an `if`).

- **Approach:** Before naming a global class, grep `class_name <Name>` in the branch and on `origin/main`, and prefer
  a name specific to the subject; when errors show up in many unrelated scripts at once after an import or a merge,
  look for a duplicate global class first. **Watch out for:** Godot keeps one global class per name and silently picks
  the other script: after a merge `PlayerState.new()` failed with "Too few arguments" and every test that loaded the
  player hung in the debugger; a clash can also stay silent until the web export ([Lamps in a
  game](compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light)). **Seen:** Deadnight, 2026-11-01
  (fix: one was renamed `PlayerMotionState`).

- **Approach:** Write the type (`var cooked: float = ...`) when a value comes out of an untyped Dictionary or Array,
  or keep the record in a small typed class. **Watch out for:** an element of an untyped `Dictionary` is a Variant, so
  `var cooked := now - _cooks[id]["started"]` has nothing to infer (`Cannot infer the type of "cooked" variable`); in
  a project that raises warnings, `:=` from a Dictionary value is an error that also hangs a headless `-s` run. The
  same goes for a property of an addon's component reached through a static lookup (`Health.of(body).value`): the
  template's parse check refused the whole suite (`The variable type is being inferred from a Variant value`).
  **Seen:** Deadnight, 2026-11-01 (fix: explicit types); gdstudio #1288, 2026-11-12 (`test_rifle_melee.gd`).

- **Approach:** Test a node with `node == null` or `is_instance_valid(node)`, never against a bool, and keep a test
  that runs the real game path. **Watch out for:** GDScript parses a comparison of an Object with a bool and fails
  only when the line runs with a live node: the unit tests of the soldier voice never reached that branch and the
  night test stopped on it. **Seen:** Deadnight #442, 2026-11-01 (fix: `is_instance_valid`; the night test is the
  check).

- **Approach:** Give an `@export_enum` a name for "none" (`"Stay"`, `"None"`) and test for that string; load every new
  script once (`gds check scripts`) before reading anything else a run prints. **Watch out for:** `@export_enum("",
  "TopLeft", ...)` is a parse error ("Argument 1 of annotation @export_enum is empty") that was reported only as
  "Could not resolve class" on the scripts that extend the failing one. **Seen:** gdstudio #880, 2026-11-10 (fix: a
  `Stay` entry).

- **Approach:** Fill a typed array in steps (`var paths: Array[String] = [a, b]`, then `if cond: paths = [c]`) and read
  the first line of a headless run's log for `SCRIPT ERROR`. **Watch out for:** `var paths: Array[String] = [a] if
  cond else [b, c]` parses, then fails when the line runs (`Trying to assign an array of type "Array" to a variable of
  type "Array[String]"`) because the ternary makes an untyped array; the process went on running, so a measurement
  matrix recorded cells from a node that never set up. **Seen:** gdstudio #883, 2026-11-10 (fix: the if); gdstudio
  #1297, 2026-11-11 (`EffectEmitter`'s `probes if warm_up_every_probe else []` stopped the warm-up in two suite cases).
- **Approach:** Pass an exported node to a typed parameter of a helper only through `is_instance_valid(node)`
  (`model if is_instance_valid(model) else null`), and test the body with its model freed. **Watch out for:** a node
  freed while the export still names it is not `null`, so `model != null` passed and the call failed on the type
  (`argument 1 (previously freed) is not a subclass`) every frame: 120 errors in one suite of the full template run,
  while every prone suite passed. **Seen:** gdstudio #1026, 2026-11-11 (`ProneAnimation.stow_view`; the suite
  `test_player_step.gd` frees the model).
- **Approach:** Set a typed-array export from code with a typed array (`var list: Array[Node3D] = [node]`, then
  `spawner.set(&"markers", list)`), or assign the property by name, which converts. **Watch out for:**
  `Object.set("markers", [node])` with a plain `Array` leaves an `Array[Node3D]` export as it was, with no error, so a
  spawner in a test spawned at its own place instead of the markers. **Seen:** kit #969, 2026-11-11
  (`test_ai_spawner.gd`).

## Script errors at run time {#runtime-errors}

<!-- new section: the page held names, lambdas and files; nothing said what a call returns when the function it calls
     hits a script error, which a watchdog depends on -->

- **Approach:** To catch a script error in code another script supplies (a task's `update()`), make the value `0` of
  the function's return enum mean "invalid" (`enum Status { INVALID, RUNNING, SUCCEEDED, FAILED }`), read the result
  into a `Variant` and treat anything that is not a known status (0 from a typed function, `null` from an untyped one)
  as the error. GDScript has no `try`: the caller carries on after the error. **Watch out for:** in Godot 4.7.2 a
  function declared `-> int` that hits `Cannot call method 'x' on a null value` returns `0` to its caller, not `null`,
  and the caller's next line runs; assigning that result to a typed enum variable hides the difference. A `-> bool`
  returns `false`, so a check that may error should mean "not valid" by `false`. **Seen:** gdstudio #965, 2026-11-10
  (a headless spike, then `AiTask._judge`).

- **Approach:** When two `RefCounted` objects need each other (a task and the runner that owns it), keep the back
  reference as a `WeakRef` (`weakref(runner)`, read with `get_ref()`) or pass the owner as an argument. **Watch out
  for:** a strong reference both ways is a cycle that reference counting never frees, which shows as objects leaked
  at exit, a line CI refuses. **Seen:** gdstudio #965, 2026-11-10 (`AiTask.runner()`).

- **Approach:** Pass a node that may have been freed (one that lived under a skeleton a model swap deleted) as an
  untyped `Variant`, or check `is_instance_valid()` before the call, and test the path that frees it. **Watch out
  for:** a typed parameter refuses a freed instance at the call (`The Object-derived class of argument 1 (previously
  freed) is not a subclass of the expected argument class`), before the function's own `is_instance_valid()` check
  runs, and only one test of the whole run met it. A deferred call (`Class.f.call_deferred(node)`) meets it on the
  idle frame as `Cannot convert argument 1 from Object to Object`. **Seen:** gdstudio #1126, 2026-11-11
  (`RagdollDrawing.place`); PR #1397's merge, 2026-11-13 (`keep_last`, 174 errors a run; coordinator's mistake);
  gdstudio #1478, 2026-11-13 (`AimLayer`'s rest check: 122 errors, in the full run only).

## Lambdas {#lambdas}

- **Approach:** To collect results from a lambda, append to an Array or Dictionary, or set a member of the object that
  owns it (a method plus member variables; a probe object holding the counts); never count in a captured local or fill
  a captured packed array. **Watch out for:** a lambda captures a local `int`, `bool`, `float` or packed array by
  value when it is made, so `kills += 1` or `vertices.append(...)` works on a copy: a test read 0 events and a
  navigation mesh built in a lambda had no vertices (every path `[]`); assigning a whole Array or Dictionary to the
  outer variable inside the lambda is the same trap. **Seen:** Deadnight #226, 2026-11-02 (bot counts, a
  mesh); gdstudio #836, 2026-11-08 (`hits += 1` read 0); gdstudio #1251, 2026-11-11 (`met = {...}` left the
  dict empty); gdstudio #1206, 2026-11-11 (a `maxf` into a captured float read 0 mm); #1158, 2026-11-12 (the same).

## What a line costs in the web build {#web-cost}

<!-- new section: per-frame scripts were cut for the web build by guessing what costs (engine calls, global poses), and
     nothing said what a GDScript line, a call or an engine call costs there (gdstudio #1347) -->

A per-frame script (a skeleton modifier, a hold, an AI step) runs 40 times a frame in a crowd, so the web build's
GDScript cost is what a web bench reads. Measured in headless Chrome on the pinned Godot (20,000 calls each,
`tools/bench/hold_cost.gd`'s spans in a kept game): a call to a function of another script or of the same one
0.06 microseconds or more (with its arguments and return), a member of a built-in read in a condition (`at.z > 0.0 and
at.z < d and absf(at.x) < w`) 0.25 for the whole line, an engine call such as `get_bone_pose` 0.03, a transform
product 0.04, a packed array read 0.02. So a function written out at its one caller costs less than the call, and a
loop over points pays for every component it reads. The engine does a loop in one call when it is handed a packed
array: `Transform3D * PackedVector3Array` turns a whole group of points, and `AABB.has_point` tests one without
reading its components in script.

- **Approach:** Before cutting a per-frame script for the web, count its script calls a frame (its own helpers, a
  static helper of another class, a getter of another object) and write the small ones out at their caller, keep
  what is written to another object (a modifier's `influence`, a hand's weights) and write it only when it changes,
  and hand point loops to the engine in packed arrays. Then measure in Chrome, in turns with `main`. **Watch out
  for:** a cache of bone poses behind a helper class (a call for each pose and each parent, recursive) made the rifle
  hold 97 microseconds a character a frame against 71; asking the engine for half as many bone poses moved nothing;
  writing the helpers out at their callers took it from 57 to 41. **Seen:** gdstudio #1347, 2026-11-12.
- **Approach:** Before culling points by boxes, count how many the boxes let through against how many count, and
  meet the boxes in the frame where the tested shape is a box (turn the small boxes into it, not it into theirs).
  **Watch out for:** a long, thin sweep turned into each bone's rest space became a box over most of the torso, so the
  rifle's low ready went through 143 to 170 points a frame of which 23 to 32 counted, and cost 20 to 36 microseconds
  more than the ready. **Seen:** gdstudio #1433, 2026-11-13 (`TorsoSkin._push_along()`).

## Project and scene files {#project-and-scene-files}

- **Approach:** In a scene file written by hand or script, put `node_paths=PackedStringArray("target")` on the
  `[node]` line of every node with a node-typed export, and `unbinds=N` on a `[connection]` whose method takes fewer
  arguments than the signal; instance it and print the reference. **Watch out for:** without `node_paths`,
  `target = NodePath("../Other")` loads as `null` with no error (the editor writes the key itself), and a connection
  without `unbinds` fails only when the signal fires (the key is `unbinds`). **Seen:** gdstudio #788, 2026-11-08 (the
  graphics profile found no node and did nothing; fixed, with a test that applies it).

- **Approach:** In a `.tscn` written by hand or by a script, put each node's `script = ExtResource(...)` line before
  the script's own exports (`style`, `title`, `key`). **Watch out for:** properties above the `script` line are
  dropped without a word: every label of a settings screen loaded at the body size and every row had no title, and no
  check noticed; only a capture and a probe that printed the property did. **Seen:** gdstudio #881, 2026-11-10 (the 3D
  Third Person menus).
- **Approach:** Treat `project.godot` as Godot's file: change it by hand only for a real setting, keep local-only
  settings for a game run in an untracked `override.cfg` (the editor never reads it: an editor plugin goes in
  `project.godot`, [Integrations](../../studio/workspace.md#integrations)), run `git checkout game/project.godot` after
  each import or run, and stage files by path (never `git add -A` in a worktree where Godot has just run). **Watch out
  for:** Godot rewrites the file in its own format and section order whenever it saves project state, so a hand-written
  comment vanished and two engineers touching the input map conflicted on a reorder nobody meant. **Seen:** Deadnight,
  2026-11-01 (fix: `override.cfg` and a checkout after every run).

- **Approach:** Make input bindings in the editor, or print `InputMap.action_get_events(action)` from a probe, and add
  a test that sends the real key. **Watch out for:** Godot accepts any integer as a `physical_keycode`: codes typed
  from memory (4194326 for PageUp, which is 4194323) loaded without a warning and never fired on the keyboard while
  the gamepad button worked. **Seen:** Deadnight, 2026-11-01 (fix: codes read from the engine; a test sends the key).

- **Approach:** Write a `Transform3D` into a `.tscn` row by row: the rotation about Y by an angle is `(c, 0, s, 0, 1,
  0, -s, 0, c)` and the node's +Z is its third column `(s, 0, c)`; turn by `atan2(dx, dz)` for a wanted +Z of `(dx, 0,
  dz)` and test the facing (a point's depth from the node) instead of trusting the matrix. **Watch out for:** the text
  form lists the basis by rows, so a generator that read the third triple as +Z turned a node the opposite way and
  "how far into the field is this point" read inside out. **Seen:** Deadnight, 2026-11-01 (fix: `atan2` and a facing
  test that spawn markers stand outside their gate).

- **Approach:** After saving a tuning resource from a script, write every value back explicitly (or change the
  script's defaults), so the `.tres` shows each number a designer tunes. **Watch out for:** `ResourceSaver` omits
  every property equal to the script's default, so a saved tuning file showed almost no values and hid the tuning.
  **Seen:** Deadnight, 2026-11-01 (fix: a short script that writes every value).

- **Approach:** In a script that edits GDScript, open files with `encoding="utf-8", newline=""` to read and write,
  keep units in tooltips ASCII (`deg`, `m/s^2`), run a headless import after the edit (it names the broken file) and
  check line endings with `file <path>`. **Watch out for:** `open(path, "w")` on Windows writes the locale's code page
  (a `²` and a `°` became single Windows-1252 bytes) and CRLF line ends; Godot refuses a script with invalid UTF-8,
  and every class that uses it then fails to compile. **Seen:** Deadnight #415, 2026-11-02 (fix: utf-8 and
  `newline=""`, ASCII units, an import after each scripted edit).

- **Approach:** Keep a resource a probe loads and edits in an array or member for the probe's life: a change meant for
  later `load()` calls lives only as long as something holds the resource. **Watch out for:** with no reference left
  the resource is freed and leaves the loader's cache, so the next `load()` of the path read the file again,
  unchanged, and the probe printed the numbers it printed without the edit. **Seen:** Deadnight, 2026-11-04 (fix: a
  `_kept` array in the arm-measuring probe).

## gdformat {#gdformat}

- **Approach:** Keep assert chains short (one `assert_*` call with one matcher per statement, the message in a
  variable), start a commented block after a one-line entry of a `const` dictionary, and re-run the tests after every
  `pre-commit` run that reformats a test file. **Watch out for:** gdformat wraps
  `assert_bool(x).override_failure_message("...").is_true()` in parentheses with the dot detached from its name, which
  is not valid GDScript ("Unindent doesn't match", and GdUnit hung); it rewrote a multi-line lambda inside a call into
  a form Godot refuses, and put a comment between `"key":` and its wrapped `{...}` value. **Seen:** Deadnight,
  2026-11-01 (fix: short asserts, a named helper in place of the lambda); Deadnight, 2026-11-03 (a merge that kept two
  batches' entries); gdstudio #1001, 2026-11-10 (a lambda in a `connect` call: named methods).
