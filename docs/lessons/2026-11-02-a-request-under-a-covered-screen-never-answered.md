---
areas: [godot-ui, net]
---
# A request owned by a screen the router had covered never got its answer

2026-11-02

- **Saw:** in Deadnight's web build the new lobby screen's Join stayed on "Joining..." and the host's seats never
  updated, while every unit test passed (Deadnight #515).
- **Cause:** the lobby screen reused the API object of the screen beneath it, whose `HTTPRequest` nodes are children of
  that screen. The UI router disables processing on a covered screen, and a disabled parent does not process its
  `HTTPRequest`, so the request never completed. The unit tests used fake APIs that answer at once.
- **Fix (Deadnight #555):** a screen that keeps asking while it is on top owns its own request nodes, under itself; a
  goodbye sent while leaving goes through one under the root. A test checks whose child the API is; the browser probe
  proved the flow.
- **General:** in Godot, a node's network requests live and die with its parent's `process_mode`. A screen that calls
  the network is run once in the web build against the real backend before it counts as done, not only with a fake API.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md), Deadnight's own lesson
  (`docs/lessons/2026-11-02-a-request-owned-by-a-covered-screen-never-answered.md` in that repository).
