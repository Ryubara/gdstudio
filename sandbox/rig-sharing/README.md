# Rig-sharing spike

One AnimationLibrary on every Quaternius character. Findings: `docs/blender/rig-sharing.md` and
`docs/godot/rig-sharing.md`.

```sh
blender -b --factory-startup -P blender/inspect_rig.py -- <model.glb>            # what a file holds
blender -b --factory-startup -P blender/clean_export.py -- <in.glb> godot/models/<name>.glb
godot --headless --path godot --import
godot --path godot -- --out <workspace>/scratch/gdstudio/<branch>                # prints RIG: lines, writes sheet.png
```
