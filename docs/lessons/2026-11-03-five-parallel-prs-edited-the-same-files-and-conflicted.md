---
areas: [process, ci]
---
# Five parallel pull requests edited the same files and conflicted

2026-11-03

- **Saw:** five Deadnight small-map pull requests were open together: stairs #655, cover #656, lamps #658, greybox #660
  and roof #661. When #658 merged, #655, #656, #660 and #661 all turned DIRTY. The maintainer asked why, since pull
  requests are meant to merge oldest first.
- **Cause:** three things.
    - **The same files:** all five added rows to the same two docs (`docs/research/maps/small-map-art.md` and
      `docs/design/style.md`). Three rewrote the same test (`test_smallmap_kit_walls.gd`) with the same fix; two edited
      `test_lot_light_cap.gd`, and two edited `assets/smallmap/LICENSE.md`. Merge order decides which pull request has to
      settle a clash, not whether there is one.
    - **Order not kept:** auto-merge lands whichever pull request goes green first. #658, opened at 01:44, merged before
      #655 (01:17) and #656 (01:21), which were still red.
    - **One fix made three times:** the coordinator knew the cover agent had the walls-test fix and that the other two
      needed it. It let all three agents write it instead of landing it once and having the others merge `main`.
- **Fix:**
    - **A fix several pull requests need** lands once, in the first of them or on its own. The others merge `main` after
      it and do not copy it.
    - **A shared docs table** (parts built, the style table) has one row per pull request, added at its own place, and a
      pull request does not reword rows it does not own. A merge then settles the table without a hand edit.
    - **When several issues will add to the same files:** the coordinator names those files in each agent's prompt and
      tells it to merge `main` right before it pushes.
    - **Merge order:** stays first-green until the maintainer chooses otherwise (a merge queue is their call). Either
      way, the conflicts come from the files, not the order.
- **Docs:** [Starting work: everything that can run, runs](../starting-work.md#parallel).
