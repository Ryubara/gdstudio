---
areas: [general, blender]
---
# A build loop ran a build script I was editing in two steps

2026-11-04

- **Saw:** one of seven Blender builds in a background loop failed with `NameError: name 'arm_clearance' is not
  defined`; the others passed (Deadnight #939).
- **Cause:** while the loop ran, I added a call to a new module in one edit and its `import` in a second; the build
  that started between the two read a script that used the name and did not import it.
- **Fix:** rebuilt that file. Edit a script a running loop reads only between runs, or make a change that has to land
  whole (a use and its import) in one write; check every log of a background loop for `Traceback`, not only its exit.
- **Docs:** this lesson.
