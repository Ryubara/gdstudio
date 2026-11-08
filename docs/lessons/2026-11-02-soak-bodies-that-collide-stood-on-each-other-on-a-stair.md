---
areas: [tests, gameplay]
---
# Two bodies in a map's move soak stood on each other on a stair for 36 s

2026-11-02

- **Saw:** a soak that walks player bodies from goal to goal along the navigation mesh (Deadnight #631) reported one
  leg given up and stuck episodes of 35 and 36 s, every one on a 2 m stair or in a 2 m doorway, two bodies at once,
  one 0.1 m above the other.
- **Cause:** the bodies collide with each other (layer 1 in mask 3) and steer straight along the mesh's corridor
  with no meeting rule, so two that meet in a narrow place push into each other or climb onto each other's capsule.
  A keep-right rule removed the head-on cases but not one following another up a stair.
- **Fix:** a soak that measures the map puts its bodies on a physics layer no mask has; how bodies pass each other is
  the bots' business and their own test. With that, 1242 of 1242 legs were walked with no second stuck.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md#measuring-a-map-on-its-mesh).
