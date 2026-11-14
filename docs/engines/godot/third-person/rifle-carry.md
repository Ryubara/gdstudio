# The rifle's upright carry

<!-- new section: weapon-pickups.md went over 50 KB when gdstudio #1348 (the upright carry) met main's rifle entries;
     the carry is its own step of the hold, with its own measurements and cost -->

How the 3D Third Person rifle's hold carries the trunk upright while the character runs at the low ready. Part of
[the rifle in both hands](weapon-pickups.md#rifle-hands), whose stance it runs in.

## The trunk carried upright {#rifle-carry}

- **The carry** (kit #1348). Running at the low ready (`HoldCarry.STATES` in `gameplay/weapon/hold/hold_carry.gd`: on
  its feet or in the air, not crouched, sliding, vaulting, lying down or with the left hand away; by the ground speed,
  from none at `walk_speed` to all at `run_speed`), the trunk is carried upright: the stance averages the trunk's
  forward lean (the line from the pelvis to `neck_01`, in the model's space) over half a second (`LEAN_SMOOTHING`) and
  takes what that average has over `carry_lean_limit` (9 degrees) off, as a turn about the model's side axis spread
  evenly over the spine bones, so the stride's own rise and fall of the trunk stays and no twist is added. The head
  keeps the facing the clip gave it. It comes in and goes over `carry_time` (0.25 s) and fades out as the gun comes up
  (`carry_amount()`); the butt then stays `carry_butt_margin` (2 cm) off the skin. The run's own trunk under the rifle's
  idle leaned 13.2 degrees (female) and 13.0 (male) on average and the sprint's 14.2 and 14.0 (the unarmed run 7.8 and
  7.5); with the carry both read 8.9 to 9.3, the stride's rise and fall 0.4 to 1.0 degrees (0.5 to 0.7 before; holding
  each frame's lean at the limit left it at 0). Standing, the rifle's idle leans 10 degrees by itself and keeps it: the
  carry is for running. Its poses come from the spine's of the update (the stance's chain, kit #1347): in the web bench
  (`hold_cost.gd`'s `rifle_carry`, the low ready with the carry all the way and `carry_lean_limit` 0) it costs about 6
  to 7 microseconds a running character a frame over the low ready (median of three paired rounds, both bodies); off, it
  is three calls (about 0.2 microseconds). A single turn at the last frame's rate in place of the second pass read the
  same within the busy machine's noise, so the second pass stays.

- **Approach:** To bring a measured line (the trunk from the pelvis to the neck) to a limit by turning bones above its
  base, turn once, measure what the line moved and take the rest at that rate; and limit the line's average over a
  stride, not each frame's. **Watch out for:** the spine's turn moved the trunk's line by about half of it, so the
  first carry left the run at 9.9 degrees against 9; holding each frame's lean at the limit then stood the trunk still
  through the stride (its rise and fall 0.0 degrees, 0.5 before). **Seen:** gdstudio #1348, 2026-11-12 (fix: the
  stance's second pass and `LEAN_SMOOTHING`; `test_rifle_run_state.gd` reads the mean and the rise and fall).
