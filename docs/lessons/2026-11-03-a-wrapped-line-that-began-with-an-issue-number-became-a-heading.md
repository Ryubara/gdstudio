---
areas: [process]
---
# A wrapped line that began with an issue number became a heading

2026-11-03

- **Saw:** markdownlint failed the pre-commit hook with `MD018/no-missing-space-atx No space after hash on atx style
  heading` on two lines of a research page that were plain sentences.
- **Cause:** wrapping at 120 columns put `#785's` and `#787 is building` at the start of a line, and Markdown reads a
  line that starts with `#` as a heading.
- **Fix:** never start a line with an issue number: rewrap so a word comes first ("are #785's", "Issue #787 is").
- **Docs:** [Lessons](index.md).
