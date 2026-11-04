---
areas: [gameplay, ci]
---
# A corner held a window, a breach and a perk alcove, and no reach fitted

2026-11-04

- **Saw:** Deadnight's main went red after the second map's layout rework (#964): the use-zone spacing sweep (#958)
  found five new overlapping pairs, and of the 26 pairs listed for the rework eight were left. One of them could not
  be moved apart at all: the side room's south-west window stood 2.8 m from the breach round the corner and 3.2 m from
  the Swift Rescue alcove on its own wall, with the side stair's foot in the next corner (#994).
- **Cause:** two. The rework placed openings by a count rule (one window a wall) and perks by another (each in its own
  alcove), and nothing summed the reaches before the walls were built: a press reaches 2.5 m from a window or a door
  and 1.5 m from a shop spot, and two zones keep 0.5 m between, so two windows need 5.5 m between their middles, a
  window and a spot 4.5 m, two spots 3.5 m. A 6 m room end cannot hold a window on two walls, a stair door and an
  alcove. And the rework's checks ran on a branch made before the sweep landed; it was squash-merged 25 minutes after
  the sweep, so the sweep first met the new layout on main.
- **Fix:** the side room keeps one entry at each end (the breach at the west, a window at the north-east); the corner
  window went, and with it a second opening in one corner, which was one direction for the dead, not two. Four other
  things moved in the generator and the test's list of pending pairs is gone, so any pair fails it. Dropping the window
  was a level design call; the map's design page says why.
- **Check for next time:** on the plan, before building, write each interactable's middle and the distances above
  between every pair on a floor (the map review's "Use zones never overlap"); a corner with two openings and anything
  else used with the button is a fault on paper. A pull request that moves walls or interactables merges main
  (`gds merge-main`) and runs the map suites again after any test that judges layout lands, before auto-merge takes it.
