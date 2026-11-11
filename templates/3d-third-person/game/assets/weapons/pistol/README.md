# Pistol

The template's weapon model: Deadnight's service pistol (a generic 1911 type), GDStudio's own script-built model, at
real length with the Toon Shooter kit's chunky cross-sections. Licence: [LICENSE.md](LICENSE.md).

| File | What it is |
| --- | --- |
| `pistol.glb` | The model: 692 triangles, one material (`Weapons`) on the palette, 0.250 x 0.196 x 0.049 m |
| `pistol_weapons_palette.png` | The 32 x 32 palette Godot extracts from the glb (lossless, no mipmaps, Detect 3D off) |
| `pistol_held.tscn` | A `BoneAttachment3D` on `hand_r` with the pistol seated in the right palm, and the `SupportHand` and `MagazineHand` markers the left hand reaches (aiming, and pushing the magazine in) |
| `build_pistol.py` | Rebuilds `pistol.glb` with the pinned Blender (`blender -b --factory-startup -P build_pistol.py`) |

## Nodes

The glb's root is `Pistol` (the frame and grip), origin at the grip. In Godot the muzzle points along -X, up is +Y and
the gun's left is +Z (the kit's weapon axes).

| Node | Where (m, in `Pistol`) | Use |
| --- | --- | --- |
| `Slide` | (0.008, 0.111, 0) | the slide, origin at its rear: move it along +X for the shot (Deadnight uses 0.05 m) |
| `Magazine` | (0.003, -0.042, 0) | the magazine, origin at its foot: drop it along the grip for a reload |
| `Muzzle` | (-0.202, 0.103, 0) | the barrel's open end; its -Z points out of the barrel (flash, shot) |
| `Eject` | (-0.092, 0.123, -0.020) | the ejection port on the right; its -Z points out of the port |
| `Grip` | (0, 0, 0) | the right hand's handle; +Y up the handle, -Z along the fingers (the barrel) |
| `Trigger` | (-0.062, 0.046, 0) | the trigger's front face; -Z is the press |
| `Support` | (-0.036, 0, 0) | the left hand's handle in a two-handed hold: the front strap, where the right hand's fingers lie |

## Holding it

Instance `pistol_held.tscn` as a child of the model slot beside the mannequin (`CharacterDressed/Model`), with its
`external_skeleton` on the mannequin's `Skeleton3D`: the `BoneAttachment3D` follows `hand_r`. The clips' own fist does
not fit the pistol, so `gameplay/weapon/hold/weapon_hold.tscn` (`WeaponHold`, a node of `character_dressed.tscn`)
closes the hands on it:

- the right hand's three fingers round the grip, the thumb high on the left side, the index finger along the frame and,
  as the character aims, on the trigger; the wrist is turned 28 degrees under the grip so that the barrel keeps the
  line the aim clips were made for (1.5 degrees up and 3 degrees out from the facing in `Pistol_Aim_Neutral`);
- while it aims or fires, the left hand on the pistol: its bone is brought to the `SupportHand` marker of
  `pistol_held.tscn` (move the marker and the hand follows, in the running game too), its fingers over the right
  hand's and its thumb forward along the frame;
- through a reload, the left hand where `Pistol_Reload` means it: on the pistol, let go for the clip's reach to the
  belt, up the grip's line to the `MagazineHand` marker with the heel of the palm on the magazine's base, and round the
  grip's foot back to `SupportHand`; the index finger is off the trigger meanwhile;
- while the pistol is carried, the arm 8 degrees out from the body (`carry_arm_out`), so the grip's foot clears the
  thigh.

Measured on the skinned mesh in every pistol clip and every locomotion clip with the pistol out
(`tests/gameplay/test_pistol_hold.gd`): no skin more than 1.2 mm inside the pistol or the other hand, and no holding
part more than 2.7 mm off it on the female mannequin and 4.4 mm on the male (the limits are 2 mm and 5 mm).

No number of the hold is typed by hand. `tools/hold/dump_hold_rig.gd` writes the rig as Godot plays it,
`tools/hold/solve_pistol_hold.py` solves the seat, the fingers and the left hand's place on both mannequins at once,
and `tools/hold/write_hold.gd` writes `pistol_held.tscn` and the five `HandPose` files of `gameplay/weapon/hold/`.
After a change to the model or to a mannequin's hands, run the three (each file's header has its command), then
`tools/capture/pistol_hold_study.tscn` for the numbers and close-ups, and the test.

The model is drawn at real length because the mannequin is real-sized (1.8 m); its chunky cross-sections read from the
third-person camera (the slide is about 9 pixels tall at 1080p from 4.4 m). How the size and the hold were chosen is in
the kit's `docs/tools/blender/weapons.md#the-third-person-template-pistol`.
