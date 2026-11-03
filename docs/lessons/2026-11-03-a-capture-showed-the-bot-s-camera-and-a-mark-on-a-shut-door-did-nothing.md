---
areas: [tests, gameplay]
---
# A capture showed the bot's camera, and a bot ignored a mark behind a shut door

2026-11-03

- **Saw:** a capture meant for the person's shoulder camera (the Night as an autopilot pinned in place) showed the
  same picture whatever the person's facing was, from the front of a character; later the bot went to the near locker
  although a person had marked the far one.
- **Cause:** the hosted bot's body was added after `Night.start`, and its camera rig took the current view, so every
  frame was the bot's. Separately, the marked locker was inside the concession, whose door was still shut: the
  shop's reachability probe (`BotErrands._avoided`, cached for each mesh) rightly ignored it, and a bake of a just
  bought door was still running.
- **Fix:** after seating the bot, `_night.player().camera_rig.camera().make_current()`; buy the door, wait
  `NightFixture.settle_bake(night)` before the bot thinks; and never trust two frames that look alike: print the
  current camera (`get_viewport().get_camera_3d()`) and compare file hashes, not the picture read from one path.
- **Docs:** the capture scene `game/tests/captures/bots_ammo_ping.gd` in Deadnight does all three; the bot page
  `docs/research/bots.md` there says a mark with no way to it is ignored.
