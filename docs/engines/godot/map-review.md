# Map review: a level designer's checklist

A reusable review for any GDStudio map, run before it ships and again when its layout changes. It was written for
Deadnight's #833 (a full review of two maps) from published level-design writing, and it is built for the games we
make: co-op, wave-based, third-person survival with doors that open by purchase. Other games are studied for design
only; nothing here is copied from them. The principles behind each section, their sources and the check each one runs
are in [Level design](../../gamedev/level-design.md), and the `level-designer` agent walks this checklist.

Run it as a person (an agent) who walks the map **from the player's camera**, not from the editor, and **proves every
claim by movement or by measurement**: "looks sealed" and "looks dark" are guesses. Each section ends with the proof
that settles it.

## 0. Before the walk

- [ ] Write down the metrics the review judges against: capsule, jump height, step height, camera arm and shoulder
  offset, the dead's reach, and the narrowest passage the camera must fit. A map is judged against its own numbers
  ([metrics](https://book.leveldesignbook.com/process/blockout/metrics.md): "judge scale by playtesting, not by
  real-world numbers"; hallways at least twice the player's width).
- [ ] List what the map is meant to do: the experience goals (a place to learn, a place to kite, a place to hold), the
  opening order and what each purchase adds. Flow is "whatever supports the intended experience design goals"
  ([flow](https://book.leveldesignbook.com/process/layout/flow.md)).
- [ ] Draw the top-down plan with every door, window, spawn, light and shop spot on it. Review the plan first; a
  problem you can see on paper is cheap.

### Does it make sense? {#does-it-make-sense}

A map can hold every number of its formula and still not be a place a player believes: Deadnight's second map had a
bank raised to the upper floor's height so that each room's dead had "ground of their own", so the land outside the
upper windows was flat ground at their sill, the same as outside the ground floor; five windows in one wall line to
hit a count; and a window over a stairwell (Deadnight #917, #824). The maintainer asked that map designers reason
about whether a layout makes sense from now on. Ask what a player standing there would ask, on the plan before
building and again from the player's camera; "the simplest way to engage the player is with plausibility"
([worldbuilding](https://book.leveldesignbook.com/process/preproduction/worldbuilding.md)).

- [ ] **What is outside each opening, at its sill.** Write it down for every window, breach and door: ground, a deck,
  a roof, a drop. An opening onto a drop, a stairwell or a wall is a defect; a window above the ground floor opens onto
  a deck, a balcony or a roof the dead can reach.
- [ ] **Why the dead come from there.** For every opening, the way from where its dead rise to it: across the yard, up
  an outside stair, through a shed with its door gone. A spawn on a roof, a deck or inside a sealed room with no way in
  from the world is a monster closet; the dead rise on the world's ground and walk.
- [ ] **One world outside.** From every floor, the outside is the same place: the ground at one level (or a slope that
  reads as one), the same landmark in the same direction. Two grounds at two floors' heights, or a fence that exists
  only so a count holds, reads as a set, not a place.
- [ ] **Every room has a reason for its openings.** Who built this place, and why is there a window here? One window
  a wall reads as a building; a row of five reads as a spawn count. A shop wall has no window; an alcove holds one
  machine.
- [ ] **No two rooms joined outside.** The windows of two areas never open onto one connected deck or yard: the
  dead's walking mesh (which the bots walk too) must not join two rooms outside by a shorter way than inside, or a
  bot routes out one window and in another and gives up at the boards. Check the mesh between every pair of rooms
  (Deadnight #917: one open yard and a shared gallery sent a bot's route upstairs out a hall window).
- [ ] *Proof: a table of every opening (what is outside it, its dead's way to it), a capture from behind each opening
  with its boards torn and from where its dead rise, and a test that fails an opening with no floor inside it or no
  ground or deck outside it at its own height, and an upper opening whose dead do not rise on the ground and climb.*

- **Approach:** Before building and again from the player's camera, table every opening (what is outside it at its sill,
  its dead's way to it from where they rise) and see one world outside from every floor, with a test that fails an
  opening with no floor inside or no ground outside at its height. **Watch out for:** the second map was built to its
  formula's counts: to keep each room's dead to that room a bank was raised to the upper floor, so both floors looked
  out on flat land, five windows went in one wall and one opened over a stairwell; every check measured a number.
  **Seen:** Deadnight #917, 2026-11-03 (fix: this list).

## 1. Flow, loops and kiting space {#1-flow-loops-and-kiting-space}

Survival play is running in a circle until the pack strings out and a turn to shoot is safe. A map that cannot be
circled is a corridor with a countdown.

- [ ] **Every opening adds somewhere to run.** Each purchased area adds a loop, or the door is a tax
  (the genre's convention; Deadnight's second map was measured against a formula taken from the genre's smallest map).
- [ ] **Loops are long enough to string a pack out** (about 40 m or more, measured along the walking mesh, not
  guessed) and wide enough that two bodies abreast do not jam. A loop that a single dead end or a slot breaks is not a
  loop. *Proof: a pathfinding query round the loop with the dead's agent size, through waypoints at the outside corners
  of what it circles and with the funnel (shortest) path, not edge-centred points, which zigzag and read half again too
  long; a bot soak
  that records where bodies stop moving.*
- [ ] **No trap slots.** A gap wider than a seam and narrower than a body wedges whoever is pushed into it.
  *Proof: scan every pair of facing collider faces for a gap between the seam and the body's width.*
- [ ] **No area is a dead end by accident.** Dead ends are a pacing tool (tension, an ambush alley) when they are
  chosen and marked as such; unplanned ones are where a run ends ([flow](https://book.leveldesignbook.com/process/layout/flow.md)
  notes designers who ruled them out wholesale later regretted it). List each dead end and say why it is there.
- [ ] **Too wide is as bad as too narrow.** An open area with no cover, loop or reason to cross it is dead space the
  dead cross without effort. For each large open area: what does a player do here, and what would be lost if it were
  a third smaller?
- [ ] **Vertical flow is chosen.** "You don't need to put random steps and platforms everywhere"
  ([verticality](https://book.leveldesignbook.com/process/layout/flow/verticality.md)). Every ramp, stair and ledge
  has a purpose (a roost, a loop, a shortcut) and a way back down for the dead, proven by walking a zombie up it.

- **Approach:** Place a hidden collider or a prop against what it fills in, or clear of it by open air (about 0.8 m),
  never "about there" and never exactly a body's width; work its centre from the size helper the placement uses, not a
  raw size row, and run the slot scan and the world tests after every move. **Watch out for:** a fountain's hidden block
  stopped 0.4 m short of a wall and a bot sat in the slot for 61% of its walk; props placed from a raw row (a depth read
  as a height) left a 0.29 m slot and pushed a plank through a wall. **Seen:** Deadnight #564, 2026-11-02; Deadnight
  (end wall props), 2026-11-03 (fix: the slot scan `test_lot_gaps.gd`; the generator places props touching or clear).

## 2. Chokepoints, cover and sightlines

- [ ] **Chokepoints are named, measured and meant.** A door or gap the dead must pass is a place to hold; it needs the
  width to hold in (two abreast with room) and a place to stand that is not in the dead's line.
- [ ] **Cover is low, sparse and readable.** Low cover keeps the player aware of the fight and tall cover isolates
  them; "less cover is better" as a starting point, and wide, tall, evenly spaced objects make a maze that cannot be
  read ([cover](https://book.leveldesignbook.com/process/combat/cover.md)). For each prop: is it cover, a
  landmark, dressing or a wall? If it is none of them, delete it or give it a job.
- [ ] **Sightlines are decided.** List the longest clear line in each area and who it favours. Long lines favour the
  gun, short lines favour the dead; a horde map wants both, in different places. The dead coming from around a corner
  is a choice (an ambush alley), not an accident of where a crate fell.
- [ ] **The camera fits.** The third-person camera is swept sideways of the arm; a passage needs the shoulder offset
  plus air on both sides, and a prop too close to a wall puts the lens inside it. *Proof: a camera probe at every door,
  stair and corner.*
- [ ] **Players have a retreat.** Every fight has an escape plan the player can form before it turns
  ([encounters](https://book.leveldesignbook.com/process/combat/encounter.md): "create an escape plan in case the
  fight turns against them").

## 3. Spawns and how the dead arrive {#3-spawns-and-how-the-dead-arrive}

- [ ] **The dead appear out of sight, and come in by a believable way.** A window, a breach, a gate, a door the player
  can see torn open: never out of thin air next to a player and never through a wall. Spawn points are 5 to 15 m
  outside their opening so the arrival is a walk, not a pop. Out-of-sight spawns make ambushes; spawning in view of a
  player in the open reads as unfair ([Epic's Walking Dead template](https://dev.epicgames.com/documentation/en-us/fortnite/the-walking-dead-universe-level-design-in-unreal-editor-for-fortnite)
  advises hidden spawners for surprise; Left 4 Dead's director spawns only out of sight).
- [ ] **Every spawn has a path.** *Proof: from each spawn marker, a navigation query to every reachable room, with the
  doors in each possible bought state.*
- [ ] **Every opening is a way in.** Floor a person can stand on lies behind every window and breach: never a stairwell,
  a parapet or a prop in the way. *Proof: from each spawn, the way to 1.5 m inside its own opening, no more than 2 m
  longer than the straight line, and a capture from the player's camera behind it with a dead tearing at it. A path to
  a far room proves the map is joined, not that this opening is used (Deadnight #824: a window over a stairwell whose
  dead came in by the next one).*
- [ ] **Every barricade is a window, never a door.** An opening that reaches the floor says "walk through here", and a
  barricade is something to hold, not a way through. Each one has a sill (waist high, under the jump), a header and a
  frame, the navigation reaching the dead over the sill as a link, and the player blocked by it. *Proof: a test that
  walks every barricade the scenes have and sends a body in under the sill and through the opening with no boards, and
  a capture from the player's camera of each one (Deadnight #915: "every single barricade should be a window, not a
  door -- it gives the players this false idea that they can walk through it").*
  *A dead sent at a window starts on something: the walking mesh's nearest point under it, from a deck as wide as it
  is, and its climb counts only at that window's own sill (Deadnight #994: a start in the air off a 2.5 m deck passed
  on a window a storey below).*
- [ ] **A dead that works a barricade stands where a person inside can shoot it.** The zone a dead counts as "at the
  boards" is made for the dead's body (a gap's width and a body's slack), not for the person's line of fire; the clear
  opening between the jambs is narrower. *Proof: a crowd sent at the boards of every window and breach, and on every
  tick one is tearing, a ray from where a person stands (the repair spot, close, beside, deep) to its chest and head
  through the world's solids and its hit zones (Deadnight #997: a dead tore from in front of a jamb for 190 s while the
  round waited).*
- [ ] **A spawn never opens into a closed area.** Closed areas stay closed to the dead too (here, a window opens the dead
  of its own room only). *Proof: the opening-order test.*
- [ ] **Spawns match pacing.** Early rounds spawn where the player is looking; later rounds spawn from more openings.
  Check that no opening is used by no round and no round uses only one.
- [ ] **The start is safe to learn in.** The first area is calm enough to learn controls, and players start facing the
  way they need to go ([Unity](https://unity.com/blog/level-design-basics): "starting players facing the right
  direction").

- **Approach:** Walk a capsule of the zombie's width through every barricade of every map along the real navigation mesh
  at a stroll and a sprint, and fail on any step inside a solid; give the climb a real link and clip. **Watch out for:**
  a zombie walks the path with no collider, and the windows split the walking mesh (a 2.0 m gap) from the drawing (a 0.9
  m sill, a 1.2 m opening), so the dead passed through the wall; tests asked only that they got in, and it read as a
  missing climb clip. **Seen:** Deadnight #915, 2026-11-03 (fix: a climb link and clip, with a change of look kept from
  changing the pace).

## 4. Pacing and door unlocks

Intensity is "suspense, the player's stake" over time, not difficulty
([pacing](https://book.leveldesignbook.com/process/preproduction/pacing.md)): start quiet, alternate highs and lows,
avoid a finale at full intensity.

- [ ] **The opening order is a curve.** For each door: the round it is first affordable (one, two and four players), what
  it buys, and what it adds to the run. A door with a price and no new loop, weapon or light is a tax.
- [ ] **The next area is shown before it is bought.** A closed door shows what is behind it (a window in the shutter,
  light spilling, a silhouette): reward and denial ("show the goal, route the player out of sight of it, then let them
  see it again from closer up", [Unity](https://unity.com/blog/level-design-basics)).
- [ ] **Rest exists.** Each stretch has a place the dead are held off (a locked room, a roost, a chokepoint) where
  the player can reload, buy and revive. If there is none, the pace has no valley.
- [ ] **Shops are where the plan wants the player.** List every shop spot with the reason it stands there. A shop in the
  open invites a fight at the counter; a shop at the far wall pulls the player across the map.

## 5. Landmarks, wayfinding and readability {#5-landmarks-wayfinding-and-readability}

- [ ] **A player who loses their bearings in a fight finds them again.** Each area has a landmark visible from
  its entrance and from the area before it ("landmarks help players regain their bearings after distractions like
  fights", [Unity](https://unity.com/blog/level-design-basics)); the landmark is lit, because "landmarks need to be lit
  to be memorable".
- [ ] **Areas are different from each other** (Lynch: paths, edges, districts, nodes, landmarks make a place
  imageable). A player should say "I'm in the yard" from one glance, without a sign.
- [ ] **Interaction is readable.** Every interactive thing (door, shop, switch, board) shares one visual language
  (colour, glow, plaque) and nothing that looks interactive is not. In-world signs "are easily mistaken for
  irrelevant set dressing" ([wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding.md)), so a
  prompt, not a sign, says what it does.
- [ ] **Prompts and markers respect walls.** A prompt that fires through a wall teaches the player that walls lie.
  *Proof: stand on the far side of each wall that has a shop, door or switch on it, at the nearest legal spot, and read
  the prompt.*
- [ ] **Use zones never overlap.** A use zone is the floor a body stands on from which the server offers a thing (its
  reach, floor, line from the hand and side). Two zones share no ground, with half a metre between, so a press meant
  for one (a held or tapped repair) never lands on the next (a wall weapon that replaces the gun in hand). Reaches are
  what a hand needs, measured from where the player stands, not a generous number; where two zones still meet (a
  teammate down beside a door) the one the player looks at wins, never a fixed order of kinds; a press that carries on
  a repair buys nothing, and a purchase that costs a weapon takes a press made once its card was read. *Proof: a sweep
  over a grid of standing ground round every interactable, each zone grown by half the gap, that asks the server's own
  zone functions and fails on a point inside two; a capture from the player's camera at the worst point* (Deadnight
  #908). *On the plan, before building:*
  the middles of two things on one floor are at least their two reaches and the gap apart. With Deadnight's reaches
  (2.5 m from a window, a door or a post, 1.5 m from a shop spot, 0.5 m between): two windows, or a window and a door,
  5.5 m; a window or a door and a spot 4.5 m; two spots 3.5 m. A room's corner with an opening on each wall has no
  room for anything else used with the button (Deadnight #994). A sweep's grid point on a
  wall's face is not room for a body: its rays start behind the point.
- [ ] **Props have a job and a material.** Walk the prop list: cover, landmark, dressing or collision. A bare grey
  box in a finished area is a defect; a prop with no collision that looks solid is one too.

- **Approach:** Space things used with one button so their use zones never share ground, with a sweep of every map's
  standing ground that fails on a point inside two zones with 0.5 m between; where two meet the one looked at wins, and
  a press that carries on a repair or would throw away the weapon in hand is not a purchase. **Watch out for:** every
  use reached 3.2 m, nothing checked zones against each other and the target order put shop spots before windows, so
  boarding bought the gun beside it (7 overlaps on one map, 51 on the other). **Seen:** Deadnight #908, 2026-11-03 (fix:
  `test_use_zone_spacing.gd`, reaches from where a player stands, no purchase within 1.5 s of a repair).
- **Approach:** Before placing a new interactable on a wall, read everything else the wall hosts (openings, posts,
  other spots and their reaches) and capture the new thing from the side the player sees it, in the same pull request.
  **Watch out for:** a grenade rack placed from an x coordinate sat within the shotgun spot's reach, then over a serving
  window, then behind a breaker post that hid its plaque; only the first was caught by a test. **Seen:** Deadnight
  #577, 2026-11-02 (fix: the rack moved clear of every cut-out; the spot test lists the new kind).

## 6. Lighting

- [ ] **Light the route, not the room.** Players go toward light; light the way on (entrances, exits, shops) and let
  the rest fall off ([Game Developer](https://www.gamedeveloper.com/design/level-design-tricks-of-the-trade),
  [Unity](https://unity.com/blog/level-design-basics)). A brightly lit space "doesn't scream" horror either
  ([Kotaku on Left 4 Dead](https://kotaku.com/the-secrets-of-left-4-deads-lighting-design-5123625)), so the balance is
  mood against route.
- [ ] **Dark, never black.** Make a scene feel dark without making it dark: dim blue fill, rim light, contrast and
  specular more than raw brightness; no area where a player cannot see the next exit
  ([lighting for darkness](https://book.leveldesignbook.com/process/lighting/darkness.md)). *Proof: capture each area
  from the player's camera at the dimmest game state (generator dry, lamps out) and read the frame.*
- [ ] **Gameplay lighting matches what the rules call lit.** If a rule says the dead slow in light, the lit ground
  and the drawn light cover the same ground. *Proof: measure the drawn light's reach against the rule's.*
- [ ] **No light bleeds through a wall.** A glow, halo, light cone or shaft judged from every side of its wall:
  the room behind it, along the wall, and from above. Billboards are the usual cause. *Proof: capture with the
  glow hidden and shown; the pixel count that changes inside the room is 0.*
- [ ] **No flat corner and no hot spot.** Walk the perimeter of each room for the one corner lit by nothing, and for
  the lamp that washes a wall to white.
- [ ] **The light budget holds on the weakest device** (lights per mesh, shadow count, halo overdraw), measured on the
  phone and web targets, not the desktop.

## 7. Collision hygiene: out of bounds and skipped doors {#7-collision-hygiene-out-of-bounds-and-skipped-doors}

This is the section that cannot be done by eye. A fence that looks 3 m high can be cleared from a car roof; a door that
looks sealed can be skipped by a crouch under a lintel; a prop with no collider is a hole.

- [ ] **Measure the reach, do not read it off the tuning.** The most a body climbs is more than the jump height: the
  step-up at an edge and the capsule's rounded foot add to it (Deadnight: jump 1.1 m, climbs 1.25 m, so a counter
  built "a little over a jump" at 1.2 m was climbed). *Proof: run the real body at blocks of each height from level
  ground, sprinting and walking, from several distances, jumping at several moments; the highest it stands on is the
  reach, and a test pins it*.
- [ ] **Compute the reach.** The measured reach, plus the height of anything a player can stand on (cars, crates,
  counters, stairs' rails, a prop's top, a window sill), must be below every perimeter wall, closed door and
  closed-area wall. *Proof: list every standable platform and the highest wall top within reach of it; a margin
  under the reach is a defect. Keep the sum as a test over the shipped scene (wall top minus the tallest standable
  prop within a few metres of it, against the reach plus a margin), so a prop stacked at the wall later fails it*.
- [ ] **Chains of props are stairs.** A wall is judged against what a body can get onto from what it can get onto: a
  barrel (0.8 m) beside a dumpster (1.6 m) beside a fence (2.6 m) is a flight. *Proof: a sweep that, from every ground
  cell near something solid, runs the body at it (sprint and jump at several moments, walk and jump, crouch-walk), takes
  each place it comes to rest as a new start and repeats a few hops; flag a place beyond the map, inside a closed area or
  at wall-top height, with the doors in each state a team can have them. Replay every chain hop by hop before filing
  it.* (Deadnight's `tools/world/map_escape_probe.gd` is a worked example.)
- [ ] **A roost is measured with dead that move.** A place the body can stand on and the dead cannot reach (the middle of
  a counter 1.75 m from every edge) is a roost; put the player there with ten dead chasing and count the blows. A probe
  that spawns the dead must give them a speed and print how near they came: a zero with the dead never closer than their
  start is a probe fault. Deadnight's `tools/world/roost_probe.gd`.
- [ ] **Inside corners are steps.** Two blocks each over the reach, meeting in an L, are climbed at the corner where
  one alone is not (a 1.3 m wreck turned across another's end, against a 1.25 m reach). Tall pieces stand square, end
  to end; the sweep, not the height, says a top is out of reach.
- [ ] **A sweep test fails on every standing place over the reach,** not only on leaving the map: a top over the reach
  was reached through a step, and against a wall it is a roost one hop short of the way out.
- [ ] **A thin collider is a wall.** A tree's trunk, a post or a sign stood "above a jump" is a step from a car roof
  beside it: a 2.4 m trunk 4.6 m from a 1.65 m roof was climbed and was one hop from over a 3.0 m fence. *Proof: every
  such collider's top against the tallest standable top within a hop (about 5 m at a sprint) plus the reach and a
  margin, as a test*.
- [ ] **The sweep is a test that runs in two minutes a map.** Start the real body on every top within the reach that
  lies near a barrier (a perimeter wall, a closed door's slab, a closed area's wall) and on the floor beside tops a
  little over it; aim at whatever is solid ahead; chain three hops; judge where it settles by the areas as boxes, each
  with its floor (inner areas first, a ramp or an upper floor a box of its own), for every door state. A hop lands the
  same for any door state that leaves the same slabs near its start, so cache it by those (Deadnight: 9 door sets of
  the lot in 91 s, 8 of the second map in 68 s). Prove it on the unfixed map: put a merged fix back in a scratch
  worktree (no commit) and see it fail
  ([The shell](../../studio/shell.md#checkout)). A start cell is clear
  by the boxes' bounds, not by a capsule query: CSG faces are one-sided and a body inside a thin wall touches none.
- [ ] **An interactable is a prop too.** A breaker post, a buy stand or a machine against a wall is a step like a crate:
  Deadnight's 1.5 m breaker post flush with a 2.4 m fence was climbed from a 1.0 m kerb wall 4 m away and was one hop
  from a closed area. Place the low cover after the posts, and keep it a sprint-jump (6.4 m) from any of them.
- [ ] **Run the movement.** For each candidate, run the real player body (the same simulation the game ticks, sprinting,
  jumping, crouching, and with the camera's latest facing) from the middle and edges of the platform toward the wall.
  A scripted path or a test, never "it looks too high". Crouch and jump combined, and the jump from a stair or ramp's
  edge, are separate candidates.
- [ ] **Slopes and steps.** The floor snap, the maximum slope and the step height decide what counts as ground. A
  wedge between a prop and a wall that is steeper than the maximum slope but shallower than a wall is a ladder.
- [ ] **Seams.** Where two colliders meet (wall to floor, door slab to jamb, module to module) there is no gap a body
  can slip into, and no lip it can catch. A wall built from modules has a collider where the module is; a thin trigger
  or a one-sided plane is not a wall.
- [ ] **Missing and phantom collision.** Walk the edge of every prop and surface: no prop you can walk through that
  looks solid, no invisible block that stops walking where nothing is. Compare the visible mesh with the collision
  shape for every prop (a collision box 20 cm off its model is both).
- [ ] **Doors skip nothing.** With each door closed, the walking mesh from the player's spawn must not reach the area
  beyond, with the jump added to the climb. *Proof: the sweep above, once for each door state; a baked mesh holds the
  closed rooms' floors as islands, so ground counts as reached only when a path query from the start ends on it, and a
  hop starts at the solid floor under the mesh (it floats above it), never at the mesh*.
- [ ] **No body is stranded on the walking mesh.** A path never leaves the piece it starts on, so a piece a body can
  walk or climb to and joined to nothing leaves a bot with no way anywhere and no error. *Proof: every piece of the walking
  mesh, per door state, with its size and place; the real capsule flooded over the floor from each must not reach the
  ground the players start on within the reach, nor a top reached from it; each piece that stays has its reason written*.
- [ ] **Fall-through and edges.** Nothing walkable lies past the map's walls (distant scenery is not collision), and a
  kill volume or floor sits under every open edge. A player who somehow leaves is returned, not lost.
- [ ] **Out of bounds for the dead.** The dead, not only the players, stay inside, and no gap is wide enough for them to
  reach a closed area.
- [ ] **Test again whenever geometry changes** (a new prop, a moved wall, a retuned jump): the check is a test in the
  suite, not a one-time walk ([Bugnet](https://bugnet.io/blog/qa-testing-for-out-of-bounds-and-clipping) makes the same
  point). Visible boundaries are better than invisible walls, which are a fail-safe, not a design
  ([invisible walls](https://www.wayline.io/blog/invisible-walls-guiding-freedom-open-world-games)).

- **Approach:** Give a map a start for every body that can exist (the most seats plus bots), each with a body's room,
  on the walking mesh and joined to the others, take the lowest free one for a seat, and read the count from the scene.
  **Watch out for:** two maps had eight markers and a start was `markers[bodies % 8]`, so a ninth body stood on the
  first; one marker was inside a parked car, and a seat reopened after a leave took a marker still in use. **Seen:**
  Deadnight, 2026-11-05 (fix: 15 markers a map; a test of every map in the registry, before and after bodies settle).

## 7a. Objectives on the map

For a map with steps to finish (a chain, a carry, a last stand): the principle is
[P20](../../gamedev/level-design.md#p20-an-objective-is-measured-not-read).

- [ ] The test of "too easy" is written down before the steps, with its numbers.
- [ ] The floor is run with real bodies and no dead, **from the state the chain will find**: boards down, the tank used,
      the doors bought. A step that asks for a state a fresh night starts in is done before it begins otherwise.
- [ ] A step behind a shut door does not count until the door is open.
- [ ] The stall is run: a real night with one dead kept alive, and the chain cannot be finished in the quiet.
- [ ] The night is run with real bots at each team size and count modifier: time, rounds crossed, downs, the share of
      the time with a dead within 10 m. A run that would be cut off stops itself and reports what it reached.
- [ ] Kills made ahead of the steps bank nothing.
- [ ] Every place a step stands on passes the use-sight and spacing sweeps, and is captured from the player's camera,
      dimmest state.

## 8. Consistency across maps

- [ ] The same kit, scale, door widths, prompt wording, light colours and shop prices mean the same thing on every map,
  or the difference is written down and on purpose.
- [ ] Words on a card, marker or feed belong to the map in play, not another map's.
- [ ] Anything the second map copies from the first (a script, a light rig) is checked in the place it landed, not only
  where it was written.

## 9. The review page

For each map: a top-down plan with notes; for each area a verdict (keep, rework, remove), the evidence (a player-camera
capture, the measured number or the proven movement) and the finding's issue. Rank findings by how much they hurt
play: **out of bounds or a skipped door first** (it ends the design), then dead or stuck bodies and unreadable
prompts, then pacing and layout, then lighting and dressing. Small, certain faults (a missing collider, one mis-lit
corner) are fixed in the review with a test; layout, pacing and balance are issues for the maintainer.

## Sources

Read for design only; nothing here is copied from a game. The full list, by principle, is in
[Level design: sources](../../gamedev/level-design.md#sources).

| Subject | Source |
| --- | --- |
| Flow, circulation, verticality | [The Level Design Book: flow](https://book.leveldesignbook.com/process/layout/flow.md), [circulation](https://book.leveldesignbook.com/process/layout/flow/circulation.md), [verticality](https://book.leveldesignbook.com/process/layout/flow/verticality.md) |
| Metrics (hallway twice the player, stairs, doors) | [The Level Design Book: metrics](https://book.leveldesignbook.com/process/blockout/metrics.md) |
| Cover and sightlines | [The Level Design Book: cover](https://book.leveldesignbook.com/process/combat/cover.md) |
| Encounters: entry points, survey time, escape routes | [The Level Design Book: encounter](https://book.leveldesignbook.com/process/combat/encounter.md) |
| Pacing: intensity curve, rest, gating | [The Level Design Book: pacing](https://book.leveldesignbook.com/process/preproduction/pacing.md) |
| Prospect and refuge ("no layout is intrinsically safe") | [The Level Design Book: prospect-refuge](https://book.leveldesignbook.com/process/blockout/massing/prospect-refuge.md) |
| Wayfinding: landmarks, lit entrances, signs, contrast | [The Level Design Book: wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding.md), [Unity: level design basics](https://unity.com/blog/level-design-basics), [Game Developer: tricks of the trade](https://www.gamedeveloper.com/design/level-design-tricks-of-the-trade) |
| Dark but readable | [The Level Design Book: lighting for darkness](https://book.leveldesignbook.com/process/lighting/darkness.md), [Kotaku: the secrets of Left 4 Dead's lighting](https://kotaku.com/the-secrets-of-left-4-deads-lighting-design-5123625) |
| Horde maps: narrow flow, side rooms, light guides the player | [World of Level Design: Left 4 Dead 2 tips](https://worldofleveldesign.com/categories/left4dead2_mapping/l4d2-1-level-design-tips-from-the-sacrifice.php) |
| Spawns out of sight, horde size | [Epic: Walking Dead level design](https://dev.epicgames.com/documentation/en-us/fortnite/the-walking-dead-universe-level-design-in-unreal-editor-for-fortnite) |
| Blockout playtest, collision and out-of-bounds logging | [The Level Design Book: playtesting](https://book.leveldesignbook.com/process/blockout/playtesting.md), [Bugnet: QA for out of bounds and clipping](https://bugnet.io/blog/qa-testing-for-out-of-bounds-and-clipping) |
| Level boundaries | [Wayline: invisible walls](https://www.wayline.io/blog/invisible-walls-guiding-freedom-open-world-games) |
| Legibility (paths, edges, districts, nodes, landmarks) | Kevin Lynch, *The Image of the City* (1960) |

Valve's developer wiki ("Left 4 Dead Design Theory") sits behind an anti-bot page and could not be read; the Left 4 Dead
points above come from the secondary sources in the table.
