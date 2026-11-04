---
areas: [blender, tools]
---
# A number pattern read the 3 of `Vector3(` as the first coordinate

2026-11-03

- **Saw:** the first build of Deadnight's drink clip (#912) reported every key's hand 5.2 to 5.7 m from its goal; the
  arm was solved onto a lip 6 m away.
- **Cause:** the build read the bottle's lip from its hold file (`muzzle = Vector3(0, 0.133, 0)`) with
  `re.findall(r"-?[\d.]+...")`, which also matches the `3` of `Vector3`, so the lip came out as (3, 0, 0.133) at the
  hold's scale of 2.
- **Fix:** read a Godot value from the text between its parentheses, as `soldier_clips._transform` does for a
  `Transform3D`: `text[text.index("(") + 1 : text.rindex(")")].split(",")`. Print each key's miss on the first build:
  a solve that reports metres where it should report millimetres has read its input wrong.
- **Docs:** [Rig sharing, a prop to the mouth](../blender/rig-sharing.md#a-held-prop-to-the-mouth).
