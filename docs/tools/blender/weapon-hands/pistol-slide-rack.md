# The pistol slide rack

<!-- new section: the rack outgrew the two-handed grip page, which reached the 50 KB limit when the rack and main's
     trigger work met (gdstudio #1385) -->

How the left hand racks the 3D Third Person pistol's slide after an empty reload (kit #1337). The grip the hand comes
from and goes back to is on [the two-handed pistol grip](two-handed-pistol-grip.md).

## The slide's rack after an empty reload {#the-slide-rack}

<!-- new section: the rack clip (kit #1081) had a stage and no player; nothing said how the game plays it after the
     reload, from a slide locked back, or what cuts it short (gdstudio #1337) -->

A reload of an empty pistol ends with `pistol/Pistol_Rack` (`WeaponDef.rack_clip`), played by the character's
`RackLayer` (`gameplay/character/rack_layer.gd`): a one-shot on the upper body over the reload's, at the clip's own
speed (0.93 s). The clip starts on the reload's last frame, so the rack comes in over the reload's last 0.07 s
(`FADE_IN` 0.03 s, `START_EARLY` 0.04 s) and the reload's one-shot is told not to fade out for that reload; with both
fading, the arms sank a quarter of the way to the carry. A reload with rounds left, or lying down, has none. It is
cosmetic: the rounds go in at the end of `reload_time` as before, and a shot, a blow, a switch or a new reload fades
it out (0.2 s).

`WeaponHold` follows it by `RackLayer.progress()` (`rack_weight`, `rack_share`, the caller's for a body posed by hand)
with the body's own `SlideRack` (`rack`, `rack_fit()`): two more modifiers after the left hand's (`HoldRackArm` to the
hand's place on the slide, `HoldRackFingers`), the left hand's plan at the reload's end by `SlideRack.support_weight()`
(on its grip at the clip's ends), the carried arm kept in and the trigger finger off through it, as through the
reload. The slide stays locked back until the rack: the rack starts with `rack_lock` (`slide_travel` over the rack's
travel, 0.889), the hand closes on the slide 4 cm back, pulls it the last 5 mm and lets it go, and the slide's sound
(the reload's last, held back for the rack: `Weapon.reload_steps_held`) plays there (`WeaponDef.rack_sound_at`, 0.482).
`SlideRack.hand_place()` and `slide_pull()` take the lock: before the hand lets go its places are that far back, so
the hand solved on a closed slide (`solve_rack_hand.py`) needed no new solve. `tests/fixtures/rack_stage.gd` drives the
same hold, so the stage and the game use the same weights.

Measured: on the stage, every frame and half frame on both bodies with the slide closed and locked (the left hand on
the slide 1.3 mm in at most on the female body, 0.9 mm on the male, palm and every fingertip on it, the pads on the
serrations; `test_pistol_rack.gd`); on the live player, every update of the rack on both bodies within the 2 mm and
5 mm while it grips and nothing deeper than 6 mm on the way (`test_pistol_rack_live.gd`, with the slide's place, the
sound's share, the rounds' time and the shot and the switch that cut it short). The cost, `tools/bench/hold_cost.tscn`
run `racked` against `carried` (40 figures): 31.7 against 12.7 µs a character a frame in headless Chrome, for the rack's
0.93 s. Close-ups: `tools/capture/rack_closeups.tscn` (`RACK_LOCK=0` for a closed slide) and the game itself,
`tools/capture/rack_live.tscn` (`RACK_VIEW=game`, `close` or `side`, `RACK_MODEL=male`).

- **Approach:** Have a hold read a layer's state that is true from the frame the layer asks the tree for its clip
  (`RackLayer.is_racking()`: pending or asked for), not the clip's weight, which the tree gives a frame later.
  **Watch out for:** the hold released the slide on the one frame between the rack being asked for and the tree
  playing it, so the rack started from a closed slide and the slide jumped forward at the reload's end
  (`test_an_empty_reload_ends_with_the_rack`). **Seen:** gdstudio #1337, 2026-11-12.
- **Approach:** While one clip hands over to another that starts on its last frame, give the part that follows them
  the second clip's whole weight at once (`rack_weight` is the rack's and the reload's weights together while both
  play), and hold the first clip's share at its end while the second fades out. **Watch out for:** blended by the
  rack's own fade-in, the left hand was half the reload's plan and half the rack's, and its fingers went 12.8 mm into
  the slide; blended toward a share of 0 as the rack faded out, the plan went back through the reload's steps and
  showed the new magazine in the hand for 3 frames. **Seen:** gdstudio #1337, 2026-11-12.
- **Approach:** Give a `HandPoseModifier` its poses only when they change. **Watch out for:** each pose given marks
  its layout dirty and lays every bone out again on the next update; `SlideRack.set_fingers()` gave two poses on every
  frame, and the rack cost about 46 µs a character a frame headless, 22 µs once it gave them only on a change.
  **Seen:** gdstudio #1337, 2026-11-12.
- **Approach:** Carry a share that is compared with a boundary as a `float` (64 bits in GDScript), never in a
  `Vector2`, whose parts are 32 bits. **Watch out for:** the plan's weight and share packed in one `Vector2` rounded a
  share of 0.54 onto the insert's end, so the prone reload's new magazine left the hand a hundredth early
  (`test_prone_reload_hold.gd`, both bodies). **Seen:** gdstudio #1337, 2026-11-12.
