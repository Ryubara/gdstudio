---
areas: [process]
---
# A scripted edit of a pull request body deleted its sections

2026-11-06

- **Saw:** after a regex edit, `gds pr check-body` on Deadnight #1342 said `missing the section ## Issues affected` and
  four more, and `pr-rules` failed the same way. The body was down from 80 lines to 21.
- **Cause:** a body fetched with `gh pr view --json body` can hold CRLF line endings. The pattern looked for a paragraph's
  end as `\n\n`, which never matched `\r\n\r\n`, so its lazy match ran on to the next plain blank line and took every
  section with it. The edit was sent with `gh pr edit` and the check was read after it.
- **Fix:** restore from GitHub's history (`userContentEdits` on the pull request, in GraphQL: the `diff` of the edit before
  yours is the whole old body). Normalise `\r\n` first, replace exact strings with an `assert` that each is there, and run
  `gds pr check-body` before `gh pr edit`, never after.
- **Docs:** [Starting work](../starting-work.md).
