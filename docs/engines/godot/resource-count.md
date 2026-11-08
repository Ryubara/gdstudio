# Naming what the resource count is made of

Godot 4.7.2, Deadnight #1319. `Performance.OBJECT_RESOURCE_COUNT` is one number; a budget on it (a leak night's peak)
says nothing about what rose. Here is how to find out.

- **`OS.dump_resources_to_file` does not exist in GDScript in 4.7.2** (`Static function "dump_resources_to_file()" not
  found in base "GDScriptNativeClass"`; the script that names it fails to compile, so `core/main.gd` fails to load and
  the headless run hangs at the first frame instead of exiting). Do not reach for it.
- **Ask the cache about every file instead.** Walk `res://` with `DirAccess` (skip `.godot`, `addons`, `.import`, `.uid`)
  and write the paths for which `ResourceLoader.has_cached(path)` is true. Call it at fixed moments of a night (1 s,
  30 s,
  6, 12, 25, 30 minutes) from the autopilot's `_process` and diff the files. It covers the resources that have a path
  (scripts, sounds, textures, shaders, `.tres`); the monitor counts more (sub-resources of scenes and the packet sequence
  behind each Ogg stream), so also print the monitor next to the count of paths.
- **What it showed in Deadnight:** 734 paths and 1 601 monitor resources at 1 s, 1 131 and 2 592 at 30 minutes; 387 of the
  397 new paths were Ogg streams, each worth 2.0 to 2.8 monitor resources and about 0.2 MB of static memory. A rise that
  is the first hearing of a bounded set of sounds flattens; a 60 minute night showed 5.7, 1.1 and 0.0 resources a
  night minute in successive windows.
- **A count that moved at the first second is a feature, not a night:** compare the first row of the sampler between two
  commits (a 40 s headless run each) before reading the rise.
- Do this on a copy: the probe is a patch of the autopilot, never committed.
