---
areas: [blender]
---
# A carry clip broke when the weapon's grip moved

2026-11-02

- **Saw:** after the hand grips were solved from the weapons' sockets (Deadnight #507), the sprint carries hid the
  rifle and shotgun behind the arm and head; rebuilt with the new grip but the same recipe, the gun hung by the right
  leg and the left hand missed the fore-end by 0.2 m.
- **Cause:** the clips fixed the forearm from the gun's wanted direction through the kit weapon's place in the hand
  and the left hand reached a typed support point, so any change to the grip moved the whole carry.
- **Fix:** build the clip as the weapon's pose (grip point, muzzle, top), read the game's grip file in Blender (Godot
  bone frames are Blender's pose bone frames), and reach both hands to it by IK; a test measures both hands on the
  weapon's skin during the sprint (Deadnight `soldier_clips.py`, `sprint_carries`; `test_hand_grips.gd`).
- **Docs:** [Rig sharing, bone axes in Godot](../tools/blender/rig-sharing.md#bone-axes-in-godot-and-clips-that-hold-a-weapon).
