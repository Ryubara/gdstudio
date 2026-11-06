---
areas: [godot-ui]
---
# A HUD word in a screen corner read dim: the film's vignette, not the colour token

2026-11-05

- **Saw:** the bots' tag word (cream `ink` on the dark ticket, 13 : 1 as tokens) looked "about like an empty weapon slot"
  on a 844 x 390 web capture. Its red-orange HOLD token was only 5.3 : 1 on the ticket (3.6 lit).
- **Cause:** the film overlay (`film_grain.gdshader`, vignette 0.62) darkens every corner of the whole screen to about
  0.6 of its brightness, HUD included: cream (244, 234, 210) renders as (148, 142, 128), and the ammo card's number in
  the opposite corner measures the same. A contrast number taken from the tokens says nothing about a part that stands
  in a corner.
- **Fix:** measure a part's words on a real capture (the brightest pixels of the word against its plate, from the PNG),
  not only from the tokens; for a word that must read at a glance make it larger (1.35 times the caption) and lighten the
  weak colour; and write the rendered numbers down, with what stays under the target and why.
- **Docs:** [Touch controls](../godot/ui-controls.md#touch-controls) and the game's `docs/research/bot-wheel.md`.
