---
areas: [web, tests, ci]
---
# A picture of a night taken at Playwright's 30 s default failed the web job on main

2026-11-05

- **Saw:** deadnight main went red at the Server Browser merge: `web` failed in `bridge_calls.py` with
  `Page.screenshot: Timeout 30000ms exceeded` ("waiting for fonts to load... fonts loaded", then nothing). The count of
  the menu had passed and the night's count was already in. The same step took 161 to 187 s in six other runs.
- **Cause:** a page drawing a night on the runner's software renderer can leave the compositor without a frame for
  longer than 30 s, so a screenshot waits. Not the change under test (it touched the menu), and not a hang of the
  page: the night's numbers were read. `lobby.py` and `look_size.py` already waited 120 s for the same reason; the
  probe that counted bridge calls kept the default.
- **Fix:** a picture taken after the count is for a reader, not a check: `page.screenshot(timeout=120_000)` in a
  `try`, and a failure leaves the picture out and notes it in the report (`take_shot` in `bridge_calls.py`). A longer
  timeout alone would still fail the job on a page that never answers; a check that reads a number never depends on a
  picture. Check for next time: a new probe that screenshots a night passes a long timeout and does not fail on it.
- **Where:** `docs/research/web-smoke-probes.md` in Deadnight (#1235).
