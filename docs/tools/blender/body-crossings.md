# Clip crossings on the template's bodies

<!-- new section: moved from own-animation.md#audit-bodies when that page reached 50 KB; the crossings of the library
clips on the bodies the template wears, which a clip of our own has to beat -->

How deep one limb goes into another when the library's clips play on the prototype `form` bodies the template wears
(kit #1187), measured beside the Quaternius pair the clips were made on. The audit of the clips themselves is
[The library clips the template plays, measured](library-clip-audit.md#audit); how the crossing is measured is under
[Solved clips](animation.md#solved-clips).

## The library clips on four bodies {#library-clips}

<!-- new section: the numbers of kit #1286 for every played clip that crosses over 5 mm on some body -->

`limb_overlap.py` over all 86 clips of both files on the prototype `form` bodies the template wears since kit #1187
and on the Quaternius pair (kit #1286, the deepest crossing a clip, mm; a pair named over 5 mm). Over all 86 clips the
`form` bodies cross on fewer (32 against 40); of the played clips these go over 5 mm on some body:

| Clip | form_female | form_male | Quaternius female | Quaternius male |
| --- | --- | --- | --- | --- |
| `Death01` | 30.5 (left hand in left thigh) | 0.0 | 29.4 (right hand in right thigh) | 40.9 (left hand in left thigh) |
| `Idle` | 5.5 (right hand in right thigh) | 0.0 | 16.9 (right hand in right thigh) | 0.0 |
| `Interact` | 2.7 | 0.0 | 18.9 (left hand in left thigh) | 0.0 |
| `Jump_Land` | 6.6 (left shin in left forearm) | 0.0 | 3.3 | 0.0 |
| `Slide_Exit` | 11.1 (right shin in right forearm) | 1.0 | 0.0 | 0.0 |
| `Walk` | 0.0 | 1.9 | 11.6 (left hand in left thigh) | 0.0 |
| `Punch_Jab`, `Punch_Cross` | 0.0 | 0.0 | 29.1, 19.0 (left hand in the head) | 0.0 |
| `Pistol_*` (six clips) | 12.4 to 14.3 (hand in hand) | 6.9 to 13.4 | 24.3 to 28.5 | 14.1 to 31.1 |
| `ClimbUp_1m` | 35.0 (chest in right thigh) | 44.6 | 32.4 | 26.4 |

The `form` bodies' slimmer hips and hands clear the thighs and the head where the Quaternius female's do not; their
thicker shins and forearms meet where a leg folds under an arm (`Jump_Land`, `Slide_Exit`, and `NinjaJump_Land` 12.2,
not played): kit #1295. The prototype male's thighs meet by 1.9 mm at rest, so his walk, jog and sprint read 1.9.

Those three are the library's numbers. Since kit #1295 the game plays corrected copies (`fixed/Jump_Land`,
`fixed/Slide_Exit`; `fixed/NinjaJump_Land` beside them), which read 0.0 on `form_female`, 0.0, 1.0 and 0.0 on
`form_male` and what the library's read on the Quaternius pair
([correcting a library clip](animation.md#corrected-clips)). `Sword_Dash` (29.4 and 25.5 on the `form` pair: the
thighs by 22.2 and 25.5 on frame 2, the left hand in the left thigh on frame 4) and `Sword_Heavy_Combo` (16.8 and
5.8, the thighs on frame 14) are not played; since kit #1320 `fixed/Sword_Dash` and `fixed/Sword_Heavy_Combo` read
0.0 on both `form` bodies, with one leg swivelled about its hip and ankle and each foot within 0.48 mm of the
library's. On the Quaternius pair the fixed dash reads 2.4 and 0.9 for the library's 8.0 and 23.3, and the fixed
combo 0.0 and 11.0 as the library's (a forearm in a thigh on frame 50 of the male, not a body the template wears).
Reproduce with `limb_overlap.py -- --clips universal/ual1.glb --model characters/prototype/form_female.glb --model
characters/prototype/form_male.glb --json <file>` (about 10 minutes a file for two bodies).
