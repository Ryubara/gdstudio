# Rooms, worlds and events

<!-- new section: multiplayer.md stood at its 50 KB limit (gdstudio #1123, from #910's report), so its sections on
     a room's server, its two worlds, its events and a player's way in and out moved here; multiplayer.md keeps a short
     section per anchor that links to each -->

What a server-authoritative room does on the server and how it reaches each client: a room over a real socket in a
test, the two worlds that must hold the same solid things, the bodies every client sees, events through the command
loop, the end of a night the server owns and a player's way in and out. The transport, the protocol and the costs are
on [Multiplayer](../multiplayer.md).

## A room over a real socket, faster than real time (Deadnight #230) {#room-over-socket}

A soak of a game server's room with real clients (ten game minutes, two people and two bots) runs in about three
minutes of wall time on one headless Godot process: `--fixed-fps 60` makes each frame exactly one physics tick and
removes the pacing (no vsync headless), so the server, the clients and the bots step as fast as the machine allows. Two
things have to run on game time, or the run fails for a reason that is not the code: the server's connection rules (a
peer may send 90 commands a second: at fixed-fps the wall clock sees several hundred and kicks it), which take a
`clock` Callable (`NightHost.clock`, `Engine.get_physics_frames() / 60.0`), and the client link's own clock
(`WebSocketLink.clock`). A run through a `GameServer` (tickets, rooms) sets `GameServer.clock`, which times the server's
own hellos and gives every room it opens the same clock (Deadnight #1059: without it the first bench lost its client
within a few seconds). Everything else already counts frames. The numbers: 36,000 ticks, server step 1.5 ms mean for
two autopilot clients and two bots, no engine error in the verbose log. The soak is
`tests/captures/bots_slots_soak.tscn` in Deadnight, a CI job of its own because it is too long for a test shard.

## The two worlds must hold the same solid things {#the-two-worlds-must-hold-the-same-solid-things}

A predicting client moves its body against its own copy of the map, the server moves the real one against the server's.
A solid thing that only one holds is a wall the other walks through, and the client's body then drifts metres from the
server's (Deadnight #748: a prize crane's cabinet, a `StaticBody3D` that the client-only drawing added to itself). Views
and drawings carry no collision; a solid thing is built into the world both sides build and moved there by the rules
(server) and the frame (client). The same goes for the bodies: the client draws the other players as puppets with no
collision, so the server's bodies must not block one another either (Deadnight #760: a body on layer 1 with a mask of 1
and 2 stopped at a teammate for good; players now sit on a layer of their own). Test it with a real client and host:
list every `CollisionObject3D` and colliding `CSGShape3D` under each side's viewport and compare them
(`tests/net/test_world_parity.gd`). A solid thing that moves is put at the command's tick on both sides
([networked map parts](../third-person/net-world.md#net-world)).

- **Approach:** Build a solid thing into the world both sides build and move it by the rules (server) and the frame
  (client); a view script adds no collision (a node it makes with `.new()` gets none), and a test joins a real client to
  a real host and asks that every solid thing in the client's viewport is in the server's at the same place. **Watch
  out for:** the prize crane's drawing gave itself a `StaticBody3D`, a game server draws nothing, so a sprint past it
  stopped the client's body and not the server's, and a soak failed under load with "client N is 2.5 m from the
  server"; a stall guard was blamed first, and a trace of what each world held at the server's spot found it.
  **Seen:** Deadnight #748, #754, 2026-11-03 (fix: `CraneBlock` lives in `NightWorld`; the test failed on main, 227
  against 226).
- **Approach:** Keep played bodies on a layer of their own that no body's mask lists, so bodies never block one another
  on either side, and list `PhysicsLayers.BODY` in the mask of every ray that must meet a body (a shot, a swing, a
  grenade, footsteps, a ping). **Watch out for:** bodies on layer 1 with a mask of 1 and 2 stopped at a teammate on
  the server and not on the client, whose puppets have no collision; the 0.6 to 0.9 m that left grew into metres at
  the next corner, the gaps sat just over the reconciler's 2.5 m snap, and a correction that cannot move a blocked body
  hides the rest. **Seen:** Deadnight #760, 2026-11-03 (fix: layer 4; the soak compares both worlds' solid things every
  300 ticks and names what each body slid on; a missed ray broke `test_smallmap_bot_night`).
