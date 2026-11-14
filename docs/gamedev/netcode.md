# Netcode: what holds in any engine

<!-- new section: gamedev listed netcode as belonging here but held no page; the Godot multiplayer page holds the
engine's API and the first spike, nothing held the rules about facts, limits, capacity and branches that are not
engine specific -->

Rules for a server-authoritative game that a client reaches over a socket and a platform backend that sits beside it.
The Godot API and the protocol the spike chose are on [Multiplayer in Godot](../engines/godot/multiplayer.md); the
backend side is [Platform backend](backend.md); where the services run is [Railway](../studio/railway.md). Each entry
says where it was learned (Deadnight, the first game).

## One owner for each fact {#one-owner}

<!-- new section: nothing covered how the parts of a server (rules, combat, stores) keep one fact between them -->

- **Approach:** Ask the owner of a fact when you need it (`GameRules.has_zombie`) instead of mirroring it from the
  events you saw, and give state only one server owns its own `to_dict`/`from_dict`/bytes with a version, restored
  after the rules. **Watch out for:** a grenade server mirrored the zombie list from spawn events, so one made
  mid-game, or after a snapshot restore, ignored every zombie already alive, and its cooks and grenades in flight were
  gone after a restore. **Seen:** Deadnight, 2026-11-01 (fix: the owner is asked, the state is saved and restored with
  its own version; a test makes the server after the zombies exist).
- **Approach:** When two parts name one thing differently (the shop's `weapon_shotgun`, the catalogue's `shotgun`),
  translate in one function, used in the one place that hands it over, and test the end state: buy through the rules
  and ask the combat server what is carried. **Watch out for:** the combat server answered `unknown_weapon`, an event the
  night filters out, so a bought weapon never reached the player and nothing failed. **Seen:** Deadnight, 2026-11-01
  (fix: `WeaponCatalog.catalog_id` and the purchase test).

## What a client may send {#client-input}

<!-- new section: nothing covered checks on the packets a client sends -->

- **Approach:** Refuse non-finite numbers where they enter (`Vector3.is_finite()`), and make a pure function of a
  distance answer "no effect" for `not is_finite(distance)` before any `maxf`/`minf`. **Watch out for:** in Godot 4.7
  `maxf(NaN - radius, 0.0)` answers 0.0, so a grenade cooked with a NaN hand position blew up for full damage on a
  zombie beside the player, and every comparison with NaN is false, so `distance >= radius` guards fall through.
  **Seen:** Deadnight, 2026-11-01 (fix: input is refused at the border and the blast function answers no effect).
- **Approach:** Make a check that drops a packet say so (a counter while developing, a log line with the reason in
  production), derive each minimum length from the layout comment, and give a limit the longest message that can fill
  it. **Watch out for:** a decoder asked for 9 bytes of an 8-byte welcome and dropped every valid one with no message;
  a hello limited to 1024 bytes dropped a ticket grown past it as `SILENT`, so one account (the one with the most
  progress) never got in while every fresh-guest probe passed. **Seen:** Deadnight, 2026-11-01 (length guard);
  Deadnight #1366, 2026-11-06 (fix: the limit holds the longest ticket the backend signs, 23.4 KB, a backend test reads
  it from the game's source, and the refusal is logged).

## One number, one place {#limits}

<!-- new section: nothing covered a limit that several parts of a system copy -->

- **Approach:** When a game constant is mirrored in another service, put its name in a comment on both sides, search
  the other side for the old number in the same pull request, read it through one shared parser, and run the
  real-socket suite (not only each side's unit tests) when a merge brings a new ceiling. **Watch out for:** the backend
  held its own `MAX_ALIVE = 40` after the game raised its cap to 120 and refused every larger value as `bad_settings`;
  JSON has one kind of number, so the backend's `12.0` was refused by the game's strict parser and a lobby read back as
  the usual rules. **Seen:** Deadnight #559, 2026-11-02 (fix: the bound was raised with the game's and
  `MatchSettings.from_json` reads what the backend sends; `test_lobby_online` found the float case).
- **Approach:** Before changing a count (seats, bots), `grep` code, tests and fixtures for the literal and for every `%`
  over a list; make one constant and pin the others to it by a test, and check that each list indexed by the count has
  that many rows. **Watch out for:** the seat limit lived in eleven places, and `markers[index % markers.size()]` put
  the fifth player on the first one's spot and shared three bot names among seven bots without an error. **Seen:**
  Deadnight #690, 2026-11-03 (fix: `test_night_bots.gd` pins the seat constants, `test_player_spawns.gd` checks the
  rows, a hue-gap test was rewritten for the new count).

## Capacity {#capacity}

<!-- new section: nothing covered sizing the rooms of a game server -->

- **Approach:** Bench the process, not a room (K rooms each in a `SubViewport`, all stepped in one frame; read p95 and
  the ticks over budget), size rooms and caps from the worst load they allow, and rerun it whenever a seat, bot or
  crowd cap moves, with the new kind of body run as the host runs it. **Watch out for:** `ROOM_CAPACITY` 4 came from one
  room benched alone, but rooms run one after the other in one thread and their heavy ticks fell on the same frame;
  3 rooms sized for 8 people took 26.6 to 28.8 ms of a 16.7 ms tick once 7 bots each were allowed. **Seen:** Deadnight,
  2026-11-02 (rooms); Deadnight #1193, 2026-11-05 (fix: `crowd_server_bench.tscn --rooms=K --bots=N`, heavy ticks
  alternated by room, the old setting run beside the new one in one container, interleaved, three times).
