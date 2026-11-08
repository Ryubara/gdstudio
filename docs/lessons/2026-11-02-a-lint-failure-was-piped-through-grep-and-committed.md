---
areas: [tools, process]
---
# A failed pre-commit run was filtered through grep, and the commit and push went ahead

2026-11-02

- **Saw:** markdownlint reported MD013 (a line of 123 characters) in a new lesson, but the commit and the push had
  already happened in the same command; a second commit fixed it. The same command also failed to read a file with a
  `/c/...` path from Windows Python (`FileNotFoundError`).
- **Cause:** the pre-commit run was piped through `grep` and then followed by `;`, so its exit code was lost and
  nothing stopped the chain. Git Bash paths (`/c/...`) mean nothing to the Windows `python` on the machine.
- **Fix:** chain with `&&` so a failing check stops the commit (`uvx pre-commit run --all-files && git commit ...`) and
  read the output after, not through a filter; give Python the Windows form (`C:/...`) of a path.
- **Docs:** [Hooks](../studio/hooks.md).