- **Approach:** When a map ships, play it through every path that builds a night (solo, host, a client built from the
  WELCOME, the balance simulator) and assert that the host's and the client's economy has the map's rules. **Watch out
  for:** the map's rules overlay (`MapTuning`, laid by `NightWorld.rules_for`) was applied by the solo night and
  `SeatedNight` only, so `NightHost` and `Night.start_remote` built the map's scene with the shared table and the
  room's server threw at `use_offers.gd:20` for want of the door items. **Seen:** Deadnight, 2026-11-03 (fix: both lay
  `world.rules_for(table)`; `test_map_choice_net.gd`).

## Every client sees the same bodies {#appearance}

<!-- new section: the solid-things section compares collision; nothing covered how bodies look and stand on every
client -->

- **Approach:** Dress every body, the player's own included, from one appearance table the server owns, build local and
  remote bodies from one scene (or one shared transform), and test two clients over the real socket: every player shows
  the same parts, colours, skeleton height, scale and facing on every client and on the server. **Watch out for:**
  bodies were dressed only on the loopback path, two windows on one machine shared one settings file, and the player
  scene turned its model half round and scaled it 0.8 while remote avatars did neither, so on the other screen a player
  was a quarter taller and faced the camera. **Seen:** Deadnight, 2026-11-01 (looks); Deadnight, 2026-11-01 (height)
  (fix: the two-client test, and a `--look` flag that gives local windows different looks).
- **Approach:** Build and test every player-visible feature twice, as the player sees themselves and as every other
  client sees them, from the same state and events: a two-client test over the real socket asserts the other client's
  screen for each action (weapon, swap, aim, fire clip and flash, reload, swing, throw, a late joiner). **Watch out
  for:** online, a remote player was a bare model with no `PlayerAnimation`, so everything that draws a weapon got null
  and the aim pose was not in the frame; every test looked at the local body. **Seen:** Deadnight #518, 2026-11-02 (fix:
  remote bodies are the same scene as local ones (a puppet `Player`), the frame gains `aim` and `pitch`, captures come
  from the second client (Deadnight #548); code that works through a node type (`as Player`) turns "no such body" into
  a silent skip, so say it loudly); gdstudio #905 (online-client.md#puppets).

## Events reach a client only through its command loop {#events-reach-a-client-only-through-its-command-loop}

A test client that is driven by hand must still send its command every tick (`night.ticked` connected to
`link.send(command.to_dict())`): the server answers a command with the tick's events, and without one the client is
sent only the spawn requests. Fire with the same command a player's input makes (`NightCommand.aim_along`, `fire`),
never with `server._combat(...)` beside the step: the server refuses a shot whose view disagrees.

A test that is the server (a kill, a purchase, a blow, a repair made with `rules.apply`) is heard by the server's own
listeners (the tallies) and by no client unless its events are sent on: `room._collect(rules.apply(action))`
(`NightHost._collect`). Compare a client's count only after the client has heard the event.

- **Approach:** Send every event list the server produces, for a request and for a tick, to the clients, and test a path
  with no request in it (a reload that finishes on its own). **Watch out for:** only the answers to a client's request
  were sent back, so points rose but the target stayed standing and no burst showed after a lobbed shot: a projectile
  bursting, a reload finishing or a round ending happen inside the server's tick. **Seen:** Deadnight, 2026-11-01
  (fix: both lists are sent; a test of a path that has no request).
- **Approach:** Drive a test client by its command: connect `ticked` to `link.send(command.to_dict())`, keep one
  `NightCommand` per client and aim and fire it as the player's input does (`aim_along`, `fire`), never call the combat
  server by hand. **Watch out for:** the night server waits for each player's command and answers with the tick's
  events, so a client that sent none heard only `zombie_spawn_requested`, and a shot made beside the step had an origin
  the server refuses. **Seen:** Deadnight, 2026-11-03 (fix: the two-client test sends a command every tick).
