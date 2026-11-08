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

## A headless layout test measures real text once the screen has its theme {#layout-needs-theme}

<!-- new section: the section it replaces said a headless run measures text as nothing; the cause was a screen built
under a bare Control, which has no theme -->

A form row that was 97 units high in a window was 52 in a GdUnit run, and a title label 23 units against 83. The dummy
renderer was not the cause: the tests built the screen under a bare `Control`, and the theme (type sizes, fonts, the
scroll areas' room, the bars) comes from the router's stage. Without it a label has the engine's default 16 px font.

- **Approach:** Open the screen through the router (`UIRouter.reset`), or under a `Control` whose `theme` is
  `UIThemeBuilder.build(UITokens.active())`, and treat the headless GdUnit run as a real layout test; keep a windowed
  capture for the eyes and the web build for the page, not for the numbers. **Watch out for:** three lessons and a page
  said "a headless run measures text as nothing", a Play screen test carried a 100-unit "headless text allowance", and a
  fit test passed on layouts a phone cut off; with the theme a headless run printed the same sizes and rectangles as a
  window, to the unit (the Deadnight fit sweep, both ways at 844 x 390: the same problem lines). **Seen:** Deadnight
  #980, 2026-11-04; Deadnight #1161, 2026-11-05 (fix: `UiFitRun` opens screens through the router; a pixel test that
  built a lobby without it measured a fault the game never had).
- **Approach:** Tell a headless run what a window of this size is when the game decides a mode from the window (the
  compact menu from `MenuScale.is_phone`), and test the rules (the compact flag, the hints hidden, the tap-target
  minimum) headless. **Watch out for:** a 64 pixel headless window never made `MenuShell` a phone's, so a "phone" case
  ran the desktop layout in CI; see [Windowed GdUnit on a Linux runner](windowed-gdunit-on-linux.md#headless-differences).
  **Seen:** Deadnight, 2026-11-05 (fix: `MenuShell.phone_mode` from `MenuScale.is_phone`).

## MultiMesh copies have no transform headless

The dummy renderer keeps no instance data: `MultiMesh.get_instance_transform(i)` returns the zero transform for every
copy. A test that checks where copies stand reads the `buffer` property instead (12 floats a copy, each basis row
followed by its origin's coordinate), which keeps the scene's values.
