# Screenshots of the Godot editor's inspector

A pull request that moves numbers into resources shows them in the inspector. The editor can be started on the private
desktop of [`gds godot`](no-focus.md) and told to photograph itself, so no person has to open it. Measured on Godot
4.7.2 with the Deadnight project, 2026-11-02.

## How

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

## What to know

- The dock is narrow and widening it from script did not work (`DockHSplitMain.split_offset` moved the viewport, not
  the inspector), so long values are cut (`defa...` for a resource path). Show the property names and numbers, and say
  where the file is in the pull request.
- **Running the editor rewrites some texture `.import` files** (Deadnight #441 tracks the cause and the fix).
  Until it lands, `git checkout -- 'game/assets/**/*.import'` before committing.
- Revert `project.godot` the same way after the run, and delete the plugin folder from the worktree.