- **Approach:** Deliver an event a test makes itself as the link would (`night.state.apply_events(rules.apply(action))`
  in one process, `room._collect(rules.apply(action))` online), run one tick, and wait on the client's state, never on
  the call. **Watch out for:** the server returns only the events of its own `apply` and `step`, so a call made beside
  it is in no client's stream: the HUD read "NEED 350 POINTS" with 600, the clients' witness stayed at 0 kills while
  the server was in round 2, and the loopback link delivers on `pump()`, so `night.state.over` read false until a tick.
  **Seen:** Deadnight, 2026-11-01 (HUD); Deadnight, 2026-11-04 (loopback); Deadnight #1074, 2026-11-05 (clients).
- **Approach:** Send an event that names a thing before the event that announces it (`NightHost._name_seat` before the
  `JOIN`), and when a change adds data to an existing flow list every text built from the earlier event; when a test
  waits for a string that never appears, print what the notice list did hold. **Watch out for:** `player_added` and
  `player_named` went in one tick, so the notice read `PLAYER 3 JOINED` and later `CY LEFT`, and a test that waited for
  `PLAYER 3 LEFT` suggested a lost event where the product was inconsistent. **Seen:** Deadnight #542, 2026-11-02 (fix:
  the name goes first and the test asserts names).

## A room test that needs a map or a fast round {#a-room-test-that-needs-a-map-or-a-fast-round}

A ticket's map is kept only when the host's level opens it, so name a host level (`TicketMaker.make(..., settings, 12,
seat)` opens the back rooms at 10) and assert `room.server.rules.settings.map` first. The count multiplier is also the
speed of the spawns: below 1 a round is smaller and the dead come that many times as slowly (0.25: four times), above 1
they come faster. A test about many rounds takes 0.25; a test about seconds takes 2.
The spawn clock is the real cost of a round, not the play: at the shipped tuning a round of a night at 0.25 waits 13 s
for each dead. A room test that plays rounds shortens it in its own copy of the tuning
(`rounds.first_spawn_delay = 0.1`, `spawn_interval_start = 0.1`, `spawn_interval_min = 0.05`); Deadnight #1074's
online suite of 11 cases went from 270 s to 23 s that way, with the same checks, and a shard fails at 80% of its
time limit.

## Act on a rules event where the rules say it, not in the list a step returns (Deadnight #1059) {#rules-events}

`NightServer.step` returns the events of that tick, but a rules event can also be made by an `apply` between steps, by a
bot's buy, or by a test that calls the rules directly, and those land in the outbox the host has already taken. A host
that waits for `round_ended` in the step's list to post a report misses the round that ended outside the step, and the
report never goes. Hook the rules' own signal (`GameRules.event_emitted`, which `NightServer._on_rules_event` already
listens to) and keep what is owed (`XpAward.take_due`); the host asks after each step and posts what is due.

## What the last event of a night makes {#what-the-last-event-of-a-night-makes}

