# Level design: the principles and how each is checked

The principles the `level-designer` agent carries (`.claude/agents/level-designer.md`), with the published practice
each one comes from and the check that settles it. The checklist an agent walks is [Map review](../engines/godot/map-review.md);
this page is why that checklist says what it says. It was written for the kit's #401, after Deadnight's review of both
maps (#833) found three ways out or past a door that the tests missed, spawns that did not read, and lighting and
landmark faults, all from a level-design reading.

GDStudio games are co-op, wave-based, third-person survival with doors that open by purchase, and they ship to the web
and to phones. The sources below are other designers' published talks, articles and books about other games; they are
studied for design and nothing of their games (layouts, names, content) is copied.

**One rule over all of them: a principle without a check is a guess.** Each principle ends in a probe (the real body or
the real night run by a tool), a capture from the player's camera (read as a picture, not as parameters), or a number
(measured, with the threshold written down). "Looks sealed", "looks dark" and "reads fine" are not results.

## The principles

### P1. Judge the map by its own numbers, measured first {#p1-judge-the-map-by-its-own-numbers-measured-first}

Metrics are the first thing a level designer fixes, and they are found by playing, not by reading a table: "you'll only
know 'it feels right' when you're walking around inside your level and playtesting", and "it can be difficult to
predict whether a wall is too high to jump, or a gap too wide"
([The Level Design Book: metrics](https://book.leveldesignbook.com/process/blockout/metrics.md)). Engines document
their own: Valve's mapper references list a crouch-jump as a separate, higher clearance than the plain jump
([Valve Developer Community: dimensions](https://developer.valvesoftware.com/wiki/Dimensions_(Half-Life_2_and_Counter-Strike:_Source))).

**Check (a number):** before the walk, write down the capsule, the jump height, the step height, the camera's arm and
shoulder offset, the dead's swing reach and the **measured reach** (P13). The review is judged against these.

- **Approach:** When a map formula's default is only the reference game's absence, ask the maintainer once and write the
  answer where a test reads it; a pull request that adds what a row forbids fixes the row in the same commit. **Watch
  out for:** the second map's formula copied the reference map's lack of perks and upgrades as its default; the machines
  shipped anyway and nothing tied the row to the scene, so the page and the map disagreed until asked. **Seen:**
  Deadnight #859, 2026-11-03 (fix: `test_map_machines.gd`
  ([lesson](../lessons/2026-11-03-a-formula-row-copied-the-reference-games-absence-and-no-test-held-it.md))).

### P2. Every opening adds a loop to run

Wave survival is played by running a circuit until the pack strings out ("training" or kiting). A designer who studied
the genre's maps found "most maps have a self looping design philosophy, where players will often times travel around
the environment and then land back in the starting area with new opportunity", and set the goal of a map "large, but
not so large the player can easily 'train' everywhere"
([Callum Stables: Gatekeeper](https://callumstables.artstation.com/pages/gatekeeper)). Rogers' hub, where "as you reach
the hub, more weenies open up", is the same shape from theme parks
([Scott Rogers, GDC 2009](https://craphound.com/disneylandleveldesign.txt)); flow is "whatever supports the intended
experience design goals" ([The Level Design Book: flow](https://book.leveldesignbook.com/process/layout/flow.md)).

**Check (a number and a probe):** for each loop, its length along the walking mesh with the dead's agent size (about
40 m or more strings a pack out; the shortest lap, by the funnel path through the outside corners, Deadnight's
`test_lot_loops.gd`) and its narrowest width (two bodies abreast); a bot soak records where bodies stop
moving. A purchase that adds no loop, weapon or light is listed as a tax.

### P3. Not every place is safe to train in

The same study builds "no man's lands" where spawners, traps and fog make circling hard, because "too many of these
opportunities can create a very 'easy' map, where there's no danger in your navigation"
([Gatekeeper](https://callumstables.artstation.com/pages/gatekeeper)). Too wide is as bad as too narrow: open ground
with no job is crossed by the dead without effort.

**Check (a number):** for each large area, the largest empty circle and the share of its ground more than 6 m from
anything solid (Deadnight's review: the field's largest circle was 7.2 m and 0.5 % of it was more than 6 m from cover,
so it was not too wide, only empty at the flanks). Each area is labelled: a place to run, to hold, or to cross, and an
area that is none of them is a finding.

### P4. Cover is low, sparse and readable, and sightlines are decided

"In general, low cover is better than tall cover", "often less cover is better", and "too many wide tall cover objects
can create confusing maze-like flow and wayfinding"; low cover keeps a player "constantly aware of enemy positions and
potential flanks" (Epic's Gears of War notes, quoted in
[The Level Design Book: cover](https://book.leveldesignbook.com/process/combat/cover.md)). id's Doom went further for
its arenas: "push forward combat" dropped cover and regenerating health so the player takes what they need from the
enemies ([Game Developer on the GDC 2018 talk](https://www.gamedeveloper.com/design/video-the-combat-design-of-i-doom-i-),
[GDC Vault](https://gdcvault.com/play/1024940/Embracing-Push-Forward-Combat-in)). Against a melee horde, cover is less a
wall to hide behind than something to run round and see over.

**Check (a capture and a number):** a capture from the player's camera at each area's entrance; the longest clear line
at eye height in each area (a ray sweep) with who it favours; and every prop given a job from the map's inventory
(cover, landmark, dressing or collision). A prop with no job is removed or given one.

### P5. Chokepoints are meant, and every fight has a way out

Players need "time to look around where to fight from" and to "create an escape plan in case the fight turns against
them" ([The Level Design Book: encounter](https://book.leveldesignbook.com/process/combat/encounter.md)). A place to hold
is a narrow the dead must pass, wide enough to hold in and with a way back.

**Check (a number):** each named chokepoint's width from the walking mesh and the second way out of the room behind it;
a hold place with one way out is listed as a dead end and justified or fixed.

### P6. The dead arrive out of sight, through an opening the player can see

Left 4 Dead's director asks of its navigation mesh "where is a spot near the Survivors, not visible to any of them?",
places mobs "at randomized spot 'behind' the Survivor team", and zeroes the wanderers of an area "when an area becomes
visible to any Survivor" ([Michael Booth, The AI Systems of Left 4 Dead, Valve 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)).
An encounter can show its enemies "visually exposed from the arena entrance" so the player plans, or "hide or spawn
more enemies around the corner" ([encounter](https://book.leveldesignbook.com/process/combat/encounter.md)). In a game
with boarded windows and breaches, the opening is the read: the player sees where the dead will come from, never the
moment they appear.

**Check (a probe and a capture):** the game's spawn audit lists each spawn point inside a solid, off the floor, in view
of the players' start, its distance to the nearest opening and to the nearest lamp; a spawn 5 to 15 m behind its
opening is a walk, not a pop. A capture from each area's entrance shows its openings. Deadnight's review found spawns at
bare fences with no breach, and six with a lamp 0.5 m away, so the dead never came out of the dark. Each opening is a
way in only if there is floor behind it: the way from its spawn to a point 1.5 m inside it is within 2 m of the straight
line. Deadnight's second map had a window over a stairwell whose dead walked 10 m outside to the next window; a path to
a far room passed it.

### P7. The way the dead come in stays true as the map opens

As doors are bought, the spawn pool grows; if the new spawns are bare ground, the arrival read of P6 erodes area by area.

**Check (a number):** the share of the spawn pool that comes through a real opening (window, breach, gate) for each
door state (Deadnight's lot fell from 100 % to 35 % as its doors opened). It is written in the review and does not fall.

### P8. Pacing rises and falls as areas open

Booth's director keeps a per-player "emotional intensity" and runs build up, sustain peak (3 to 5 seconds), peak fade
and relax (30 to 45 seconds, or until the team has moved on): "unpredictable peaks and valleys of intensity create a
powerfully compelling and replayable experience" ([Booth](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)).
Bungie split the same idea by timescale: the AI decides on 30 seconds, the mission designer on 3 minutes ("when to send
reinforcements, when to retreat"), "a 3-second loop inside of a 30-second loop inside of a 3-minute loop"
([Jaime Griesemer, Joystiq interview, 2011](https://www.engadget.com/2011-07-14-half-minute-halo-an-interview-with-jaime-griesemer.html)).
In a door-purchase game the map's 3-minute loop is the opening order: each door is a step on the curve, and a stretch
needs a valley (a place the dead are held off) or the pace has none
([The Level Design Book: pacing](https://book.leveldesignbook.com/process/preproduction/pacing.md)).

**Check (a number and a capture):** a table of every door: the round it is first affordable for one, two and four
players, and what it adds (a loop, a weapon, a light, a rest); a capture of each closed door from in front of it, which
shows what is behind it (light, a silhouette, a window) before it is bought.

### P9. Each area has a lit landmark seen from its way in

Rogers' "weenies" are "landmarks that draw guests towards certain locations", and the player is drawn "towards goals
geographically and visually" ([Rogers](https://craphound.com/disneylandleveldesign.txt)). Kevin Lynch's paths, edges,
districts, nodes and landmarks make a place imageable (*The Image of the City*, 1960), and Totten carries both into level
design ("Pathfinding with Architectural Weenies", "Organizing the Sandbox: Kevin Lynch's Image of the City", in
Christopher Totten, [*An Architectural Approach to Level Design*](https://www.routledge.com/An-Architectural-Approach-to-Level-Design/Totten/p/book/9780815361367),
CRC Press, 2nd edition 2019). Landmarks help a player regain their bearings after a fight
([Unity: level design basics](https://unity.com/blog/level-design-basics)).

**Check (a capture):** from each area's entrance and from the area before it, at the dimmest game state, the area's
landmark is in frame and lit; a person shown one frame says which area it is without a sign. Deadnight's generator, the
game's second pillar, read as a blank wall from the yard's gate: a finding.

### P10. Usable, never through walls {#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall}

"Signs are easily mistaken for irrelevant set dressing"
([The Level Design Book: wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding.md)): interactive
things share one visual language and a prompt says what they do. A prompt or a press through a wall teaches that walls
lie. Two things used with one
button are spaced so their reaches never meet: a person mending a window taps use again and again, and a wall weapon
whose reach took in the window's bought the gun that replaced the one in hand.

**Check (a probe):** the game's use-sight test walks a grid of standing points round every interactable, behind the
walls too, and demands no prompt and no press where a wall is between; a spacing sweep walks the same ground and fails on
a point inside two use zones, with half a metre between them. On the plan, before a wall is built, the middles of two
things on one floor are at least their two reaches and the gap apart: a corner with an opening on each wall has no room
for a third thing.

- **Approach:** Make an interact reach a line of sight from the hand as well as a distance, and give every interactable
  a test from behind its nearest wall or floor, on the server and on the prompt. **Watch out for:** every kind (wall
  spots, doors, posts, fuel, boards, revive) had its own flat distance check and each test stood in front, where no wall
  is, so a player behind a wall saw the card and could buy. **Seen:** Deadnight #831, 2026-11-03 (fix:
  `test_use_through_walls.gd`).
- **Approach:** When a look reads as a gameplay cue, find the object that owns it and check it on every instance of that
  object on every map, with a test that walks all of them. **Watch out for:** the boarded outline the maintainer saw was
  a moonlight card's shadow bars through an empty window, given by hand to six of the second map's twelve entries, so
  half the empty windows read as repairable and half did not. **Seen:** Deadnight #902, 2026-11-03 (fix: the cue belongs
  to the object, on every instance, not to the ones a lighting pass dressed).
- **Approach:** Draw a barricade as a window (sill, jambs, header, planks), keep the dead's navigation gap apart from
  the drawn opening, and check every barricade on every map from the player's camera for what its shape affords. **Watch
  out for:** an opening from floor to lintel reads as a way through whatever the rules say; the breaches were
  door-shaped because the gap the navigation needed at the ground was also the drawn opening. **Seen:** Deadnight #915,
  2026-11-03 (fix: the barricades were redrawn as windows).

### P11. Light guides the route; dark is never black

Lighting places lights to "provide information to help players play"; "brightly lit doorways help players understand
the flow of the room", and a dark far wall is not a primary exit, which "would be lit more prominently"
([The Level Design Book: lighting](https://book.leveldesignbook.com/process/lighting.md)). "Guide the player to their next
location using light" ([World of Level Design on Left 4 Dead 2](https://worldofleveldesign.com/categories/left4dead2_mapping/l4d2-1-level-design-tips-from-the-sacrifice.php)).
Rogers' squint test: squint at the screen, "and the main path is the brightest thing on the screen"
([Rogers](https://craphound.com/disneylandleveldesign.txt)). Dark is felt through contrast, rim and fill, not by
removing light ([lighting for darkness](https://book.leveldesignbook.com/process/lighting/darkness.md),
[Kotaku on Left 4 Dead's lighting](https://kotaku.com/the-secrets-of-left-4-deads-lighting-design-5123625)).

**Check (a capture and a number):** each area captured from the player's camera at its dimmest state; the frame blurred
(the squint test), its brightest region is the way on or the landmark; the area's lit share (floor cells above the
game's lit threshold) matches what its design page says (Deadnight's back lot was 30 % lit where its page said 5 %).

### P12. Light stays on its side of the wall

A glow is judged from every side, not the side its picture is for: billboard halos swing through walls, unshadowed
lamps reach the next room by their range, one-sided panes are holes from behind, and a spot's aim decides which boxes it
lights ([halo](../lessons/2026-11-03-a-billboard-halo-wider-than-its-gap-to-the-wall-bled-through-it.md),
[sign](../lessons/2026-11-03-a-sign-was-built-for-the-front-and-its-light-went-through-the-wall.md),
[pane](../lessons/2026-11-03-a-lit-window-was-a-hole-from-the-room.md),
[spot](../lessons/2026-11-03-a-spot-written-with-a-yaw-of-180-faced-the-road.md);
[Compatibility lighting](../engines/godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light)).

**Check (a number):** capture the room behind each wall-mounted glow, along the wall and from above, with the glow freed
and present; the pixels that change inside the room are 0. The game's glow-bleed and light-cap tests run after any
light's position or aim changes.

### P13. The real body's reach, not the jump height

The tuning's jump height is not the most a body climbs: the step-up at an edge and the capsule's rounded foot add to it
(Deadnight: jump 1.1 m, climbed 1.25 m, so a counter built "a little over a jump" at 1.2 m was a roost,
Deadnight #833). Engines that
publish metrics list the crouch-jump apart from the jump for the same reason
([Valve: dimensions](https://developer.valvesoftware.com/wiki/Dimensions_(Half-Life_2_and_Counter-Strike:_Source))).

**Check (a probe and a number):** the game's ledge probe runs the real body at blocks of each height, sprinting and
walking, jumping at several moments; the highest it stands on is the reach, and a test pins it. Every perimeter wall,
closed door and closed-area wall is above the reach plus the height of anything standable within reach of it, with the
margin written down. A top over the reach is out of reach only by the sweep: two such blocks meeting at an inside
corner were climbed from the floor. A thin collider is
judged the same way: a tree's trunk "above a jump" (2.4 m) was a step from a car roof beside it. The reach is one
constant every test reads, not a number copied into each.

### P14. Escape sweeps for every door state

Collision faults are found by movement, not by eye, and again after every geometry change
([Bugnet: QA for out of bounds and clipping](https://bugnet.io/blog/qa-testing-for-out-of-bounds-and-clipping)).
Automated agents that explore a map find "unintended game play mechanics, exploits and bugs", and EA's researchers name
exploit finding and coverage as uses in first-person shooters
([Bergdahl et al., Augmenting Automated Game Testing with Deep Reinforcement Learning, IEEE CoG 2020](https://arxiv.org/abs/2103.15819)).
A chain of props is a staircase: a barrel beside a dumpster beside a fence is a flight.

**Check (a probe):** the game's escape sweep runs the real player body from every ground cell near something solid
(sprint and jump at several moments, crouch-walk), takes each resting place as a new start, and flags a place beyond
the map, inside a closed area or on a wall top, once for each door state a team can have. Each hop starts at the solid
floor, not the walking mesh, and ground counts as reached only when a path from the start ends on it
([lesson](../lessons/2026-11-03-a-probe-began-on-the-walkable-mesh-and-jumped-0-2-m-too-high.md)). Every chain is
replayed hop by hop and captured before it is filed. The result is a number per door state (hops run, places reached,
violations), and the target is 0 violations. In the suite the sweep starts on the props near the barriers (no wall a
player must not cross is within the reach of the floor, so a way out begins on a prop), judges by area boxes, and
caches each hop across door states by the slabs near it, so a map's every door state runs in under two minutes
(Deadnight #848, whose first run found a way out the review had missed).

### P15. A roost is a decision, proven against the dead

A place a player can stand on and the dead cannot strike from turns a survival map into a shooting gallery; the genre
keeps one or two on purpose and pays for them (a long climb, a single ramp the dead also use). The dead must also be
able to follow where the design says they can: a crowd moved off the physics engine needs its floor.

**Check (a probe and a number):** the game's roost probe puts the player on each standable top the escape sweep found,
in a real night with ten dead chasing for 40 s, and counts the blows that landed. 0 blows is a roost; each roost is
listed with its verdict (by design, or a finding). Deadnight's start-room counter: 0 blows on top, 7 on the floor;
the lot's plaza container against its end wall, reached from a crate: 0 blows on its back edge (#855). The dead walk
at a night's pace (2.4 m/s): a probe that put them down with no speed never closed in. The sweep tests fail on any
standing place over the reach, not only on leaving the map.

### P16. The camera fits where the body goes

A third-person camera needs the shoulder offset plus air on both sides; a prop near a wall puts the lens inside it
([Third-person camera: walls](../engines/godot/camera.md#walls)).

**Check (a capture):** from the player's camera at every door, stair and corner, the player and the way on are in the
frame.

### P17. It reads on a phone

The maps ship to the web on phones: a smaller picture, fewer pixels drawn ([the web build on a
phone](../engines/godot/web-phone-frames.md#pixels-are-the-first-lever)) and thumbs over the screen. Mobile levels
should be easy
to read "at just one glance" ([GlobalStep: level design in mobile games](https://globalstep.com/blog/level-design-in-mobile-games-adapting-to-smaller-screens-and-touch-controls/)).
Apple's guidelines set a 44 x 44 pt default control size (28 x 28 pt minimum) and, from WCAG AA, a 4.5:1 contrast for
text up to 17 pt and 3:1 above it ([Apple HIG: accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

**Check (a capture and numbers):** each area's entrance captured at a phone's landscape size and the web build's render
scale, with the touch controls drawn: the landmark, the openings and a dead at the far end of the longest sightline are
visible and not under a thumb button; a prompt's text against the scene behind it measures 4.5:1 or more. The kit's
starting bar, not a published number: a dead at the longest sightline is at least 24 px tall in a 390 px-high frame.

### P18. Maps agree with each other, and the check stays in the suite

The same kit, door widths, prompt words and light colours mean the same thing on every map, and a map's words are its
own ([lesson](../lessons/2026-11-03-a-card-spoke-of-the-first-map-on-the-second.md)). A sweep run once is a snapshot:
geometry changes, and the jump is retuned.

**Check (a probe):** the reach, escape and use-sight checks are tests the suite runs; a review re-runs the sweeps after
any change to a wall, a prop or the player's tuning, and states the commit it ran on.

### P19. The place makes sense to a player {#p19-the-place-makes-sense-to-a-player}

A layout is a place before it is a set of numbers: the plausibility of a space is what engages a player first, and the
first questions of a place are "who made this place?" and "how will the player know?"
([The Level Design Book: worldbuilding](https://book.leveldesignbook.com/process/preproduction/worldbuilding.md)). Lynch's
imageability (P9) needs a world that holds together from every viewpoint. A formula of counts and distances can be met
by a layout no one believes: Deadnight's second map gave each room's dead "ground of their own" with a bank at the upper
floor's height and the hall's roof as ground, so both floors looked out on flat land at their sills, five windows stood
in one wall to hit a count, and one window opened over a stairwell (Deadnight #917, #824).

**Check (a table, a capture and a test):** for every opening, what is outside it at its sill and the way its dead walk
to it from where they rise on the world's ground; a capture from behind it with its boards torn and from where its dead
rise; one world outside seen from every floor; a test that fails an opening with no floor inside it or no ground or
deck outside it at its own height, and an upper opening whose dead do not rise on the ground and walk up. The map
review's [Does it make sense?](../engines/godot/map-review.md#does-it-make-sense) is the list.

- **Approach:** Give every placeholder area an issue that finishes or closes it, and before a map ships capture each
  playable spot looking past its walls. **Watch out for:** the first map's road was a placeholder greybox from the first
  layout (Deadnight #29) whose purpose stayed undecided; nothing made it a finished place or checked what a player sees
  past the lot's walls, so it stayed unfinished for a hundred pull requests. **Seen:** Deadnight #686, 2026-11-03 (fix:
  players found it when the road opened).

### P20. An objective is measured, not read

A task on a map (a step, a carry, a last stand) reads harder on paper than it plays: a list of chores across a map sounds
like a night's work and can be a minute of walking. The test of "too easy" is written before the steps are, in numbers,
and the steps are expanded until they pass. Three things have made such a chain read wrong. A fresh night is the one
state nothing has been used, so a step that asks for a full tank or whole windows is done before it starts: Deadnight's
extraction chains read 256 s from an empty night and 295 s once the boards were down and the tank half used, and the
first real nights counted a seal behind a shut door as done (Deadnight #1056). The quiet is a tool players
will use: in this genre a team keeps one dead alive and does its chores in peace, so a chain has to hold up against that
stall. And kills made ahead of the steps have to bank nothing, or the steps are a chore at the end of a farm.

**Check (a probe):** four runs of the real thing. The floor: real bodies, no dead, from the state the chain will find
(points, boards and fuel as a team has them by then), in time and in people, for one body and for four. The stall: a
real night in which the team keeps one dead alive. The night: real bots, with the share of the chain's time spent with a
dead within 10 m, the downs and the rounds it crosses. The farm: kills past the next tier bank nothing. Each place a
step stands on passes the use-sight and spacing tests (P10), and a step's new prop is judged by P13 to P15.

## What could not be read

- Valve's developer wiki sits behind an anti-bot page; the dimension figures above come from its search excerpts, and
  the Left 4 Dead points come from Booth's slides and the secondary sources.
- The Doom GDC 2018 talk was read through its listing and Game Developer's summary, not watched.
- Totten's book was read through its contents (chapter and section titles), not its text.

## Sources

| Principle | Source |
| --- | --- |
| P1, P13 | [The Level Design Book: metrics](https://book.leveldesignbook.com/process/blockout/metrics.md); [Valve Developer Community: dimensions](https://developer.valvesoftware.com/wiki/Dimensions_(Half-Life_2_and_Counter-Strike:_Source)) |
| P2, P3 | Callum Stables, [Gatekeeper](https://callumstables.artstation.com/pages/gatekeeper) (a wave-survival map's design goals); [The Level Design Book: flow](https://book.leveldesignbook.com/process/layout/flow.md), [circulation](https://book.leveldesignbook.com/process/layout/flow/circulation.md) |
| P2, P9, P11 | Scott Rogers, "Everything I Learned About Level Design I Learned from Disneyland", GDC 2009 ([text of the talk](https://craphound.com/disneylandleveldesign.txt)) |
| P4 | [The Level Design Book: cover](https://book.leveldesignbook.com/process/combat/cover.md); Kurt Loudy and Jake Campbell, "Embracing Push Forward Combat in DOOM", GDC 2018 ([GDC Vault](https://gdcvault.com/play/1024940/Embracing-Push-Forward-Combat-in), [summary](https://www.gamedeveloper.com/design/video-the-combat-design-of-i-doom-i-)) |
| P5, P6 | [The Level Design Book: encounter](https://book.leveldesignbook.com/process/combat/encounter.md) |
| P6, P7, P8 | Michael Booth, [The AI Systems of Left 4 Dead](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf), Valve, 2009 |
| P8 | Jaime Griesemer, [interview on Halo's 30-second loop](https://www.engadget.com/2011-07-14-half-minute-halo-an-interview-with-jaime-griesemer.html), 2011; [The Level Design Book: pacing](https://book.leveldesignbook.com/process/preproduction/pacing.md) |
| P9 | Kevin Lynch, *The Image of the City* (1960); Christopher Totten, [*An Architectural Approach to Level Design*](https://www.routledge.com/An-Architectural-Approach-to-Level-Design/Totten/p/book/9780815361367) (2019); [Unity: level design basics](https://unity.com/blog/level-design-basics) |
| P10 | [The Level Design Book: wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding.md) |
| P11 | [The Level Design Book: lighting](https://book.leveldesignbook.com/process/lighting.md), [lighting for darkness](https://book.leveldesignbook.com/process/lighting/darkness.md); [World of Level Design: Left 4 Dead 2 tips](https://worldofleveldesign.com/categories/left4dead2_mapping/l4d2-1-level-design-tips-from-the-sacrifice.php); [Kotaku: Left 4 Dead's lighting](https://kotaku.com/the-secrets-of-left-4-deads-lighting-design-5123625) |
| P14 | [Bugnet: QA for out of bounds and clipping](https://bugnet.io/blog/qa-testing-for-out-of-bounds-and-clipping); Joakim Bergdahl, Camilo Gordillo, Konrad Tollmar and Linus Gisslén, [Augmenting Automated Game Testing with Deep Reinforcement Learning](https://arxiv.org/abs/2103.15819), IEEE CoG 2020 |
| P17 | [Apple Human Interface Guidelines: accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility); [GlobalStep: level design in mobile games](https://globalstep.com/blog/level-design-in-mobile-games-adapting-to-smaller-screens-and-touch-controls/) |
| P10, P12 to P15, P18 | GDStudio's own lessons from Deadnight #703, #831, #832, #833, #840 and #908, linked in each principle |
| P19 | [The Level Design Book: worldbuilding](https://book.leveldesignbook.com/process/preproduction/worldbuilding.md); Deadnight #917 |
| P20 | GDStudio's own lesson from Deadnight #1056, linked in the principle |
