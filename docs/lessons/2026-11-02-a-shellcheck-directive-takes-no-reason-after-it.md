---
areas: [tests]
---
# actionlint rejected `# shellcheck disable=SC2086 -- reason` in a workflow step

2026-11-02

- **Saw:** the `actionlint` job failed with `SC1072: Expected '=' after directive key` and `SC1073: Couldn't parse this
  shellcheck directive` on a `run:` block of Deadnight's ci.yml.
- **Cause:** a shellcheck directive is `key=value` and nothing else on its line; a reason after `--` is read as another
  key. The directive was there only to allow an unquoted `$folders` that should have been an array.
- **Fix:** read the words into an array (`read -r -a folders < <(cmd)`) and pass `"${folders[@]}"`: no directive, no
  word splitting. actionlint only checks `run:` scripts with shellcheck installed, so a Windows machine without it
  passes what CI rejects: run it where `shellcheck` exists, or keep scripts simple enough not to need a directive.
- **Docs:** [Test speed](../engines/godot/test-speed.md).
