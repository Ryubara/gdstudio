---
areas: [tests, godot]
---
# gdformat turned a chained assert into invalid GDScript

2026-11-01

- **Saw:** after `pre-commit` reformatted a test, GdUnit4 broke with "Parser Error: Unindent doesn't match the previous
  indentation level" and hung. The file had a line holding only `. is_true()`.
- **Cause:** gdformat wraps a long call chain such as `assert_bool(x).override_failure_message("...").is_true()` in
  parentheses and puts each `.call()` on its own line, writing the dot detached from its name; in an `if`-less
  statement that is not valid GDScript.
- **Fix:** keep assert chains short: one `assert_*` call with one matcher per statement, put the message in a variable
  or drop it, and re-run the tests after every `pre-commit` run that reformats a test file.
- **Docs:** [Tests](../engines/godot/index.md).
