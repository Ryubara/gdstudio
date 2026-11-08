---
areas: [gameplay, blender]
---
# An exported zombie Idle stood in a T-pose

2026-11-01

- **Saw:** after the rig-sharing clean-up, the Quaternius Zombie's Idle rendered with its arms straight out; Walk was
  fine. The kit zombie's own Idle on the style bible sheet looked hunched, as if half crawling.
- **Cause:** Idle, Yes and No have no channels for the shoulders and arms. Blender keeps whatever pose the previous
  action left on unkeyed bones (the import's active Crawl), and a sampled glTF export writes the rest pose there.
- **Fix:** give each clip a held channel, from Walk's first frame, for every bone Walk turns and the clip does not
  (Deadnight `tools/blender/build_zombies.py`, `fill_missing_rotations`).
- **Docs:** [character variants](../tools/blender/variants.md).
