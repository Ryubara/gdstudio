---
areas: [net, tests]
---
# A test that teleported a predicting client's body made the reconciler throw it 87 m the wrong way

2026-11-03

- **Saw:** a net test for a server-owned return (Deadnight #862) put the played body and the server's body past the
  fence together; the body then showed 174 m from the start for a frame (87 m out, plus the 87 m "correction") and the
  camera 88 m from it.
- **Cause:** `Reconciler` judges a frame by where the client recorded its command `ack` left the body. A test move of the
  body is not in that record, so the first frame after it reads "server (out there) minus recorded (at the start)" as an
  error and snaps the body by it, on top of where it already is. A walk the player really made would be in the record.
- **Fix:** after moving the client's body by hand, move the server's too and call `reconciler.reset()`, and let both
  settle before the part under test. The camera is read on the frame after the body moved (the rig is placed in
  `_process`, after the physics frame that applied the correction); `RenderingServer.frame_post_draw` never fires headless
  and a wait on it hangs the run. A test spot is also checked against the physics: one "inside the second map" was in a
  3.8 m snow bank and the engine pushed the body out.
- **Docs:** Deadnight `docs/research/out-of-bounds.md`.
