---
areas: [tests, process]
---
# `gh ... --attach` put the images at the end of the body, outside Screenshots

2026-11-01

- **Saw:** the `body` check failed on Deadnight #448 and #450 (twice more on #450 after the first fix): the template
  check found no uploaded Before/After capture. On #463 `gh pr edit --attach` did the same, the agent reported the
  captures as attached without reading the body, and `body` and `pr-rules` kept failing.
- **Cause:** `gh pr create --attach` and `gh pr edit --attach` append the uploaded images at the end of the
  description, outside `## Screenshots`; the body check refuses the `Before:`/`After:` lines until the images sit on
  them. File names written as plain text in that section are not uploads.
- **Fix:** write `![before](./before.png)` / `![after](./after.png)` references on the `Before:`/`After:` lines, so
  `--attach` rewrites them to the uploaded links in place; otherwise move the appended image lines under the bullets
  by hand. After any `--attach`, read the body back (`gh pr view N --json body -q .body`) and grep that the image
  lines sit under the `After:` bullet in `## Screenshots`, not at the end, then run `groundwork.py check-body` on it
  before saying the captures are attached.
- **Enforced:** a PreToolUse guard (`check_attach` in `.claude/hooks/guards.py`) refuses `gh pr create|edit --attach`
  before it runs when the body file has no `![alt](./<file>)` reference for each attached file inside `## Screenshots`
  (between `Before:` and `After:` for the before capture), and names the missing files and the line to write. Deadnight
  #448, #450, #463, #506, #536, #546 and #565 all hit this; the lesson alone did not stop it.
- **Docs:** [Capture](../capture.md#attaching).
