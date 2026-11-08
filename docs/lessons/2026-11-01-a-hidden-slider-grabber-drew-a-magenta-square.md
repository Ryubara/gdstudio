---
areas: [process, blender]
---
# A hidden slider grabber drew a magenta square

2026-11-01

- **Saw:** a themed HSlider showed a magenta and black square where the grabber was meant to be invisible.
- **Cause:** the invisible grabber was a PlaceholderTexture2D, which draws its checker pattern in game.
- **Fix:** a transparent ImageTexture of the same size.
- **Docs:** [UI controls](../engines/godot/ui-controls.md).
