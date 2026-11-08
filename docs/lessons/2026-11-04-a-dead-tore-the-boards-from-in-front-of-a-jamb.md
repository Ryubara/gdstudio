---
areas: [gameplay, tests]
---
# A dead tore a window's boards from in front of a jamb, where nobody could shoot it

2026-11-04

- **Saw:** a bots soak (Deadnight #950, seeds 16 and 17): a window's boards stood at 5 for 190 s while the round waited.
  A dead stood at the gap's end and tore, a person at the repair spot had the jamb between them and it, and mended
  (a board a second against a walker's 1.2 s) instead of shooting.
- **Cause:** the rule "this dead is at this gate" was written for the dead's body: the gap's width plus half a metre of
  slack. The thing a person sees and shoots through is the clear opening between the jambs, 1.2 m of a 2 m gap. Every
  test asked that the dead got in or tore, none asked where it stood while it tore or who could hit it there.
- **Fix:** a dead tears only within the clear opening less 0.1 m (`ZombieGate.tear_room`); beside it, it slides along
  the wall to the front and queues (`ZombieSim._slide_to_the_opening`). A test sends a crowd at every window and
  breach of both maps and shoots every tearing dead from five places inside at chest and head, through the world's
  solids and the fitted hit zones: 7 of 7 windows failed before the fix.
- **Docs:** [map review checklist, section 3](../engines/godot/map-review.md#3-spawns-and-how-the-dead-arrive).
