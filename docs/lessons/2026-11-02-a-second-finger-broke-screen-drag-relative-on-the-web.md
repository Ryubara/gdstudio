---
areas: [input, web]
---
# A second finger made touch look flick: screen-drag `relative` on the web

2026-11-02

- **Saw:** moving with the left thumb and then looking with the right made the view flick around; one thumb alone was
  fine (Deadnight #497). Also asked: a held aim button should drag to look.
- **Cause:** in Chrome with two fingers down, a finger's first `InputEventScreenDrag.relative` is measured from the
  origin or from the other finger's press (1454 px for a 100 px drag; (-1080, 522) for the stick finger), and `velocity`
  is stale for the first three drags. One finger never shows it, because its press seeds the position. Measured: a
  2.42 rad turn for a 100 px drag against 0.41 designed. #480's tests and the live probe drove one finger at a time.
- **Fix (Deadnight #506):** keep each finger's last position and step from it, never from `relative`; trust `velocity`
  only after three drags; the aim button drags to look.
- **General:** touch is multi-finger. Every touch control test has a second finger down on another control at the same
  time, and the live probe runs a two-finger case; buttons players hold are checked for drag-to-look.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
