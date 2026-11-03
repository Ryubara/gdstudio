---
areas: [tests, godot-ui]
---
# A capture waited in frames for a hold that counts seconds, and shot the wheel a third open

2026-11-02

- **Saw:** the first picture of Deadnight's bot command wheel (#642) showed three tiny tickets round the reticle and no
  dial: the wheel was a third grown. A scene that failed to parse also sat for the whole 300 s timeout before saying so.
- **Cause:** the wheel opens after 0.18 s held and grows over 0.12 s, both by the time `_process` is given. The capture
  held the key for 24 frames and waited 20 more, which is 0.4 s at 60 fps and 0.13 s at the 300 fps a windowed run on a
  fast card makes, so the shot came before it had grown.
- **Fix:** a capture of anything that moves by time waits by time (`await get_tree().create_timer(0.6).timeout`), never
  by a frame count; the bench waits real seconds. Before a windowed capture, load the scene once headless
  (`godot --headless --path game res://<scene> --quit-after 5`) and read the errors: a parse error keeps the window
  open until the timeout.
- **Docs:** Deadnight `docs/research/bot-wheel.md`.
