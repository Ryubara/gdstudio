# Screenshots of the Godot editor's inspector

A pull request that moves numbers into resources shows them in the inspector. The editor can be started on the private
desktop of [`gds godot`](no-focus.md) and told to photograph itself, so no person has to open it. Measured on Godot
4.7.2 with the Deadnight project, 2026-11-02.

## How {#how}

A throwaway editor plugin (never committed: it lives in the scratch folder and is copied into the project for the run)
does the work in `_enter_tree`:

1. wait about 200 frames for the editor's first scan to end (earlier, `open_scene_from_path` is lost and the editor
   shows the project's main scene);
2. `EditorInterface.open_scene_from_path(scene)`, select a node and `edit_node(node)`, or `edit_resource(load(path))`
   for a `.tres`;
3. unfold every group: `inspector.find_children("*", "EditorInspectorSection", true, false)` and call `unfold()` on
   each (the sections are folded by default, and `unfold` is callable from script);
4. wait 60 frames, then `EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(file)`
   and `get_tree().quit()`.

The plugin is enabled by adding its `plugin.cfg` to `[editor_plugins] enabled` in `project.godot` for the run, and
the target comes from environment variables. Run it with `gds godot -- --editor --path game`. The whole editor window
is saved (3840 x 2126 on this machine); crop the inspector dock, about 430 px wide at the right edge.

For a bottom panel (the AnimationTree graph): select the node with `EditorInterface.get_selection().add_node(node)` and
`edit_node(node)`, make the panel taller with `base.find_child("DockVSplitCenter", true, false).set("split_offset",
-800)` (a `VSplitContainer` of the center column; the split of the panel's own graph is another one), press the
"Open Editor" button of a state machine node (`emit_signal("pressed")`) for its states, and wait about 60 frames before
saving the viewport's image. The same plugin can call `EditorInterface.save_scene()` and read the `.tscn` afterwards
to prove nothing generated was saved (gdstudio #830, Godot 4.7.2).

## What to know {#what-to-know}

- The dock is narrow and widening it from script did not work (`DockHSplitMain.split_offset` moved the viewport, not
  the inspector), so long values are cut (`defa...` for a resource path). Show the property names and numbers, and say
  where the file is in the pull request.
- **Running the editor rewrites some texture `.import` files** (Deadnight #441 tracks the cause and the fix).
  Until it lands, `git checkout -- 'game/assets/**/*.import'` before committing.
- Revert `project.godot` the same way after the run, and delete the plugin folder from the worktree.
- The same probe checks a template's scenes as a person meets them (kit docs: [the template
  checklist](new-game.md#template-checklist)): open each scene, call `_get_configuration_warnings()` on every node that
  has it (`Node.get_configuration_warnings()` is not in the script API in 4.7; the engine's own warnings, such as a
  collision body with no shape, are checked by hand), look for a mesh, shape, tree root or animation player left
  empty, call `EditorInterface.save_scene()` and compare the file with what it was (uids and `unique_id`s are added the
  first time; anything else is generated state). Set the editor's 3D camera for a shot with
  `EditorInterface.get_editor_viewport_3d(0).get_camera_3d().look_at_from_position(...)` after selecting the node, and
  again after about 20 frames. Gdstudio #831, Godot 4.7.2.

## Changing values like the remote inspector {#remote-inspector}

<!-- new section: nothing said how to check that a setter really takes the edit that the Remote tab sends -->

- **Approach:** Prove that a value changed in the Remote tab takes effect by sending the tab's own message from an editor
  plugin: an `EditorDebuggerPlugin` (`add_debugger_plugin`) that captures a prefix of its own, a throwaway autoload that
  registers `EngineDebugger.register_message_capture`, sends the live objects' `get_instance_id()` and answers "report"
  with the values it reads, and `EditorInterface.play_main_scene()`. The plugin sends
  `session.send_message("scene:set_object_property", [id, "property", value])`. **Watch out for:** the editor consumes
  `scene:` messages, so the plugin needs a prefix of its own for the ids, and a helper named `_set` clashes with
  `Object._set`. With setters, the field of view (62 to 95), spring length, run speed, capsule radius, platform speed
  and a door's panel size all changed in the running game. **Seen:** gdstudio #831, 2026-11-08.