Once the rules say the match is over, `NightServer.step` runs `_step_over` (a frame and the intermission's clock) and
nothing else, so whatever the end made has to be handed out there. A stat that is counted at `game_over` or by the
last down (*Dead on arrival*, *Standing room only*, a night count) finishes challenges in that same event; their events
(`ChallengeAward.take_events()`) wait for the next `apply`, and a client with its player down sends none (Deadnight
1172: the board held the number and no client heard it). `_step_over` drains them. Test a night's end as *told*: wait
for `challenge_done` on a client after `game_over`, not only for the board's number.

## An end the server owns: intermission and return (Deadnight #973) {#server-owned-end}

The end of a match is a state of the server, not of each client, or no two screens agree on the second:

- **Freeze, count, say once.** When the rules say the match is over the server stops stepping the world (bodies,
  enemies, rules) and only counts the intermission, putting the whole seconds left in every frame (`-1` while the match
  is on, so it costs a match in play nothing) and sending one `night_closed` event at 0. A client counts by that number.
- **The client stays through it.** Leaving the seat at the game over (to avoid an unread socket) made the screens
  diverge and left nothing to show; reading the frames costs nothing when the world is still, and a client that is
  sent no commands cannot move. It closes its link at the event or when its player presses Leave. The room waits a
  short grace for the rest and hangs up on them.
- **A frame that says the match is over also covers a late arrival** (a seat taken during the intermission heard no
  `game_over`).
- **The return is the backend's to remember.** The game server tells the backend the match *finished* and which users
  were still present; the backend reopens the same lobby (code, host, settings) for them instead of dropping it. A
  match that ended any other way (everyone left, a crash) still drops it. A client asks for its lobby until it reads
  `open`, because it may ask before the game server's call has landed.
- **Test it over real sockets** with the real backend and a leaver: clocks within a second of each other, the room freed,
  the lobby open again with the host's rules, a host who left replaced, and a night everyone left not reopened.

## A player's way in and out of a room {#player-states}

<!-- new section: the room sections cover the transport and the protocol; none lists the states a player passes
through, the ways in and out, or what is kept for a seat -->

- **Approach:** For any multiplayer flow, list every state a player can be in (alone, with friends, started, late, full,
  host gone, tab closed) from the player's view before building, test each with two or more real clients on the real
  stack, and run a new screen once in the web build against the real backend. **Watch out for:** creating a night was
  create then start, so the waiting room, who is in it and who starts were never designed: no screen showed the members,
  a closed tab never left, and the first lobby screen reused a covered screen's requests, which never answered.
  **Seen:** Deadnight #515, 2026-11-02 (fix: Deadnight #521, #537 and #555: a node's network requests live and die with
  its parent's `process_mode`, so a screen that keeps asking while on top owns its own request nodes under itself).
- **Approach:** Erase state kept by player id in a second place where the rules erase the player, and test a seat given
  up and taken again; walk a "did not arrive" report from every source with both lists side by side, and say which
  source the walk could not reach. **Watch out for:** leaving erased the rules' player but not the combat server's
  loadout, and the room gives the lowest free id to the next person, who carried the last one's weapons while the rules
  said the start weapon only. **Seen:** Deadnight #904, 2026-11-03 (fix: the combat server forgets a player on
  the rules' `player_removed`; `test_weapon_sources.gd` walks every weapon through every carry and a seat given up and
  taken again, and failed first with `pistol, mp5`; a source the walk cannot reach is named in the report).
- **Approach:** For any "you are already in X" refusal, list every way the system puts a player into X and every way out
  from the player's view (button, menu, closed tab, dropped connection, night ended, Activity closed), test each over
  the real stack with bots in, and prefer moving the player to refusing them. **Watch out for:** a finished night's
  reopen put its users back in the one-open-lobby index, an entry they never made, so a player at the menu was refused
  by a lobby they could not see for ten minutes. **Seen:** Deadnight #1177, 2026-11-05 (fix: a failing test for every
  suspect, keeping the ones that fail (bots were innocent); create, join and quick join move a player out of the old
  lobby, an empty or unread reopened one is dropped, both exits of a night say `leave`; [Netcode](../../../gamedev/netcode.md#leaving)).

## A feature that crosses services {#across-services}

<!-- new section: the page covers the client and the game server; nothing covered a change that also needs the
backend deployed -->

- **Approach:** Call a feature that crosses services (client, backend, game server) done only when every service it
  crosses is deployed by the pipeline that merges it, with one test per setting through the real stack, read back from
  the running night. **Watch out for:** the backend had no deploy job, so the live one predated the lobby rules,
  answered a rules change with a bare 404 and ignored a start's settings; every test ran a backend built from the
  checkout. **Seen:** Deadnight #944, 2026-11-04 (fix: the deploy compares the live service's settings keys with the
  client's, and an unknown key is refused by name at every border; `deploy-backend` joined the pipeline and one test per
  setting reads the value back from the running night).
