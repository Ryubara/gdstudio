# The headless renderer draws with a dummy: do not make meshes from two threads

A `--headless` run (every GdUnit run in CI) has no GPU: the rendering server is the **dummy renderer**
(`RendererDummy`), and its mesh storage is not safe to fill from two threads at once. A game that loads a model with
`ResourceLoader.load_threaded_request` while the main thread builds meshes of its own (a lot's CSG, a staged row of
zombie views) can race it: the engine prints `Initializing already initialized RID` and `Parameter "m" is null` in
`mesh_storage.h`, and a mesh RID is left behind, which the exit check reports as
`ERROR: 1 RID allocations of type 'N13RendererDummy9DummyMeshE' were leaked at exit` after every test has passed.
It shows once in a few dozen runs, only on a loaded machine, and no `Leaked instance` line goes with it.

- **Load on the main thread when the display is headless** (`DisplayServer.get_name() == "headless"`). Nothing is gained
  from a thread there: no frame is drawn. Deadnight's `NightWarmup.loads_in_threads()` is the switch.
- The same holds for any `WorkerThreadPool` job that makes a `Mesh` or a `MeshInstance3D`.
- To see it, search the whole run's log for `Initializing already initialized RID` (the first sign) before looking at
  what leaked: the line before it names the call that raced.

## Headless text has no height, so a layout test there cannot prove a fit

The dummy text server measures a label as almost nothing: a form row that is 97 units high in the window was 52 in a
GdUnit run, and a Play screen that overflowed a 540 unit phone canvas passed a "fits the canvas" test. Test the rules
(the compact flag, the hints hidden, the tap-target minimum) headless, and prove the fit with a windowed capture that
prints every control outside the window (`tests/captures/solo_settings_tour.gd` in Deadnight) and in the web build
([lesson](../../lessons/2026-11-02-a-finished-screen-was-never-routed-from-the-menu.md)).

## MultiMesh copies have no transform headless

The dummy renderer keeps no instance data: `MultiMesh.get_instance_transform(i)` returns the zero transform for every
copy. A test that checks where copies stand reads the `buffer` property instead (12 floats a copy, each basis row
followed by its origin's coordinate), which keeps the scene's values.
