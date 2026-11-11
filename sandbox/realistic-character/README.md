# Realistic character experiment

The build of gdstudio #1151: how far a realistic game character gets in the pinned Blender alone. The findings, the
numbers and the gap list are on `docs/tools/blender/realistic-characters.md`; this folder is the record of how it was
built and is not a starting point for a game asset as it is.

- `build.py` runs the eight stages in `blender/` (sculpt, skin bake, eyes, hair cards, clothes and gear, their
  textures, the rig, the export), each a headless Blender run that reads the file the stage before it saved.
- `blender/s90_render.py` renders any stage in Cycles or EEVEE under three lighting setups.
- `godot/` is the test project: it builds the materials, plays a library clip, captures and measures frame cost.
  Its `asset/` folder is filled by stage 8 and ignored by git.

**No asset is committed.** The build needs two files it does not ship: Blender Studio's Human Base Meshes bundle
(CC0, from blender.org's demo files) and the template's `mannequin_female.glb` (already in this repository). Whether a
character derived from the bundle is ever committed, with its licence entry, is the maintainer's decision.
