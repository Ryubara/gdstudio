# A pose set by hand read back as the NLA track's

2026-11-01

- **Saw:** a leg solve read the same knee and ankle in every frame of a clip (the ankle's spread came out 0.0), and the
  solved legs came out as flat paddles.
- **Cause:** the rig-sharing clean-up leaves every clip on an unmuted NLA track; with no active action the NLA still
  evaluates on each `view_layer.update()` and overrides the pose bones set by hand.
- **Fix:** mute every NLA track before setting pose bones and reading `pose.bones[...].matrix`.
- **Docs:** [Gaits from kit clips](../blender/gaits.md).
