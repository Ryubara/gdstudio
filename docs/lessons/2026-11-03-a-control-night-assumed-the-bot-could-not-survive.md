---
areas: [tests, gameplay]
---
# A control night failed because the new bot behaviour made the control winnable

2026-11-03

- **Saw:** CI `godot (1)`: `test_bot_flare.gd > test_the_same_night_without_the_flare_gun_the_pack_cannot_be_cleared`
  failed (person raised at 37 s, expected never). It passed on my machine only because I had run `tests/bots` and one
  order test, not the whole `tests/night` folder.
- **Cause:** the control's premise ("a bot with 3 rounds cannot clear a pack of 8, so the person is never raised") held
  only while a hurt bot stood and died. With health play states (#693) the hurt bot backs off, draws the dead after it,
  regenerates and kills them one by one, then raises the person alone. The behaviour worked; the control's "never"
  was too strong. Switching the states off made it pass, which proved the cause.
- **Fix:** judge the control on time, not on never: both nights play `FLARE_WINDOW` (15 s; the flare night needs about
  8) and the control must not have raised the person in it. Not by turning the states off in the test.
- **Check next time:** a change to how bots survive or move runs every suite that holds a bot night (`tests/night`),
  not only `tests/bots`; a control that asserts "cannot" should assert a time bound that the feature's purpose does not
  erase.
- **Docs:** the game's `docs/research/bots.md` play states section.
