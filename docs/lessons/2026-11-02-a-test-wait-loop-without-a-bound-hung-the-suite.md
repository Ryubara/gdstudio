# A test that waited for a count that never came hung the whole suite

2026-11-02

- **Saw:** a GdUnit test loop waiting for a count hung the suite when the count could not come (Deadnight
  challenges, #429).
- **Cause:** an unbounded wait turns a failed expectation into a hang, and a hang names no failing test.
- **Fix:** bound every wait loop (frames or seconds) and assert on what was seen after the bound, so the test fails
  at once and names itself.
- **Docs:** none yet; a GdUnit rule.
