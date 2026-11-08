---
areas: [godot-ui]
---
# A hidden part's rectangle was read as the place it would draw in

2026-11-05

- **Saw:** the free ground for a card beside the players' column was 100 units narrower than the screen showed: with
  no point gains up, `gains.get_global_rect()` began at x 549, and with three rows up at x 651.
- **Cause:** a part that is hidden (no rows) is not laid out: its rectangle is whatever its container last gave an
  empty column, not where its rows will stand. A search that read that rectangle moved a card for nothing and then
  could not find a place at the smallest canvas.
- **Fix:** the place a part will draw in is worked out from what places it (`HudGains.room` centred on the offset from
  the screen's middle), and what comes and goes is a `soft` box the search may meet when no place misses it, not a
  rectangle read at that moment.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-card-that-looks-for-free-ground).
