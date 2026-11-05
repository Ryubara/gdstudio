---
areas: [web, input, tests]
---
# A browser touch test could not lift one of two fingers

2026-11-05

- **Saw:** a Playwright probe holding a stick finger and tapping Aim with a second finger saw Aim stay held after the
  tap: the sprint it was meant to return to never came back, and a second Crouch tap did nothing.
- **Cause:** with `Input.dispatchTouchEvent`, a `touchMove` that lists only the finger that stays releases nothing, even
  though the protocol text says a missing point is released; and `touchEnd` with no points lifts every finger.
- **Fix:** lift one finger with a `touchEnd` that lists only that finger (`{"type": "touchEnd", "touchPoints": [that
  finger]}`): the other stays down. Checked against the game's own held-button list before and after each variant.
- **Docs:** `tools/web_smoke/touch_sprint.py` in Deadnight (`second_finger_up`).
