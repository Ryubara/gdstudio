---
areas: [process, ci, tools]
---
# A pull request description failed pr-rules twice and its images landed outside Screenshots

2026-11-02

- **Saw:** deadnight #553 failed `pr-rules` on its first run with `a commit names the model 'Claude Sonnet 5.5' in its
  trailer, but the description's 'Model:' line does not`, and on the second with `'Before: none' needs a reason in
  parentheses`. `gh pr create --attach` put the uploaded images after `## AI use`, not under `## Screenshots`, and a
  later `gh pr edit --attach` appended them again instead of replacing the `![alt](./name.png)` references in the body.
- **Cause:** the branch was handed over from another agent, so its commits carried a different model's trailer than the
  one finishing it, and the description was written from a draft without running the rules' wording. `--attach` appends
  uploads to the end of the body; it replaces a reference only when the body's `./file.png` path matches the attached
  file's path as given.
- **Fix:** list every model of the branch's commits on the `Model:` line (`git log --format=%b | grep Co-Authored`), and
  write `Before: none (new: ...)` with the reason in parentheses. For the images, create the pull request, read its
  body back (`gh pr view N --json body -q .body`), move each uploaded `user-attachments` URL into its place under
  `## Screenshots`, delete the appended block and `gh pr edit N --body-file <file>` without `--attach`. Check the
  headings' order after every edit.
- **Docs:** [Agents](../agents.md) (the pull request rules the checks enforce).
