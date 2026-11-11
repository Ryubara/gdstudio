# Vault clips

Three clips of the template's own for vaulting over an obstacle, on the mannequins' rig (the Universal Animation
Library has a climb, `ClimbUp_1m`, and no vault). Godot imports `vault.glb` as an `AnimationLibrary`, like the two
packs; add it to an `AnimationPlayer` under the name `vault` and the clips are `vault/Vault_Low`, `vault/Vault_High`
and `vault/Vault_Land`. Nothing in the game plays them yet: the vault (kit #1013) plays a stand-in until kit #1037.

| File | What it is |
| --- | --- |
| `vault.glb` | The three clips (24 frames a second, in place, no loop) |
| `vault_clips.json` | Each clip's reference obstacle, the speed the body is moved at, and the contact times |
| `build_vault.py` | Rebuilds both with the pinned Blender (`blender -b --factory-startup -P build_vault.py`) |
| `render_vault.py` | The contact sheets (`build_vault.py -- --render <folder>`), the poses between the keys among them |
| `../limb_overlap.py` | Measures limbs passing through each other, for this build and any other clips |

| Clip | Length | Reference obstacle | What happens |
| --- | --- | --- | --- |
| `Vault_Low` | 0.792 s | 0.8 m high, 0.4 m deep | A speed vault: off the left foot, the left hand on the top, both legs over to the right, down on the right foot |
| `Vault_High` | 1.250 s | 1.2 m high, 0.4 m deep | A two-handed side vault: a short step, off the right foot, both hands on the top, the right hand off first |
| `Vault_Land` | 0.417 s | none | The step after either vault: the right leg gives under the landing (the hips drop 0.14 m in three frames) and drives off into the sprint |

## Using them

The clips are in place: the game moves the body, as it does for every other clip. `vault_clips.json` says how the
body was moved when each clip was keyed, with forward 0 at the obstacle's front face:

- `speed` and `root_start`: the root starts `root_start` metres from the front face (negative is before it) and moves
  forward at `speed`; moved like that over the `obstacle` (`height`, `depth`), the hand lies still on the top and the
  body clears it.
- `events`: seconds from the clip's start: `takeoff` (the last foot leaves the floor), `hand_plant` and
  `hand_release` (the left hand on the top; `right_hand_release` in `Vault_High`), `over` (the hips over the middle of
  the obstacle), `land` (the right foot down, the clip's end). `root_at` is where the root is at each.
  `hand_release` is the last time the wrist is still; `push_off` is when the fingers have left and the body is in
  the air (`lowest` in `Vault_Land`: the hips' lowest point).
- `motion`: what the build measured of the move itself: each stretch in the air (`air_1`, `air_2`: its length, the
  speed upward at its start, the rise to the top of the arc and the fall from it, the speed downward at its end, and
  how far the body's centre of mass is off a free fall's arc), `release_r` (the right arm from when its hand lets go,
  or from the takeoff in `Vault_Low`, to the landing: the wrist's height over its shoulder and its speed on every
  frame), `legs` (`Vault_High`, from the takeoff until the legs come down: the hips over the top, the knees' and
  ankles' spread in hip widths, each knee, ankle and toe against the top, each ankle's speed against the hips), `push`
  (the planted arm from the plant to the push: the elbow's angle on each frame, the share of the body's weight the arm
  carries), `reach` (the landing leg's knee and foot over the last six frames) and `absorb` (`Vault_Land`'s knee and
  hips).
- `hand_place`: where the left wrist is while planted: `left` of the body's line, `forward` of the front face,
  `wrist_above_top` over the top (the palm lies on it). `Vault_High`'s right hand mirrors it.

Both vaults start in the sprint's left foot strike (`Sprint` at 0 s) and end in its right one, where `Vault_Land`
starts; `Vault_Land` ends in the left foot strike again. `Vault_Low` leaves the right hand alone (it stays 0.6 m from
the obstacle and keeps the sprint's fist), so a pistol can stay in it. `Vault_High` puts both hands open on the top:
no weapon is in the hands during it.

For another height, lift the body by the difference while a hand is on the top (`tools/capture/vault_study.tscn` does
it with `LOW_HEIGHT` and `HIGH_HEIGHT`); `Vault_Low` is made for about 0.5 to 1.0 m and `Vault_High` for about 1.0 to
1.3 m. The clips were keyed on the female mannequin. The male's arms are 5 cm longer, so his planted wrist moves up
to 35 mm (`Vault_Low`) and 71 mm (`Vault_High`) and sits up to 49 mm low: put the hand on the edge by IK if it shows.

The clips carry the body's rise and fall themselves (in the pelvis), over the reference obstacle: move the root level
and forward at `speed`. A path that drops the root to the floor at the end as well, or ends sooner than the clip's
`land`, brings the body down faster than a fall.

## Rebuilding

`build_vault.py` reads the female mannequin and the library's `Sprint_Loop`, keys the three clips from the tables in
the file, and fails before it exports when the skin goes under the floor or more than 12 mm into the box, when a
planted wrist or ankle moves, when the palm is more than 15 mm from the top, when the body is jerked to keep a hand in
reach, or when a limb is more than 5 mm inside another on either mannequin (`../limb_overlap.py` measures both skinned
meshes on every frame; the clips read 0.0 mm). It reads the clip between its keys as well, 240 times a second with
the keys joined by straight lines as a game joins them (`check_between`): a leg joint of either mannequin more than
5 mm inside the box, skin more than 12 mm inside it, a planted hand's own skin more than 20 mm into the top or the
lowest skin more than 25 mm under the floor fails the build (`--trace` prints every sample that reads anything, and
each leg joint's place near the box). It also fails on a move a body cannot make (`check_motion`): the centre
of mass more than 15 mm off a free fall's arc while nothing touches the body, a planted arm that never gives under the
weight or is not straight when the hand leaves or carries under a quarter of the body's weight, a landing leg that
folds again, snaps open or is not nearly straight a frame before the foot lands, a landing step whose knee and hips do
not give, and a free arm that is flung: its wrist more than 0.05 m over its own shoulder, faster than 7 m/s in the
world or 4.5 m/s against the shoulder, or a change of speed over 4 m/s in one frame. In `Vault_High` it fails on legs
that do not go over together: the knees over 2.0 or the ankles over 2.6 hip widths apart while the hips are over the
box, a knee under 40 degrees or a leg bone under the top there, an ankle whose speed against the hips changes by over
6 m/s in a frame, or a leg held under 1 m/s for two frames in the air. From each vault's jump on, the pelvis is not
keyed by hand: `Clip.drive` takes the height the centre of mass has to be at on every frame (a free fall in the air;
while a hand carries the body, a curve between the heights and speeds at the plant and at the push) and keys the
pelvis under it, and the build keys each clip a few times until the two agree (`--trace` prints every frame's
numbers). Positions in the tables are `(left, forward, up)` in the world of the reference obstacle; the legs in the
air are keyed in the hips' own axes (`hips()`), the left foot left of the hips and the right foot right of them, so
they cannot cross. A free arm is keyed from its own shoulder in the world's axes (`shoulder()`), so its height over
the shoulder is a number in the table whatever the body's roll. The export is the same bytes on every run, and
`vault_clips.json` carries its sha256 with the measured numbers. After a rebuild, run
`tests/assets/test_vault_clips.gd` and look at the sheets (`_over` and `_close` show the legs over the top, `_arm` the
planted arm from the plant to the push, `_side` every frame of the whole move, `_edge` the legs at the front edge
between the keys, five poses a frame).

`../limb_overlap.py` also runs on its own, on any clips of the universal rig:
`blender -b --factory-startup -P limb_overlap.py -- --clips <clips.glb> --model <mannequin.glb> [--model ...]`
prints the deepest overlap of each clip with its frame and pair, and exits 1 over `--limit` (5 mm by default). It
measures every key at the file's own frame rate, read from the key times (24 for these clips, 30 for the library's
and the prone clips; `--fps` names it for a file whose keys fit no usual rate), so its frames are the build's.
`blender -b --factory-startup -P test_limb_overlap.py` checks that: it keys a clip, measures it in the scene and from
the exported file, at 30 and at 24 frames a second, and exits 1 when the two differ.

The `.import` turns the importer's animation optimizer off: it removes keys, and a key removed from an arm that holds
a contact moves the hand.
