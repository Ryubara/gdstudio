---
areas: [blender, camera]
---
# A carry posed from the front was hidden from the game camera

2026-11-02

- **Saw:** the first sprint carry (Deadnight #459), a gun held low across the chest, looked right on the front contact
  sheet; from behind, where the shoulder camera sits, the body hid the whole gun and no swing showed at all.
- **Cause:** poses were judged from the default front three-quarter view of the contact sheet, not from where the
  player sees the character.
- **Fix:** render the sheet from the game camera's side (`render_clips.py --view back`) before posing further, and
  prove it in a Godot capture through the real camera; the muzzle now points across and up past the helmet.
- **Docs:** [Deadnight character animation](https://github.com/Ryubara/deadnight/blob/main/docs/research/character-animation.md).
