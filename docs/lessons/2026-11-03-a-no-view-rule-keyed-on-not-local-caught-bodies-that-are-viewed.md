---
areas: [gameplay, camera, tests]
---
# A "no one looks through this body" rule keyed on "not the local player" caught bodies that are viewed

2026-11-03

- **Saw:** Deadnight #938. The first cut rested the camera rig of every body made with `local_input = false`. Five
  tests of the downed camera failed (the rig no longer followed the body: `track()` was skipped), and the same run
  logged `Signal 'tree_entered' is already connected` because a test calls `setup()` twice on the same rig.
- **Cause:** "not local" is not "nobody looks": the manual mode's player (tests drive it by hand and read its rig),
  the autopilot under the shoulder camera and a remote human's body on a drawn host are all `local_input = false`.
  `release_view()` could use that proxy because it only stops a body taking the current camera; switching the work
  off is a different claim.
- **Fix:** say it where the body is made: the server passes `viewless` for a bot (`bot` flag of its join) and for a
  body that draws nothing, and `Night` marks the autopilot's body viewless only under the spectator camera
  (`Player.make_viewless()`, `Player.look_through()` to undo it). Connections made in `setup()` check
  `is_connected` first. Run the whole `tests/player`, `tests/night` and `tests/bots` folders before pushing a change
  to a node everyone shares, not only the new suite.
- **Docs:** [Third-person camera](../engines/godot/camera.md#a-rig-no-one-looks-through).
