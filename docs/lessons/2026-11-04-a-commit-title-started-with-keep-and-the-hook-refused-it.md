---
areas: [process]
---
# A commit title that started with Keep was refused by the commit hook

2026-11-04

- **Saw:** Deadnight #987: `art: Keep the hand IK's reload and long-gun hold out of the body` made
  `commit title follows the conventions ... Failed`, and no commit was made.
- **Cause:** the title was the issue's, and an issue title is not checked. The allowed verbs are Add, Fix, Update, Remove,
  Rebuild, Rework, Improve, Document; "Keep" is none of them. The same mistake as
  [an issue title reused as a commit title](../studio/hooks.md#pre-push),
  made again because nothing checked the title before the commit.
- **Fix:** write the title into a file at the start and run `gds pr check-body <body> --title <title file>` (it checks
  the title and its 72 characters) before committing; a title from an issue is looked at against the verb list first.
- **Docs:** the commit title rules in `AGENTS.md` ("Commits and pull requests").
