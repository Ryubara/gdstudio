# Weapon pickups and the rifle

<!-- new section: shooting.md reached 53 KB when gdstudio #1040 (the rifle pickup and its two-handed hold) met main's
     aim layer; the pickup and the rifle's hold are one subject, apart from aiming and firing -->

Weapons found on the map and the rifle held in both hands: the floating pickup, giving a weapon at run time, and the
two-handed hold with its reload. Part of [the 3D Third Person template](../third-person-template.md); aiming, firing,
ammunition and switching are on [Crouch, aim and shoot](shooting.md).

## Weapon pickups and a two-handed hold {#weapon-pickups}

<!-- new section: the weapons section covers a loadout fixed in the scene; nothing said how a game hands a character a
     new weapon, or how a long gun is held when the animation library has no clip for it (gdstudio #889) -->

A weapon lying in the level is a `WeaponPickup` (`gameplay/pickup/weapon_pickup.gd` + `weapon_pickup.tscn`, a
`Pickup` that gives a weapon): its `weapon` (a `WeaponDef`) and `rounds`, the spin, bob, sound and `respawn_time` of
`Pickup`, and the nodes `Visual` (the model goes under it), `Shape` (a 1.2 m wide cylinder), `Glow` (an unshaded
additive ring on the ground in `tint`), `Light` (a 2.2 m omni light in `tint`, no shadow) and `Sound`. A weapon's own
pickup is a scene that inherits it and puts the model under `Visual`: the template's `rifle_pickup.tscn` (the rifle,
60 rounds, 20 s) stands in the prototype map between the spawn and the range.

- **What it gives** goes through the character's loadout, `WeaponLoadout.give(definition, rounds)`: a weapon not
  carried goes in a new slot with a full magazine and `rounds` in the reserve and is brought out
  (`switch_to_new`, on), one already carried takes only the rounds up to `max_reserve` (`Given.AMMO`), and one with
  a full reserve takes nothing (`Given.NOTHING`), so the pickup stays. A body with no `WeaponLoadout` leaves it. The
  pickup says `weapon_taken(collector, definition, given)` and `collected`. Any `Pickup` can give something else by
  overriding `_give(body) -> bool` and `_set_shown(shown)`; `Visual` can be any `Node3D` and bobs about its height in
  the scene.
- **Gameplay and cosmetics.** The carried list is in the loadout's step state (`CharacterState.loadout[6]`), so a
  server and a predicting client agree on what a pickup gave, and a restore takes a given weapon back. The spin, the
  glow, the light and the sound are cosmetic. Adding to `slots` at run time is additive: a screen that lists the
  weapons (an inventory) reads `slots` and redraws on `slots_changed` (a weapon given, or taken back by a restore).
- **The two-handed hold** is `TwoHandHold` (`gameplay/weapon/two_hand_hold.gd` + `two_hand_hold.tscn`; the rifle's
  `rifle_held.tscn` inherits it and adds the gun, the hands' places and the finger poses), the definition's `view`. It
  is not in the character's scene: the loadout makes the definition's `view_scene` under the `Model` slot the first time
  the character carries the weapon, so a character without a rifle carries none of its nodes. Its parts are below:
  [the rifle in both hands](#rifle-hands).
- **The rifle**: hitscan, automatic, 10 shots a second, no spread on a first shot growing to 1.2 degrees over 5
  shots in a row and back in 0.35 s ([spread](fire-modes.md#spread)), recoil 0.6, damage 22, a magazine of 30,
  60 to 180 in reserve (`rifle_ammo`), reload 2.2 s, holster 0.3 s, draw 0.4 s; Deadnight's synthesised M4A1 sounds
  (`assets/audio/rifle/`, MIT), the shot at -27 dB.

Tests: `test_weapon_pickup.gd` (walking into it gives the rifle and its rounds, it comes back after its time, with the
rifle carried it gives only rounds, with a full reserve it stays, the rifle fires while the button is held, a body with
no loadout leaves it, both hands reach their places and let go when it is put away, the step state takes a given
weapon back), `test_rifle_hold.gd` ([the rifle in both hands](#rifle-hands)) and `test_rifle_run_state.gd` (the run,
the sprint and the slide with the rifle are the same fresh, after a switch, after a burst, after a reload and after
going unarmed, and the pistol's run the same after the rifle, on both bodies; `tools/capture/rifle_run_tour.tscn`
films it from the game camera with a side view, and with `RUN_STAGES=directions` the sprint in every direction and a
reload on it), `test_rifle_sprint_carry.gd` ([the sprint](#rifle-hands)) and `test_rifle_draw_trunk.gd` (no spine bone
past `chest_turn` and the head within 15 degrees of the front through a pickup and a switch to the rifle, standing, out
of a run and a sprint, on both bodies, kit #1327). Captures:
`tools/capture/rifle_tour.tscn` from the game camera (the floating rifle, taking it, the low ready, a walk, the aim, a
burst, the aim up and down, the reload, hip fire, a crouch, a switch to the pistol and back) and
`tools/capture/rifle_hands.tscn` (six close-ups at once in every state).

Cost, measured on the desktop: a pickup's spin and bob 0.8 to 0.9 microseconds a frame; ten rifle pickups drew 35 draw
calls on the Compatibility renderer and 14 on Forward+, the same with their lights as without (each rifle is its near
level's three meshes and the ring). The hold's cost is with [its section](#rifle-hands).

- **Approach:** In a test that walks a character through a pickup with a respawn time, make the respawn longer than
  the whole walk in and out, then wait for it. **Watch out for:** with a 0.5 s respawn the rifle pickup came back
  while the character was still walking out over it and gave its rounds twice (180 in reserve, not 120). **Seen:**
  gdstudio #889, 2026-11-10.
- **Approach:** When a part moves from the scene to being made on demand (the held rifle under `Model`, made by the
  loadout when it is first carried), grep `tools/` for every `get_node` of it too and run each capture scene once: the
  export leaves `tools/` out and no suite loads it. Look such a node up when it is needed (`get_node_or_null`), never in
  `_ready`. **Watch out for:** `rifle_tour.gd` took `RifleHeld` in `_ready`, so after the change every frame of the tour
  printed a `SCRIPT ERROR` and nothing measured the hold, found only when the tour was run for the next round.
  **Seen:** gdstudio #889, 2026-11-10 (fix: `_rifle_out()` looks it up when the rifle is out).

### The rifle in both hands {#rifle-hands}

Moved to [The rifle in both hands](rifle-hands.md#rifle-hands).
