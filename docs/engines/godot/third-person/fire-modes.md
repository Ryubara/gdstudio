# Fire modes

<!-- new section: shooting.md was at its size limit; nothing held what one press of fire gives per weapon (single,
     burst, automatic) or what a tap from the hip does (gdstudio #1352) -->

What one press of the fire button fires, weapon by weapon, and what a tap does. Part of
[the 3D Third Person template](../third-person-template.md); aiming, firing, ammunition and switching are on
[Crouch, aim and shoot](shooting.md).

## Single, burst and automatic {#modes}

<!-- new section: a weapon had only an automatic toggle, so a burst setting had nowhere to live and no test could cover
     it (gdstudio #1335, #1352) -->

`WeaponDef.fire_mode` (the Fire group) says what a press fires:

| Mode | A press | Held |
| --- | --- | --- |
| `SINGLE` (the pistol) | one shot | still one shot |
| `BURST` | `burst_size` shots (3), `burst_rate` apart (15 a second) | still one burst |
| `AUTOMATIC` (the rifle) | one shot | `fire_rate` shots a second until it is let go |

`fire_rate` is also the wait after a burst's last shot before the next burst can start (one `shot_interval()`).
`burst_size` and `burst_rate` are greyed out in the inspector unless the mode is `BURST`. `automatic` is still there for
older code: reading it says whether the mode is `AUTOMATIC`, and setting it picks `AUTOMATIC` or `SINGLE`.

- **How a burst runs.** The weapon counts the shots still to come (`Weapon.bursting`, in its step state after the
  melee blow's eight numbers, `Weapon.BURST_AT` 13). The character pulls the trigger on every tick while a burst is
  running, whatever the button does, and `pull()` fires each shot once the burst's spacing allows it. A press made
  during a burst stays buffered and starts the next burst once one shot interval has passed after the last shot. An
  empty magazine ends the burst with no click. A reload, a switch, a melee blow, a death, or the character losing the
  shot (a slide that does not let it shoot, the aim let go on a `fire_needs_aim` weapon) also ends it, with
  `bursting = false`.
- **Online.** The fire mode is gameplay data in the definition, so the server and the predicting client use the same
  one. Each shot of a burst is an ordinary `SHOT` event, and a command carries the shot block (`has_shot`) on each tick
  a burst shot can leave (`Character.shot_wanted`). No packet changed, so `NetWire.VERSION` stays 8. Uplink with fire
  held for 3 s, one burst: under the 1320 B/s that single fire is allowed (`test_player_step.gd`), against a budget of
  2000.
- **Cost.** Headless on the desktop (`tools/bench/weapon_cost.tscn`, three runs): a burst weapon's tick with its pulls,
  three hitscan shots started every 30 ticks, is 1.9 to 2.8 µs a tick, against 0.6 to 0.9 for an idle weapon and
  loadout. One burst cycle costs 56 to 85 µs, most of it the three rays (15 to 17 µs each). The character's step is
  unchanged within noise (`player_step_bench.tscn`, 40 bodies on commands: 40.8 and 42.0 µs a body a tick on main,
  38.0 and 37.2 on the branch).

Tests: `test_burst_fire.gd` (the weapon alone and the player with simulated mouse presses), `test_fire_count.gd` and
`test_net_fire_count.gd` (every weapon in every mode: a one-tick press, a tap under the shot interval and a 2 s hold,
offline and client against server). Capture: `tools/capture/burst_tour.tscn` films the rifle on burst from the game
camera: a tap from the hip, a tap while aiming, a press held for a second and two quick taps, with the ammo counter
going down 3 per press.

## A tap from the hip {#tap}

<!-- new section: a one-frame press with the arm down fired nothing, and nothing said whether it should; a burst needs
     the same answer (gdstudio #1352) -->

Every press fires. A press is buffered (`fire_buffer_time`, 0.3 s) and the shot leaves once the arm is half up
(`shot_aim_amount` of `aim_pose_time`, about 75 ms). While a shot is still buffered, or a burst is running
(`Character._shot_pending`), the arm keeps coming up even after the button is let go. So a tap of one tick from the hip
fires one shot or one whole burst, and the aim ends on the tick after the last shot. Only the arm then lowers, over
`shot_hold_time`.

- **Approach:** Answer what a press does in every state (arm down, arm up, held, tapped) and every fire mode at once,
  and test each one with simulated input. **Watch out for:** before #1352 a one-frame press from the arm down fired
  nothing, since the aim dropped with the button before the arm was half up. A burst started from the hip would have
  stopped after its first shot, when the arm went down. **Seen:** gdstudio #1352, 2026-11-12 (`test_fire_count.gd`
  failed 7 times with the arm-up fix taken out, `test_burst_fire.gd` twice).
