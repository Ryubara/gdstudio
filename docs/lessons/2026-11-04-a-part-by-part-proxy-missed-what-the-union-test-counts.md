---
areas: [blender, tests]
---
# A part-by-part proxy passed a hand the game's test counted inside

2026-11-04

- **Saw:** a Blender check of the arms said the downed Soldier's hand on the belly was clear, and Godot's sampler said
  83 mm inside; a probe of each part alone in Godot found nothing over 20 mm (Deadnight #939).
- **Cause:** the game's test casts its six rays against every other part at once. Each part's surface is open where
  its bones' skin meets the next part's, so a hand in a fold (belly, thighs) meets a back face of one part or another
  down every axis without being deep in any one. My proxy built one surface per part.
- **Fix:** the proxy builds one surface of every part the arm must stay out of, as the game does; it then followed
  Godot (63-86 mm against 78-83) and the pose search ran in Blender. Copy the game check's exact rule before tuning
  against a proxy, and confirm its numbers on one known fault before trusting it.
- **Docs:** [Clips that keep the arms out](../tools/blender/variants.md#clips-that-keep-the-arms-out).
