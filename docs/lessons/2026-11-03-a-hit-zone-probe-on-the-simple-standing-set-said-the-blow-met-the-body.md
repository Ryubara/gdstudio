---
areas: [gameplay, tests]
---
# A hit-zone probe on the fixture's simple standing set said the melee blow met the body

2026-11-03

- **Saw:** the first probe of the bat, axe and crowbar (Deadnight #924) printed `zone=body` for a chest aim and
  `zone=head` only for a head aim, which contradicted the finding of #897 (every blow is the head). With the
  night's own target set every blow was the head and dealt 68, 90 and 375, the head's multiplier.
- **Cause:** `WeaponsFixture.list_of` and `WeaponsFixture.step` send each target with the simple upright set
  (`Hitbox.STANDING`: a head sphere r 0.22, a thin body capsule). The night shoots a walker at its fitted set
  (`ZombiePose.hit_set`: `walker.move` or `walker.strike`), whose zones are larger, and a melee sweep is 0.4 m thick.
  The same fixture sat under the "real fitted zones" claim of the quick melee test, which only held because that
  blow is flat.
- **Fix:** a probe or a test that depends on the zone sends the target as the night does (`"pose":
  ZombiePose.hit_set(look, mode)`, the walker facing the player) and aims as the camera does (a ray from the camera
  pivot, 1.6 m up, through the point: the sweep then runs from the eye along it). Check the probe against the real
  night once (a real key and a camera) before trusting a zone it prints.
- **Docs:** the game's `docs/design/weapons.md#hits-to-kill-by-round` and `tests/weapons/test_melee_hits_to_kill.gd`.
