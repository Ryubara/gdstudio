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
  what leaked: the line before it names the call that raced
  ([lesson](../lessons/2026-11-02-a-threaded-load-in-the-dummy-renderer-left-a-mesh-leaked-at-exit.md)).