- **Approach:** Put a probe on each piece before choosing what to cut, and give a fix that must not change behaviour a
  hash of the behaviour, run with the fix on and off in one process. **Watch out for:** a room with a bot cost 1.28
  times a room without and the frame was blamed; the cost was `use_target` asked twice for every body every tick (30
  asks a step, nearly all answering `{}`). **Seen:** Deadnight, 2026-11-05 (fix: a flat bound `UseSites` makes the
  answer `{}` without the walk; a hash of every command every bot sent was equal with it on and off; 14.6 to 10.6 ms).
- **Approach:** Test a table of who counts toward a ceiling for every kind of seat (person local, person remote, bot)
  and every change of seat. **Watch out for:** a hosted bot fell into the "remote" branch of `is browser` and cut a
  desktop crowd from 120 to 40; found by a profile run, not a test. **Seen:** Deadnight, 2026-11-04 (fix: a bot's seat
  is never registered, a person taking a bot's seat registers as a browser until it says otherwise).

## Who is in a room {#leaving}

<!-- new section: the Godot page lists a player's states; nothing covered what a connection event means -->

- **Approach:** Before deriving "the player chose to leave" from a closed socket, list every reason the client closes
  its own link (the night ended, a screen left, a page went away, an error) and test the normal end of the flow with
  the clients doing what the real screen does. **Watch out for:** the client closes its link on `night_closed`, so
  after the intermission every socket closed "on purpose", the room dropped them all from the list of who returns, and
  the reopened lobby had nobody. **Seen:** Deadnight #1177, 2026-11-05 (fix: the room keeps who was there when the
  night closed (`returning`) and edits it no more; an unread reopened lobby is dropped after a minute).
- **Approach:** When a second source starts reporting a fact an existing request carries, find the tests that assert the
  request's own answer and make them assert the end state; say in the docs which source covers which path. **Watch out
  for:** the client's `leave` and the game server's `/left` reach the backend over two connections in no order, so the
  second answered `not_member` and an older test that asserted the first failed; each covers a path the other cannot
  (a button the server cannot see, a closed tab the client cannot send). **Seen:** Deadnight #1177, 2026-11-05 (fix:
  the second is a no-op that names the end state; the test accepts either answer).

## Branches that share the net files {#parallel-branches}

<!-- new section: nothing covered several open pull requests changing the protocol and its data paths -->

- **Approach:** When a branch changes a serialized layout or the protocol version, merge `origin/main` right before the
  last push and bump past the highest number any open pull request names; check the version before any keys, and keep
  a test with a snapshot from each older layout that must answer `bad_version`. **Watch out for:** two pull requests
  each bumped `SNAPSHOT_VERSION` 3 to 4 and merged cleanly because the edit was identical, so one number named two
  layouts; `NetWire.VERSION` collided three ways in an afternoon. **Seen:** Deadnight #449, 2026-11-01 (snapshot);
  Deadnight #518, 2026-11-02 (protocol, with #472, #54, #57).
- **Approach:** Before building a data path in shared net files, `gh pr list` the open pull requests that touch them and
  read their diffs; where one owns the data, build only the consumer and say so in the issue. **Watch out for:** an
  issue said "the level comes from the ticket", so a pull request built the whole path (host, WELCOME, a new event, a
  version bump) while the XP tally's pull request landed its own; main's files replaced most of it. **Seen:** Deadnight
  #1115, 2026-11-04 (fix: main's files were taken for the server and protocol, only the HUD, setting and lobby list
  were kept).
- **Approach:** When two issues share an interface, write its exact shape (path, keys, who decides what) in the first
  issue that settles it, or ask the other task's agent for the route and the body, and look at its pull request at each
  milestone. **Watch out for:** the issue bodies named what is sent, not the path, keys or who pays the one-offs, so the
  game side of a report was filled in from guesses and rebuilt when the backend landed. **Seen:** Deadnight #1059,
  2026-11-04 (fix: the report was rebuilt to `POST /internal/matches/:id/report` as #1075 shipped it).
- **Approach:** Treat the command's flag bits as a shared resource: the issue that needs one names the bit it takes,
  a branch checks the open pull requests for bits they already hold before it picks one, and the protocol version is
  raised once per landing, past the highest any open pull request names. When no bit is left, the next protocol
  change widens the flags field first. **Watch out for:** prone took bit 15 and a version bump while the weapon
  presses' branch held bits 11 to 14, so the two were settled only at the merge; after them no flag bit is free.
  **Seen:** gdstudio #1012 (PR #1021) and #887, 2026-11-10
  ([the template's packets](../engines/godot/multiplayer.md#template-packets)); gdstudio #1254, 2026-11-11 (the
  command's byte 13 was spare; it and #1277 both took version 7, so #1254, landing second, took 8); #1420 (entry flag
  bit 7, version 10).
- **Approach:** When you raise the protocol version, search the tests for the old number pinned as a literal
  (`grep -rn "is_equal(<old>)" tests`, the join suite's refusal case) and change it with the bump, before the full
  suite. **Watch out for:** the codec and wire suites read `NetWire.VERSION` and stay green, so the net suites run
  while working passed and only the full template run failed, on `test_net_server_join.gd`'s pinned 6. **Seen:**
  gdstudio #1277, 2026-11-11 (PR #1300); gdstudio #1386, 2026-11-13 (a new command field and export: the field count
  in `test_player_step.gd`, `body_items` in `test_net_args.gd` and the hostile suite's all-0x7F command broke).
- **Approach:** A test that checks a packet's exact size sums the codec's own sizes per item
  (`SnapshotCodec.player_size(entry)`, `event_size(event)`), never a count times a fixed constant, so a layout change
  on main moves the expected number with it. **Watch out for:** the hitscan suite counted `PLAYER_SIZE` for every
  player; once main gave an aiming entry an aim byte, every TICK it checked was one byte over and both cases failed
  only after the branch merged main. **Seen:** gdstudio #1252, 2026-11-11 (PR #1269, after #1300).
