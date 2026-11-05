---
areas: [general, tests]
---
# A scripted cut "from this heading to the end of the file" removed the helpers that came after it

2026-11-05

- **Saw:** removing one step (and its stand-in class) from a capture tour, a script cut the file from the step's heading
  to the end. `git diff --stat` showed 40 deleted lines where about 25 were meant; the tour had lost `_key`, `_press` and
  `_still`, which sat after the step. Nothing failed: no test loads a capture script, and an import only reads the scenes
  and resources, so the tour would have broken the next time someone ran it.
- **Cause:** the cut assumed the block was the last thing in the file. In this repository helpers follow the steps.
- **Fix:** cut from the heading to the next top-level `func` or `class` (never to the end of the file), read the
  `git diff` of every file a script touched, and run `godot --headless --check-only -s <script>` on any GDScript file
  edited by a script that no suite loads. The deleted lines were restored from `git show HEAD:<path>`.
- **Docs:** none beyond this lesson; the rule for scripted edits is in the lesson on line breaks inside strings.
