---
areas: [audio]
---
# A yard sound routed through a window used the wrong fall-off

2026-11-03

- **Saw:** two things. A test of the second map's yard (a loop 25 m beyond a window, a listener 4.6 m inside it, in line)
  heard it come in at a window 9 m to the side. And the capture's stage beside a window read 7 dB louder than the rest of
  the walk, although the loops were set 8 dB under the room tone through a boarded window.
- **Cause:** the router put the loop at the window and added `20 log((unit + near) / (unit + total))` to its level,
  taking the engine's fall-off to be `unit / (unit + distance)`, which is what `AudioService` uses to rank voices. An
  `AudioStreamPlayer3D` falls off as `unit_size / distance`: no gain at `unit_size`, a boost inside it (+18 dB at a
  tenth of it). A loop 1.3 m from the listener was 18 dB up, and the farther window ranked best because the remainder
  to add is larger there.
- **Fix:** the extra level is `20 log(distance to the window / whole way round)`, so engine plus extra is
  `unit / whole way`; windows are ranked by the whole way (shortest first). A test checks that engine gain plus extra
  equals the whole-way level, and a capture level per stage shows nothing jumps.
- **Docs:** [Sound through windows](../godot/audio.md#sound-through-windows-not-walls-deadnight-657).
