---
areas: [web, godot]
---
# Playwright's headless browser is always software-rendered

2026-11-01

- **Saw:** a web export ran at 12 to 15 fps in Playwright on a PC with an RTX card; the first launch also failed with
  `Executable doesn't exist ... chromium_headless_shell-1248`.
- **Cause:** `headless=True` launches `chromium-headless-shell`, which draws with SwiftShader. A new Playwright version
  needs its own browser build (`playwright install chromium-headless-shell`).
- **Fix:** record software numbers as "it runs without a GPU", never gate on them; for real-GPU numbers launch
  `channel="chrome"`.
- **Several pages:** a headless smoke with three or four pages at once (players in one room) stalled the third and
  fourth page on software GL on a shared machine; launch it with the GPU (`--gpu`, `channel="chrome"`).
- **Docs:** Deadnight `docs/research/web-export.md`.
