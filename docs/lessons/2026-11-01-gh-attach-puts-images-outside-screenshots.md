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
- **Docs:** [Capture](../capture.md#attaching).
