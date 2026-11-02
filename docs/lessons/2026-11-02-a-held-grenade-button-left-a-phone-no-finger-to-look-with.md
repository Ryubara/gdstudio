---
areas: [input, gameplay]
---
# A held grenade button left a phone with no finger to look with

2026-11-02

- **Saw:** on a phone the camera could not be turned while a grenade was held ("The user also can't control the camera
  when holding grenade", Deadnight #599). The mouse, the gamepad stick and a third finger all turned it.
- **Cause:** a hold that must be kept (a cooking grenade, aim held) takes the right thumb on a phone, and the left has
  the stick. Fire and Aim were made to look when dragged (#497) because they are held; Grenade is held for the whole
  cook and was left out, and the touch tests pressed it for one tick and never turned the view meanwhile. Nothing in the
  grenade code or the camera blocked the look: the drag from the button went nowhere.
- **Fix:** a drag that starts on any held button looks (Deadnight #599: Grenade joins Fire and Aim), and a test holds
  the grenade on every device (keyboard and mouse, gamepad, a thumb on the button, a second finger) and turns the view
  while the pin is out.
- **General:** when a verb is held, list what the hands that hold it can still do on every device and test that the
  look and the move still work during it; on touch count the fingers: two thumbs, and every held button is one.
- **Docs:** Deadnight `docs/design/touch-controls.md`.
