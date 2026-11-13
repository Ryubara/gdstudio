# The aiming chest

<!-- new section: shooting.md and third-person-template.md reached their size limits; nothing held how far the chest
     may lean while a character aims crouched or lying -->

How far the chest of a 3D Third Person character leans while it aims crouched or lying, with every weapon. Part of
[the aim layer](shooting.md#aim-layer), which makes the modifier; the head on top of it is
[the aiming head](aim-head.md#head-on-aim).

## Standing the chest up while aiming {#aim-upright}

<!-- new section: the aim layer turns the spine only for a weapon with a muzzle; nothing stood the crouch's folded
     trunk up for the fists (gdstudio #1351) -->

Our crouch idle (`gds/Crouch_Idle`) folds the trunk so the chest (`spine_03` to `neck_01`) leans about 81 degrees
forward, which suits a body ducking low. Aiming from it, the head dropped to the bottom edge of the shoulder camera's
frame. What stands the chest up depends on the weapon (measured from the drawn pose, `tests/gameplay/test_aim_chest.gd`,
gdstudio #1351, 2026-11-12):

| Weapon | Crouched, aimed | Lying, aimed | What stands it |
| --- | --- | --- | --- |
| Pistol | 16 to 29 | 69 to 73 (its prone aim clips) | the aim clips and the aim offset (`AimOffsetModifier`) |
| Rifle | 23 | 23 (the trunk 60) | its own aim clips (`rifle/Rifle_Aim_*`, `clips_upright`) and the hold's stance |
| Fists, before | 81 to 82 | 52 (the prone idle) | nothing: no muzzle, no aim clips |
| Fists, now | 34 (30 forward) | 52 | `AimUprightModifier` |

The rifle's crouched fold the issue was filed on (81 degrees, gdstudio #1334's measurement) was gone on main before
this work: the rifle got aim clips of its own since. The test keeps it there.

The `AimLayer` makes an `AimUprightModifier` between the spine's aim turn and the head's modifier. It reads the
chest's line in this update and, where it leans forward more than `upright_max_lean` (30 degrees) about the model's
side axis, turns `spine_01` to `spine_03` back by the difference (the chain's shares, 0.3, 0.3, 0.4, about the one
axis, so they add up to it exactly); a chest leaning less, or back, is left as it is. The upper arms
(`steady`: `upperarm_l`, `upperarm_r`) keep the way they point in the model's space, so the crouch's hands still hang
toward the knees: turned back with the chest, they swung out and up, a hand by the face. Each bone is written once, so
`influence` fades it ([a modifier's influence](shooting.md#aim-layer)). It is on by the head's weight (the aim eased,
less a reload) with a weapon the spine's turn does not aim (no muzzle or no aim clip: the fists), less how far the body
lies; the pistol and the rifle never use it. A pose on each machine from the aim it already has: a puppet too, never
sent. Inspector of `AimLayer`, Upright group: `upright_max_lean`, `upright_disabled` (as before gdstudio #1351).

`tests/gameplay/test_aim_chest.gd` (`ChestPoseProbe`, the last modifier, reads the chest each drawn frame, physics at
20 ticks a second): the rifle and the fists crouched, crouch walking and lying at -30, 0 and 20 degrees, the pistol
crouched, the chest under 36 degrees off upright crouched and 60 lying; with the turn off the fists' crouched chest
leans more than 70. The capture is `tools/capture/aim_chest_tour.tscn` (`AIM_UPRIGHT=0` for before).

- **Approach:** Stand a folded trunk up for an aim with no clips of its own by a turn that only acts past a limit
  (lean at most so far), and keep the upper arms pointing where the clip had them. **Watch out for:** turning the
  spine alone carries the arms with it: the crouch's hands, hanging to the knees, swung out and up to the face. A turn
  about one axis shared over a chain is the old global turn times the bone's own share, on the parent's old global
  turn: the shares above cancel out, so writing the summed share turned the chest twice over. **Seen:** gdstudio
  #1351, 2026-11-12 (`aim_chest_tour.tscn` frames; the derivation before the first run).
- **Approach:** In a capture tour, hold an action whose tuning makes it a held button (crouch: `crouch_toggle` is off
  by default) for every stage it should last, and read a frame of each stage before trusting a before and after.
  **Watch out for:** a tap of crouch in hold mode crouches for one tick: the head tour's "crouched" stages and the
  first draft of the chest tour filmed a standing body, and the chest tour's before and after came out the same.
  **Seen:** gdstudio #1351, 2026-11-12 (fix: both tours hold `crouch`).
