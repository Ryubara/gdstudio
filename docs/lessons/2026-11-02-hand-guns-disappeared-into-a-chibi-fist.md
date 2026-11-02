# Hand guns at the size rule disappeared into the chibi fist

2026-11-02

- **Saw:** the revolver and flare gun, sized by the weapon size rule (0.88 x real length), showed only a barrel in
  the Soldier's hand (Deadnight #376).
- **Cause:** the size rule measures a weapon against the body, but the Toon Shooter Soldier's hands are two to three
  times real size on a body at 0.8, so a one-handed gun at body scale sits inside the fist.
- **Fix:** check every held item in a hold render before writing its hold, and allow a size exception for one-handed
  guns (like the repair hammer, about 1.6x). The kit Soldier file's Revolver copy is rescaled like the AK's, so its
  hold does not carry over: use the Shotgun hold for every gun. Sweep a bent bar as one tube; boxes give a bend a
  saw-tooth edge.
- **Check:** at the start of a weapon task, compare the catalogue's ids with the weapon model folders: every id has
  its own model.
- **Docs:** [Blender weapons](../blender/weapons.md#axes-origin-and-the-hold).
