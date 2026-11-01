# Removing the kit Soldier's helmet removed his eyes

2026-11-01

- **Saw:** a Soldier with no helmet had a blank face.
- **Cause:** the Toon Shooter Soldier keeps its eyes and brows in the bone-parented helmet mesh (`Head`), not in `Body`.
- **Fix:** split the black islands in front of the face out of the helmet and join them to every head part.
- **Docs:** [Character variants from one rig](../blender/variants.md#modular-parts).
