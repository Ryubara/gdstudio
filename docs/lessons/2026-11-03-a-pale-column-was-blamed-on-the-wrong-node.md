---
areas: [tests, godot, process]
---
# A pale column was blamed on the wrong node

2026-11-03

- **Saw:** an issue (Deadnight #854) said the pendant lamps' haze cones (`UpperB/Lamp7`, `Lamp8`, `UpperA/Lamp6`) read as
  hard-edged pale columns from the shoulder camera at 2 to 3 m. Captures of those cones from 1 to 8 m (cone drawn and
  hidden, the game frozen) showed warm, soft beams.
- **Cause:** the issue named the nodes by where they stood in the picture. The pale blue shell was the prize crane's
  beam (a 36 m cylinder on its own inline shader: additive, no edge fade, no near fade), which stands beside those
  lamps. Hiding every node on a shader one at a time, and comparing the pictures, named it in one run; a fix aimed at
  the named cones would have left the picture unchanged.
- **Fix:** before changing an effect named in a report, hide the named node in the report's own view and check that
  the thing in the picture goes (a pixel difference, or `visible = false` and a look). Hide with `layers = 0` when the
  owner sets `visible` itself every frame (the crane did, so a hidden beam came back between two grabs). Then fix what
  the picture shows (here the crane's beam, plus a smaller change to the cones).
- **Docs:** [Measuring an effect on the screen](../engines/godot/measuring-effects-on-screen.md#a-soft-rim-and-which-node-it-is).
