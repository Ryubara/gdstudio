# The aiming head

<!-- new section: shooting.md reached its size limit; nothing held how the head sits while a character aims -->

How the head of a 3D Third Person character sits while it aims: level, looking along the aim, on a straight neck,
with every weapon and in every stance, on a puppet too. Part of [the aim layer](shooting.md#aim-layer), which makes
the modifier.

## Holding the head on the aim {#head-on-aim}

<!-- new section: shooting.md reached its size limit; the head's own turn while aiming (gdstudio #1334) had no room
     there -->

The aim clips carry a head and neck of their own, and the spine's turn carries them along: the library's pistol aim
leans the head about 10 degrees to the character's right and tips it 19 down whatever the aim's pitch; its up and down
blends bend the neck one way and the head the other (aiming 30 degrees down, the neck 17 back and the head 21 forward on
it); the rifle and the fists, whose aim is not a clip, look straight ahead aiming 30 down; crouched they look at the
floor. The layer makes an `AimHeadModifier` right after the spine's: it works out the turn that takes the head from
where the chest leaves it (the neck and head at their rest turns on the chest) to looking at the aim point level (no
roll against the world's up), holds it within `head_max_turn` (90 degrees) of that line, and gives the neck
`head_neck_share` (0.4) of it and the head the rest about the same axis, so they never bend against each other. It
writes each bone once (so `influence` fades it, as for the spine) and is on by the aim (the pistol's aim weight, or the
character's `aim_amount` eased) less a reload, for every weapon, on a puppet too (it reads the same aim ray). Where the
chest is bent too far for the neck (the crouch and prone clips aiming 20 degrees up), the head turns its whole reach
toward the aim and stops there. `tests/gameplay/test_aim_head.gd` reads the drawn pose each frame (`HeadPoseProbe`,
physics at 20 ticks a second so frames fall between ticks): every weapon standing, walking, crouched and lying at -30, 0
and 20 degrees, the head within 3 degrees of level, 4 of the aim, its roll on the neck and the neck's on the chest under
8, no zigzag, under 0.5 degrees between frames; with the head off, 1562 checks fail. `test_net_puppet_head.gd` checks a
puppet with the pistol and the rifle; the capture is `tools/capture/aim_head_tour.tscn` (`AIM_HEAD=0` for before).

The body that swings round at the start and end of an aim is not the head: while the aim fades in, the spine's turn
folded the chest back by up to 47 degrees on main (gdstudio #1318, [the aim layer](shooting.md#aim-layer)). The head
modifier rides whatever chest that leaves.

- **Approach:** Give the head its own last say while aiming: a modifier after every spine turn that sets the neck and
  head from the chest's pose of this update toward the aim point, level, shared over the two bones about one axis.
  **Watch out for:** a head that rides the clips and the spine's turn takes whatever the clip author's shooter did (a
  cheek leaned on the sights, a neck and head blended against each other between the up and down poses); measuring the
  head on its neck alone hides it, since most of the lean is the chest's: read the head's roll against the world's up
  and where it faces against the aim too. **Seen:** gdstudio #1334, 2026-11-12 (`test_aim_head.gd`).
