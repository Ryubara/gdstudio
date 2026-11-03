---
areas: [godot, tests]
---
# A draw-call count read three frames after a camera move was noise

2026-11-03

- **Saw:** comparing the lot's draw calls before and after new walls (Deadnight #849), the same fixed camera spot gave
  1117 in one run and 37 in the next, and 947 against 238 at the start apron; a "before" and "after" table built from
  them said some spots got 1000 calls cheaper.
- **Cause:** the probe moved the camera, waited three `frame_post_draw` and read `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`
  once. The count is the last drawn frame's, and a frame or two after a big move still carries the old view (the count
  was settling over about ten frames: samples at one spot ran 66, 83, 96, 102, 111).
- **Fix:** wait 12 frames after the move, take five samples and keep the median, print the spots whose five samples
  differ, and run the before scene and the after scene through the same probe in the same session (a copy of the old
  scene file beside the new one is enough: `res://world/zz_before_greybox.tscn`). The repeat of the "before" run
  now matches to the call.
- **Docs:** Deadnight `docs/research/later-breaches.md`, "Draw calls". Check: a draw-call comparison states how many
  frames it waited and how many samples it took, and is repeated once on the unchanged scene before the numbers are
  believed.
