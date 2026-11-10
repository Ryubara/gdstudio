# The rules this repository reviews against

An excerpt of the repository's `AGENTS.md` and the kit's docs, as a reviewer reads them.

- **Typed GDScript.** Every variable, parameter and return is typed. Public members (signals, exports, functions)
  carry a `##` doc comment.
- **Numbers live in a tuning resource** (a `Resource` with exports), never as a constant in a script, so a designer
  changes them in the inspector. A constant that is a physical fact of the engine (a unit conversion) may stay.
- **Time.** Anything that moves or counts down uses the physics or process `delta`, never a fixed frame time and never
  the wall clock. Tests count physics frames (`await get_tree().physics_frame`), never `create_timer`: a timer makes the
  suite as slow as the clock and the result depends on the machine's load. A cosmetic effect on one client may use a
  timer.
- **Per-frame functions** (`_process`, `_physics_process`) do not allocate, build strings or look nodes up: they update
  on a signal, or hold what they need in a field.
- **Absent nodes.** A node looked up with `get_node_or_null` may be absent: check it before use, or use `@onready` with
  `$` when the scene guarantees it.
- **Network authority.** The server is the only authority: a client sends an intent (where it aims), never a value
  (how much damage, how many rounds). A server function is never reachable by a peer who does not own what it
  changes. Cosmetics (a flash, a sound, a particle) are never replicated or sent by a reliable message: each client
  makes them from the event it already got.
- **Calling across folders.** `gameplay/` and `core/` do not import each other's classes; a call to a node of another
  folder goes through a group or a method check (`has_method`), and the method must exist on the node the call is
  made on.
- **Tests.** Every new script has a test that fails when its behaviour breaks. A test that cannot fail (an assertion
  that is always true) is a finding. A bug or a limit is pinned by a test of the failing case.
- **Docs move with the code.** A change to a tuning field, a signal or a component updates the page that lists it in
  the same pull request.
- **The description is true.** What it says about screenshots, tests and docs matches the diff: a visible change
  needs `Before:` and `After:` captures; `none` is only for a change nobody sees.
