---
areas: [blender]
---
# Modular roof bays showed the sky through their joints

2026-11-03

- **Saw:** from inside Deadnight's blockout room, thin bright lines ran up the roof between every two 2 m bays.
- **Cause:** each bay's boards ended exactly at the bay's edge, so two bays met edge to edge and the depth buffer left
  a hairline where the sky showed.
- **Fix:** boards at a bay's end run 20 mm into the next bay (the same colour, so the overlap never shows).
- **Docs:** [Modular kits: roof and outside](../blender/modular-kits.md#roof-and-outside).
