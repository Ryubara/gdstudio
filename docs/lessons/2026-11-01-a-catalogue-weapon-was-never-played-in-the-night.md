---
areas: [gameplay, tests]
---
# A catalogue weapon was never played in the night: the crowbar was a bat, swung nothing and hurt nothing

2026-11-01

- **Saw:** the maintainer, playing the web build, found that the crowbar used a baseball bat model, had no swing, made
  a muzzle flash on attack and its blows did nothing, and that the revolver did not show in the hand. The revolver is
  the starting weapon, so every night began with an empty hand. Every PR involved had passing tests and captures.
- **Cause, five layers, each built and tested alone (Deadnight #285):**
    - *Flash:* `ShotEffects.shot()` drew the muzzle flash before looking at the weapon kind, so a melee blow flashed
      (#111; #249 trimmed the tracer and impact for melee but left the flash).
    - *No swing:* `PlayerAnimation.play_action("Swing" / "Fire" / "Reload")` had no caller in game code. The clips came
      in #128, the holds in #288 and #295 wired only `equip()`. The capture sheets called `play_action` by hand, so
      every capture showed a swing the game never played.
    - *No damage:* the night server used the shoulder camera's ray as the melee sweep's origin. The camera sits 2.3 m
      behind the player and the sweep reaches 2.3 m, so a zombie touching the player was out of reach (#158). Guns reach
      60 m, so only melee broke. The autopilot sends its eye as the origin and `test_aim` used hand-made origins, so
      bots, balance runs and unit tests all passed.
    - *Bat for crowbar:* one hold per class; the `Melee` hold used the bat model as a stand-in (#288), and
      `test_weapon_equip` pinned `crowbar -> baseball_bat.glb` as the expected answer (#295).
    - *Empty hand:* no `Pistol` hold existed; #288 listed the pistol, SMG and flare gun as "no model" and #295's test
      asserted the hand was empty for them.
- **Why it got through:** the gaps were known and written down (the design page, a PR body, a "needs triage" issue),
  but nobody told the maintainer, and the tests turned each stand-in into the expected result. No test pressed the
  real attack input for each catalogue weapon in a real night and looked at what happened.
- **Fix:** Deadnight #285: melee skips the gun effects, the attack plays its clip, the sweep starts at the player's
  eye, each weapon id has its own hold and model; a test presses the real input for every catalogue id in a real
  night and checks the model in hand, the clip, the effect kind and the damage.
- **Rules for the next game:**
    - Every catalogue entry (weapon, item, perk) has one play-through test: real input, real night, look at the model,
      the clip, the effects and the result.
    - A test never asserts a stand-in or a missing piece as correct. A known gap is a failing or skipped test with the
      issue number, never an `EXPECTED` row.
    - A known gap that ships to the default branch is reported to the maintainer in the PR's summary and the
      coordinator's report, not only in a design page or a triage issue.
    - Capture scripts drive the game's real path; one that calls an animation or effect by hand proves nothing about
      the game.
    - An origin or range that comes from the camera is tested from the real camera at the shortest range a weapon has.
- **Follow-up (Deadnight #389):** the sweep moved to the body's head; the test now drives the real human
  controller with the real camera, since bots send their eye position and skip the camera; and a test checks that
  every catalogue id resolves to its own model file, so no hold per class can let one model stand in for another.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
