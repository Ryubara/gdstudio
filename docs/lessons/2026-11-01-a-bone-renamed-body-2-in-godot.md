# A bone renamed Body_2 in Godot

2026-11-01

- **Saw:** the Soldier's Run named a bone `Body_2`, and `find_bone("Body")` returned -1 on him.
- **Cause:** the Soldier's mesh is called `Body` too; Godot's glTF importer makes node names unique.
- **Fix:** rename meshes that share a bone's name (`Body_Mesh`) in the Blender clean-up.
- **Docs:** [Rig sharing (Blender)](../blender/rig-sharing.md#the-recipe).
