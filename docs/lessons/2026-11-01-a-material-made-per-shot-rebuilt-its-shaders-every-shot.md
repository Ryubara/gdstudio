---
areas: [godot, gameplay]
---
# A material made for each shot rebuilt its GL programs at every shot

2026-11-01

- **Saw:** in the web build the first shot, the first zombie and then every few seconds of firing stopped the frame for
  60 to 400 ms; a counter on `linkProgram` showed about 290 programs linked in 20 s of play, 50 times each of the same six.
- **Cause:** the muzzle flash, impact and puff each made a new `StandardMaterial3D` and freed it a moment later. A
  material's shader is shared by every material with the same settings and is freed with the last of them, so each
  shot made the shader again and the Compatibility renderer linked its programs again, on the main thread.
- **Fix:** a warm-up behind a loading screen replays one of each effect through the game's own code, then keeps the
  materials those effects made for the whole night, so the shaders are never freed; the check is "no program linked
  after the loading screen". It also draws the lot lit and dark and every enemy under each light condition.
- **Docs:** [First-use hitches](../godot/first-use-hitches.md).
