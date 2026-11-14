# Building and reviewing a template

<!-- new section: new-game.md reached 47 KB with the proof entries of gdstudio #1237 still to come; what a template's
scripts, scenes and tests must do is a subject of its own, apart from making and proving a game -->

What every GDStudio template is built and reviewed against, so that people and agents can tune and read it. Making a
game from a template and proving it are on [New game](new-game.md).

## What every template is built and reviewed against {#template-checklist}

<!-- new section: the page said what a template holds; nothing said what its scripts, scenes and tests must do so that
     people and agents can tune and read them (gdstudio #831) -->

A template is a starting point that people open in the editor and agents read as text, so its parts follow one
contract. A new template is built to it and every change to a template is reviewed against it; the review lists a line
per component (passes, or what was fixed). The twelve items, each with its reason:

Items 1 to 9 are for the **inspector** (what a person sees and changes), 10 to 12 for **agents** (what makes the
template cheap to change):

1. **Every value a developer would tune is an `@export`**, in a named group (`@export_group`, `@export_subgroup`),
   with a range and a unit suffix where it has one, a `##` tooltip and a default that plays well; internals are not
   exported.
   *Why:* the inspector is where a game gets tuned, and a number in a script constant cannot be found there.
2. **A change takes effect at once**, in the running game and the remote inspector: a value is read where it is used, or
   applied through a setter, and never copied once in `_enter_tree()` or `_ready()`. *Why:* tuning while the game runs
   is the fast loop, and a copy made at load silently ignores the edit.
3. **A value with a visible effect in the editor is a `@tool` script** (a camera's distance and field of view, a
   platform's path, a door's size, a block's size and colour, a trigger's shape, a spawn point's facing): the viewport
   shows the change. Gameplay, input and signal wiring stay off in the editor (`Engine.is_editor_hint()`). *Why:* a
   person tuning a map should see the map change, not run it to find out.
4. **Nothing generated at edit time is saved into a scene**: a `.tscn` holds what a person or agent put there and
   nothing more. *Why:* generated data is noise in a diff and goes stale; the one exception is a lightmap's UV2 mesh,
   which only the editor can make (the `ProtoBlock`).
5. **No node shows `<empty>` for something it needs, and none carries a configuration warning when its scene opens**; a
   node that needs another says so through `_get_configuration_warnings()`. *Why:* a warning on opening is the first
   thing a new person sees, and it teaches them to ignore warnings.
6. **Shared tuning lives in a `.tres` resource** (`player_tuning.tres`) and an edit to the resource applies live (its
   `changed` signal). *Why:* a copy of the file is a second feel, and the resource is one place to diff.
7. **Node references are exported (`@export var x: Node3D`) or unique names (`%Name`)**, never long hard-coded paths,
   and **a part a person is expected to replace (a model, a weapon) is never referenced by its own node name or unique
   name**: it sits under a stable slot node, and everything else references the slot (an export) and asks it for the
   part. *Why:* a component then works when it is moved or reused, and a replaced part is deleted, so the editor empties
   every path that pointed at it, and a dropped-in scene takes its file's name and is not unique
   (the model swap in #844; [Replacing the model](third-person-template.md#replacing-the-model)). A unique name on a
   node between the owner and the part also turns the `AnimationTree`'s root into a `%Name/...` path that the editor's
   helper player cannot resolve.
8. **Each component works alone** when dropped into an empty scene and set up from the inspector, and talks to the others
   through signals. An area that senses bodies says which ones by its mask (the named layers of
   [Physics layers](physics-layers.md#template-layers)) and, behind it, which ones count (characters, props, any) in an
   export, and by default ignores the level and itself. *Why:* a template that only works whole cannot be taken apart,
   and in a level where every body shares layer 1 an area that counts any body is triggered by the floor beside it
   (the gate door in #845 and the pressure pad in #848).
9. **Whatever a person sees or places is real nodes in its scene**, laid out in the editor: UI (the touch stick, look
   zone and buttons as `Control` nodes with anchors), the HUD, markers, spawn points and map pieces. Scripts hold
   behaviour; they do not build or `_draw` visible parts at run time. *One exception:* a shape that is only a function
   of exports and that no node draws (the HUD's `Crosshair`: a filled circle and a thin ring, `ui/hud/crosshair.gd`)
   may be a `Control` that `_draw`s itself, as long as the node is in the scene, placed by anchors, shows in the editor
   (`@tool`) and its look is exports; the alternative is a texture file for a shape that must scale to any size.
   *Why:* a developer opening the scene sees what is there and moves or restyles it there, and an agent reads the
   `.tscn` text for placements as easily as code.

10. **Generated structures stay in code only where a scene could not hold them well** (the animation tree's graph, built
    in code with `@tool` so the editor shows it). Typed GDScript, short scripts, a `##` doc comment on every class,
    export and signal. *Why:* code is what agents change most reliably, and a graph of many nodes is not worth placing
    by hand.
11. **Scene and resource files stay small and diff cleanly**: no editor-only state, no generated data, stable node names.
    *Why:* a review reads the diff.
12. **Every component has tests, in its home**: a component any game of any template can use unchanged is a script of
    the synced `addons/gds_game/`, proved alone in `godot/tests/gds_game/`; the template keeps its scene, its tuning
    and its in-the-map suites ([Sync](../../studio/sync.md#gds-game)). Each export's default is pinned (`ExportPins`,
    in the synced `addons/gds_game/testing/`) and a test changes each live export at run time and checks its effect.
    *Why:* a pinned default is a decision someone made, a test of the change is the only proof that item 2 holds, and a
    universal part copied into a template is never fixed in the games made from it.

A test of item 5 calls the script's own `_get_configuration_warnings()`: the engine's `get_configuration_warnings()` is
not callable from GDScript ("Nonexistent function"), and the script's list is the one a missing component adds to.

How it is proved: `gds check scripts` and an editor open of a fresh game (the probe of
[editor screenshots](editor-screenshots.md) prints each node's configuration warnings and what is empty, and saves each
scene to see that nothing generated is written), the suites with a pin and a live test per export, and the editor's own
remote-inspector message ([Changing values like the remote inspector](editor-screenshots.md#remote-inspector)).

- **Approach:** Build a new template to the twelve items and review a changed one against them, a line per component in
  the pull request (what was checked, what passed, what was fixed). **Watch out for:** 3D Third Person (#821) passed its
  tests and shipped with exports copied once at load (the camera, the capsule, the graphics profile, a door's sensor),
  map components that built their meshes and shapes in code so nothing showed in their scenes, and no pin of any
  default; the maintainer found two of these by using it. **Seen:** gdstudio #831, 2026-11-08.
- **Approach:** Make every visible part a node of its scene, laid out with anchors, and let a `@tool` script only read
  their places and apply the inspector's numbers to them. Mark the mesh, shape or material a script sizes
  `resource_local_to_scene = true` and look parts up by unique name (`%Panel`), which works from the instance's root.
  **Watch out for:** the touch controls were one empty `CanvasLayer` that drew the stick and buttons in `_draw`, and the
  door, platform, prop, pickup, zone and spawn point made children with `add_child` that the Scene dock never lists.
  A `@tool` script that sets a property of an instance's child does not dirty the scene that instances it (a level
  held no override after the editor saved it). **Seen:** gdstudio #831, 2026-11-08
  ([touch controls](ui-controls.md#touch-controls), [map components](third-person-template.md#map-components)).
- **Approach:** When a `@tool` script has to write into nodes that the scene file itself owns (not an instance's
  children), take the written values off in `NOTIFICATION_EDITOR_PRE_SAVE` and put them back in `..._POST_SAVE`, as the
  animation tree and the camera wrapper do. **Watch out for:** opening and saving `main.tscn` with the camera wrapper as
  a `@tool` script wrote spring length, margin, damping, offset and a computed transform onto the Phantom Camera, and a
  `@tool` `Player` wrote `floor_snap_length`; read the saved file once after making a part `@tool`. **Seen:** gdstudio
  #831, 2026-11-08 ([camera](camera.md#phantom-camera)).
- **Approach:** Pin the inspector contract of every node and resource with one fixture (`ExportPins.differences` and
  `wrong_values` against a dictionary of defaults) so a new export fails the suite until its default is pinned, and keep
  one suite per component under gdlint's twenty public methods. **Watch out for:** two suites went past twenty `test_`
  functions and gdlint (`max-public-methods`) failed them, and a float export compared with `is_equal` failed on a
  property that holds a float32 (use `is_equal_approx`). **Seen:** gdstudio #831, 2026-11-08; #846, 2026-11-09 (the
  ragdoll's 19 tests, two suites); #875, #879 and #881, 2026-11-10 (suites split per part); #981, 2026-11-10, #1094
  and #1111, 2026-11-11 (exports unpinned until the full run: run the pin suite); #965, 2026-11-10 (a class split
  too); #1085; #1337 (2 exports unpinned, a 21st method on `weapon.gd`).
- **Approach:** Before you add a method to a game class, count its public functions (`grep -c "^func [a-z]"`). When
  it already has twenty, add a property with a getter and setter (like `Weapon.bursting`, which ends the burst when set
  false) or a private helper. Put a plain `var` (a computed alias) after the last `@export`, never in an export
  group. **Watch out for:** `Weapon` had exactly twenty public functions, so `bursting()` and `end_burst()` failed
  gdlint's `max-public-methods`. A non-exported `automatic` alias placed in `WeaponDef`'s Fire group made every export
  after it a `class-definitions-order` error (75 at once). **Seen:** gdstudio #1352, 2026-11-12 (both caught by the
  commit hook); gdstudio #1420, 2026-11-13 (`Character.goal_direction()` failed it; now
  `CharacterGoal.direction()`, off `Character`).

- **Approach:** When a change adds a setting to an extending template's own `project.godot`, run
  `python/tests/test_new_game.py` before the push: it compares that file with the base's and lists each allowed
  difference. **Watch out for:** 3D Third Person's Jolt setting (#846) failed the kit's `test` job on all three systems
  with the template's own suite green, because the comparison only knew the input map and the orientation. **Seen:**
  gdstudio #846, 2026-11-10 (fix: the test strips and checks the Jolt line).
