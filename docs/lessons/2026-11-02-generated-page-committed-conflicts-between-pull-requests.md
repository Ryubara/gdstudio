---
areas: [ci, tools]
---
# A generated page that is committed goes stale on every pair of concurrent pull requests

2026-11-02

- **Saw:** the kit's main CI went red (run 41409561985, kit #118) and kit #117, #125 and #129 each needed a merge of
  main, a re-render and another push: `docs/research/mistakes-by-area.md`, generated from every lesson, was committed,
  and `test_lessons.py` and `mistakes.py check` failed when it was not current.
- **Cause:** two lesson pull requests from the same main both rewrite the one generated file. The first merges; the
  second's merge with main has a page without the first lesson, so its tests fail. Every fix carries a lesson (#110), so
  most pull requests were affected, one extra CI round each.
- **Fix:** commit what a person writes, never what a program derives from it. The page is built where it is read: the
  MkDocs build (`hooks:` in `mkdocs.yml`, `.github/scripts/mkdocs_glossary.py`), `gds lessons <area>` and the
  SubagentStart hook, all from `docs/lessons/`. `mistakes.py check` validates the lessons' front matter only, and
  `test_two_lesson_branches_from_the_same_main_merge_clean_in_either_order` merges two lesson branches in both orders in
  a temporary repository. Before adding a generated, committed file, ask what two concurrent pull requests do to it.
- **Docs:** [Hooks: docs](../hooks.md#docs), [Lessons](index.md).
