---
areas: [godot-ui, tests]
---
# A tap size set on one phone page was 43.1 CSS px on the narrowest

2026-11-05

- **Saw:** `phone_layout.py --section tour --size 667x375` reported taps of 43.1 CSS px on nine screens, under the 44
  floor, while `test_phone_floor` and CI were green. The same 43.1 read on main before the fix.
- **Cause:** every phone page is 540 units high, so a unit is the page's height over 540 (0.722 CSS px at 844 x 390,
  0.694 at 667 x 375). `MenuLook.TAP_TARGET` (62 units) was chosen on the 844 page (44.8 px) and the test walked only
  the pages that size and wider; the narrowest page was checked by the web probe alone, which CI does not run.
- **Fix:** the size is the least units that make 44 CSS px on the shortest page that counts as a phone (64: 44.4 px),
  and that page (1334 x 750 at ratio 2) is in `test_phone_floor`'s `CASES`. The height was free: every phone page is
  540 units high, so a size that fits the narrowest fits the rest. Deadnight #1264.
- **Check for next time:** a size in design units that stands for a size in CSS px is derived on the shortest page it
  must hold on, and a test walks that page. When a floor test lists pages, list the extremes of what a phone is (the
  narrowest, the tallest), not the common ones. A probe CI never runs is not a check.
- **Docs:** Deadnight `docs/research/phone-page-scale.md` (the narrowest page's taps).
