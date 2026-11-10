# Vault clips

Three clips of the template's own for vaulting over an obstacle, on the mannequins' rig (the Universal Animation
Library has a climb, `ClimbUp_1m`, and no vault). Godot imports `vault.glb` as an `AnimationLibrary`, like the two
packs; add it to an `AnimationPlayer` under the name `vault` and the clips are `vault/Vault_Low`, `vault/Vault_High`
and `vault/Vault_Land`. Nothing in the game plays them yet: the vault itself is kit #1013.

| File | What it is |
| --- | --- |
| `vault.glb` | The three clips (24 frames a second, in place, no loop) |
| `vault_clips.json` | Each clip's reference obstacle, the speed the body is moved at, and the contact times |
| `build_vault.py` | Rebuilds both with the pinned Blender (`blender -b --factory-startup -P build_vault.py`) |
| `render_vault.py` | The contact sheets (`build_vault.py -- --render <folder>`) |
| `../limb_overlap.py` | Measures limbs passing through each other, for this build and any other clips |

| Clip | Length | Reference obstacle | What happens |
| --- | --- | --- | --- |
| `Vault_Low` | 0.667 s | 0.8 m high, 0.4 m deep | A speed vault: off the left foot, the left hand on the top, both legs over to the right, down on the right foot |
| `Vault_High` | 1.083 s | 1.2 m high, 0.4 m deep | A two-handed side vault: a short step, off the right foot, both hands on the top, the right hand off first |
| `Vault_Land` | 0.417 s | none | The step after either vault: down on the right foot and off into the sprint |

## Using them

The clips are in place: the game moves the body, as it does for every other clip. `vault_clips.json` says how the
body was moved when each clip was keyed, with forward 0 at the obstacle's front face:

- `speed` and `root_start`: the root starts `root_start` metres from the front face (negative is before it) and moves
  forward at `speed`; moved like that over the `obstacle` (`height`, `depth`), the hand lies still on the top and the
  body clears it.
- `events`: seconds from the clip's start: `takeoff` (the last foot leaves the floor), `hand_plant` and
  `hand_release` (the left hand on the top; `right_hand_release` in `Vault_High`), `over` (the hips over the middle of
  the obstacle), `land` (the right foot down, the clip's end). `root_at` is where the root is at each.
- `hand_place`: where the left wrist is while planted: `left` of the body's line, `forward` of the front face,
  `wrist_above_top` over the top (the palm lies on it). `Vault_High`'s right hand mirrors it.

Both vaults start in the sprint's left foot strike (`Sprint` at 0 s) and end in its right one, where `Vault_Land`
starts; `Vault_Land` ends in the left foot strike again. `Vault_Low` leaves the right hand alone (it stays 0.6 m from
the obstacle and keeps the sprint's fist), so a pistol can stay in it. `Vault_High` puts both hands open on the top:
no weapon is in the hands during it.

For another height, lift the body by the difference while a hand is on the top (`tools/capture/vault_study.tscn` does
it with `LOW_HEIGHT` and `HIGH_HEIGHT`); `Vault_Low` is made for about 0.5 to 1.0 m and `Vault_High` for about 1.0 to
1.3 m. The clips were keyed on the female mannequin. The male's arms are 5 cm longer, so his planted wrist moves up
to 37 mm (`Vault_Low`) and 76 mm (`Vault_High`) and sits up to 45 mm low: put the hand on the edge by IK if it shows.

## Rebuilding

`build_vault.py` reads the female mannequin and the library's `Sprint_Loop`, keys the three clips from the tables in
the file, and fails before it exports when the skin goes under the floor or more than 12 mm into the box, when a
planted wrist or ankle moves, when the palm is more than 15 mm from the top, when the body is jerked to keep a hand
in reach, or when a limb is more than 5 mm inside another on either mannequin (`../limb_overlap.py` measures both
skinned meshes on every frame; the clips read 0.5 mm at most). Positions in the tables are `(left, forward, up)` in
the world of the reference obstacle; the legs and the free arm in the air are keyed in the hips' own axes (`hips()`),
the left foot left of the hips and the right foot right of them, so they cannot cross. The export is the same bytes
on every run, and `vault_clips.json` carries its sha256 with the measured numbers. After a rebuild, run
`tests/assets/test_vault_clips.gd` and look at the sheets (`_over` and `_close` show the legs over the top).

`../limb_overlap.py` also runs on its own, on any clips of the universal rig:
`blender -b --factory-startup -P limb_overlap.py -- --clips <clips.glb> --model <mannequin.glb> [--model ...]`
prints the deepest overlap of each clip with its frame and pair, and exits 1 over `--limit` (5 mm by default).

The `.import` turns the importer's animation optimizer off: it removes keys, and a key removed from an arm that holds
a contact moves the hand.
