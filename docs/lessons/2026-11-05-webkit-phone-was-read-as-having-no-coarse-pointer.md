---
areas: [web, tests]
---
# A WebKit phone that ran the desktop path was read as having no coarse pointer

2026-11-05

- **Saw:** the game in Playwright's WebKit with an iPhone descriptor came up with the desktop layout (`phone: false`,
  factor 1). I wrote down "its pointer is not coarse, so it is no stand-in for iOS Safari", in the game's research page
  and in this kit's web-export page, without asking the page: the maintainer then said the zoom was on an iPhone.
- **Cause:** `(pointer: coarse)` is true there and the ratio cap installed; the one thing that differed from an iPhone
  was `navigator.maxTouchPoints`, 0 where a phone's is 5, and `TouchMode.detect` needs both.
- **Fix:** read the cause of a "not a phone" result off the page before writing it down (`matchMedia`, the
  `devicePixelRatio` descriptor, `maxTouchPoints`, one `evaluate`), and give the page what the device has (an init
  script that defines `maxTouchPoints` as 5); then the WebKit stand-in runs the whole probe.
- **Docs:** `docs/godot/web-export.md` (phone page size section); Deadnight `tools/web_smoke/phone_view.py --engine
  webkit`.
