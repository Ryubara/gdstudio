# What to plan from the start

A checklist for the first day of the next GDStudio game. Every line is a gap that Deadnight's maintainer or its own
work exposed and that nobody planned for at the start; each links to the row, lesson or issue that taught it. Where a
cause is still being found, the line says "known gap, cause pending" with its issue.

Keep it current: each new row on [What the maintainer caught](maintainer-corrections.md) adds or updates a line here.

## Design, feel and the reference {#design-feel-and-the-reference}

- Plan: the reference game's core loop, variety beats (bosses, special rounds, enemy types) and numbers (movement,
  tiers, economy), collected and cited before tuning ([row](corrections-log/corrections.md)).
- Plan: the genre's controller conventions (hip fire turns the body, sprint any way unless aiming, hold to interact)
  listed before the controller is built ([row](corrections-log/found-by-playing.md)).
- Plan: for every state (turning, reloading, swapping) and action (fire), whether the action leaves, waits or cancels;
  the shot waits for the body's turn
  ([controller states](../gamedev/controller.md#states)).
- Plan: a rule that follows from a state (empty, downed) is evaluated from that state on the server each tick, never
  as a side effect of an action a control can stop sending ([States and actions](../gamedev/controller.md#states)).
- Plan: a bot sends a person's command (it looks where it acts and moves under that view), so a rule on the view holds
  it as it holds a person ([Bots](../gamedev/bots.md)).
- Plan: one camera input per behaviour the maintainer names; aim zoom only from the aim button.
- Plan: a reference camera, tuned (framing, damping, interpolation, FOV as a number) before content.
- Plan: for a game camera, which node owns each framing value and who may write it (distance on the rig, the shoulder on
  the Camera node's own H and V Offset, nothing else writing them, the addon's host copy included), and one test that
  sweeps the camera's yaw with every zoom held to prove the lens never nears the head
  ([row](corrections-log/caught-by-checks.md)).
- Plan: a feel pass per verb (shake, kick, flash, hit feedback), each effect measured on screen from the player's
  camera.
- Plan: a setting that scales a quantity keeps the pace: a test that each round lasts about as long at 1x, 2x, 3x
  ([Settings that scale the game](../gamedev/design.md#settings)).
- Plan: the HUD element by element, read in half a second, captured at 720p, 1080p, 1440p and in the browser.
- Plan: one written order and spacing for anything shown together on several screens (a player's icon, level
  and name), set once and shared by every screen ([row](corrections-log/caught-by-checks.md)).
- Plan: for an identity feature, every place a name is drawn, found by searching the code and listed in the issue, the
  HUD's own player boxes first ([row](corrections-log/caught-by-checks.md)).
- Plan: the genre's feature list as players know it, checked against the issues before the first playtest: a
  character choice and its voice, the full set of perks (own names, close in meaning), weapon slot keys and
  silhouettes, a grenade's fuse beep and weight, a reload you notice, the player count; in Deadnight each arrived
  as a request after play (#678, #679, #687, #682, #680, #683, #690)
  ([row](corrections-log/found-by-playing.md)).

## Input {#input}

- Plan: every device class the game ships on (keyboard and mouse, gamepad on any device id, touch), each played on
  every platform ([row](corrections-log/found-by-playing.md)).
- Plan: pointer lock and Esc on the web: pause on lock loss, nothing fires while unlocked
  ([web export](../engines/godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night)).
- Plan: pause on a pad's Start as the first press, in the build players use; a button shared with a `ui_*` action
  is tested on a screen with no focus.
- Plan: a gamepad inside an embedded iframe (the Discord Activity) needs the focus: prompt one click
  ([web export](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: touch proved in a phone-emulated browser; a finger is also a mouse motion in the web runtime
  ([web export](../engines/godot/web-export.md#phone-touch-and-fit)).
- Plan: multi-touch with two thumbs at once, and hold buttons (aim) that also drag to look; per-finger positions,
  never `relative` ([touch controls](../engines/godot/ui-controls.md#touch-controls)).
- Plan: touch designed as its own interface before its first button: every action and every element on the screen for
  that device gets a verdict (keep, make the existing element tappable, drop as a duplicate), and rules the player
  expects everywhere (reload at 0) are proved through each device's real input path.
- Plan: a touch action is listed by what it does, derived from one table, not by an allow-list: every button looks while
  dragged unless its row owns the drag, so a new one cannot opt out unseen
  ([row](corrections-log/found-by-playing.md)).
- Plan: every input edge counted once per physics tick by the game, not by `is_action_just_pressed`.

## Platforms {#platforms}

- Plan: one opening screen everywhere, the main menu, the Discord Activity included; a platform shortcut is the
  maintainer's call ([row](corrections-log/found-by-playing.md)).
- Plan: a platform differs from the website only in sign-in and chrome: list every branch on the platform (an instance
  id, the Discord host) in the first build and keep none that changes what a press does; players reach each other by
  a code, a link or a list, never by a platform identity
  ([web export](../engines/godot/web-export.md#activity-same-game),
  [deadnight #1178](https://github.com/Ryubara/deadnight/issues/1178)).
- Plan: player identity and display names per platform (Discord nickname, a guest name prompt, Steam later)
  (known gap, [deadnight #485](https://github.com/Ryubara/deadnight/issues/485)).
- Plan: store, key-art and Discord asset sizes listed with the first art pass, portrait crops framed with their own
  lens ([key art](../tools/blender/key-art.md#title-art-and-store-sizes),
  [deadnight #492](https://github.com/Ryubara/deadnight/issues/492)).
- Plan: the Activity stood in locally (mapping prefix, gzip, iframe focus) before the maintainer tries it
  ([web export](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: a layout rule for a device class (phone, tablet, desktop window) takes its input in what the person holds (CSS
  pixels on the web, never the canvas's device pixels), has a test for each class, and is run once on the real page (the
  web export in phone emulation, and in an iframe for Discord) before a phone capture is trusted; a menu's smallest
  text and tap target are measured in CSS pixels on every screen
  ([web export](../engines/godot/web-export.md#a-phone-pages-size-the-canvas-is-not-the-page),
  [deadnight #1197](https://github.com/Ryubara/deadnight/issues/1197)).
- Plan: list the browser abilities each embed grants (focus, gamepad, pointer lock, clipboard, autoplay, fullscreen) and
  probe each inside the Activity frame with Discord's policy before shipping
  ([web export](../engines/godot/web-export.md#discord-activity-copy-and-paste-in-the-frame)).
- Plan: every text field is opened, typed in, closed and submitted with a finger on a phone-shaped page (the export's
  virtual keyboard option on, the field kept above the keyboard, a keypad for a code) before a flow that needs text
  is called done ([web export](../engines/godot/web-export.md#a-phones-keyboard-in-the-web-build),
  [keyboard](../engines/godot/web-export.md#a-phones-keyboard-in-the-web-build)).
- Plan: a visible pre-game lobby (members, host, a start the host controls) and mid-match join, every player state
  designed and tested with real clients ([row](corrections-log/found-by-playing.md)).
- Plan: rooms, invite links and codes on player-facing screens, never an address or `localhost`
  ([row](corrections-log/found-by-playing.md)).
- Plan: a performance budget per platform (desktop, browser, server), never one cap for all
  ([performance budgets](../engines/godot/performance-budgets.md#the-rule)).

## Netcode {#netcode}

- Plan: test every closed loop (prediction, interpolation, rate limits) at the worst shipped round trip (300 ms and
  more) with a push, and with the client's own thread frozen (0.5, 2, 5 s) over the real socket, not only steady lag
  ([multiplayer](../engines/godot/multiplayer.md#a-client-that-freezes-measured-on-the-live-server),
  [deadnight #483](https://github.com/Ryubara/deadnight/issues/483)).
- Plan: that test is a gate with thresholds in CI from the first predicting client (native and the web build through a
  relay, frozen, with a teeth run that breaks the reconciler and the server's hold), not a measurement in a pull
  request ([the bad-network gate](../engines/godot/third-person/online-client.md#bad-network-gate)).
- Plan: protocol and snapshot version bumps that collide across branches: bump past main right before the last push
  ([netcode](../gamedev/netcode.md#parallel-branches)).
- Plan: deploy skew between the web build and the game server: wait for the same commit
  ([railway](railway.md#skew)).
- Plan: never deploy a branch to the shared web service; a CI deploy of main replaces it anyway
  ([deadnight #491](https://github.com/Ryubara/deadnight/issues/491),
  [web export](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: events the server causes alone reach every client
  ([multiplayer](../engines/godot/multiplayer.md#events-reach-a-client-only-through-its-command-loop)).
- Plan: appearance and bodies replicated from one owner, the same scene local and remote
  ([row](corrections-log/found-by-playing.md)).
- Plan: every player feature is specified and tested from another player's view: a two-client test over the real
  socket for what the other screen shows, and captures from the second client's screen
  ([multiplayer](../engines/godot/multiplayer.md#appearance),
  [deadnight #518](https://github.com/Ryubara/deadnight/issues/518)).
- Plan: where a player is (menu, waiting room, night, away, reopened lobby) and what ends each state, written as one
  table of states and ways out before the lobby is built; a player moves between lobbies by creating or joining
  (never a refusal for being in another), and a lobby with no person is gone at once, with the game server saying
  when a seat is empty ([row](corrections-log/found-by-playing.md),
  [multiplayer](../engines/godot/multiplayer.md#player-states), [netcode](../gamedev/netcode.md#leaving)).

## Saving {#saving}

- Plan: hold menu choices in one draft, preview the draft, and commit once on leaving; no other view rereads saved
  state while the screen is open.
- Plan: a test for every choice against another choice, a tab change and a reload, counting writes.
- Plan: tests point the settings and save files away from the player's own `user://`
  ([Throwaway user folder](../engines/godot/throwaway-user-folder.md#tests)).

## Co-op rules {#co-op-rules}

- Plan: downs, revives and the scoreboard designed together
  ([deadnight #472](https://github.com/Ryubara/deadnight/issues/472),
  [deadnight #486](https://github.com/Ryubara/deadnight/issues/486)).
- Plan: whether bots fill player slots, researched before the systems they use
  ([row](corrections-log/corrections.md)).

## Content: weapons, art and animation {#content-weapons-art-and-animation}

- Plan: a roster table (model, definition, source, numbers) with a test that every weapon can be obtained
  ([A weapon is a model, a definition and a source](../gamedev/balance.md#roster)).
- Plan: every catalogue entry played through in the real night with the real input
  ([Every catalogue entry](../gamedev/testing.md#catalogue)).
- Plan: weapons sized against the hand that holds them, not only the body
  ([Hands on the weapon](../tools/blender/weapons.md#hands-on-the-weapon)).
- Plan: hand sockets on every held model and a solved grip, with skin-against-weapon contact tested in every pose;
  the kit's clips never move the fingers ([Hands on the weapon](../tools/blender/weapons.md#hands-on-the-weapon)).
- Plan: what each body layer plays in every movement state (walk, sprint, crouch, air)
  ([One action state for every body](../engines/godot/animation-tree.md#one-action-state-for-every-body)).
- Plan: an animation for every interaction, and clip speeds measured before blend points
  ([Gait follows speed](../engines/godot/crowds.md#gait-follows-speed)).
- Plan: kit props and materials on the map as soon as the layout holds
  ([row](corrections-log/corrections.md)).
- Plan: a map design review before a map ships and after its layout changes, run as a level designer from the
  player's camera: loops and kiting space, chokepoints, spawns, pacing of the doors, landmarks, lighting, and every
  out-of-bounds and door-skip candidate proven by movement, not by eye; Deadnight's two maps were first reviewed after
  more than a hundred pull requests (#833; [checklist](../engines/godot/map-review.md)).

## Audio {#audio}

- Plan: loudness, first-50 ms energy and pitch spread measured from a recording of the real service
  ([close and powerful sounds](../engines/godot/audio.md#close-and-powerful-sounds)).
- Plan: voice lines written as a person speaking, with many takes per event
  ([writing the lines](../gamedev/audio/voice-lines.md#2-writing-the-lines)).
- Plan: no sound design in bus effects, which the web build ignores
  ([audio](../engines/godot/audio.md#web-samples-or-streams)).

## Performance {#performance}

- Plan: first-use hitches: warm up every effect, enemy and shader behind a loading screen
  ([first-use hitches](../engines/godot/first-use-hitches.md)).
- Plan: web spikes on shot and kill: no allocation per event, short sounds decoded at load
  ([starting sounds](../engines/godot/audio.md#starting-sounds)).
- Plan: performance from the first playable night, not after a lag report: one command for the worst case (latest
  round, most players, strongest intensity setting, platform ceiling), a sampler of counts and labelled times, a budget
  file held in CI (counts tight, time as a ratio of a calibration loop), and a page of per-system limits with what the
  game does past each. Deadnight had measured the web build and a bare crowd, never its own worst night, and a
  maintainer
  found the lag first ([performance budgets](../engines/godot/performance-budgets.md#the-rule),
  [row](corrections-log/found-by-playing.md)).

## Test infrastructure {#test-infrastructure}

- Plan: agent launches are silent, unfocused and cursor-free from day one, one wrapper for each (`gds godot` mutes with
  `--audio-driver Dummy`, `gds quiet` sets `GDS_QUIET=1` and every probe launch adds `--mute-audio`)
  ([sound](../engines/godot/no-focus.md#sound)).
- Plan: quiet runs for anything that can take the mouse, Godot or browser
  ([browser probes](../engines/godot/web-probes.md#running)).
- Plan: one shared start helper for every browser probe, so a menu change cannot break them
  ([browser probes](../engines/godot/web-export.md#browser-probes)).
- Plan: a screen's first running frame tested through every route into it (solo, join, resume, the Activity)
  ([ui controls](../engines/godot/ui-controls.md#a-menu-over-a-live-game)).
- Plan: no flaky exit-leak checks to stall the queue: disconnect test lambdas
  ([lesson](../engines/godot/test-exit-leaks.md#what-a-test-leaves-alive)).
- Plan: one-tick flags latched per physics tick, and motion bounded per tick, not per frame.
- Plan: suites clear the UI router and every wait loop has a bound
  ([Testing a game](../gamedev/testing.md#leftover-state), [waits](../gamedev/testing.md#bounded-waits)).
- Plan: captures and recordings from the player's camera, with the real devices switched off.

## Process {#process}

- Plan: land old PRs before new ones, reporting from the oldest down
  ([Landing](landing.md#landing)).
- Plan: rerun known flakes at once and push only what a merge needs
  ([Landing](landing.md#merging-main-into-a-pull-request)).
- Plan: a fix is done when it is live where the maintainer plays (deployed commit named, probe run on the live URL)
  ([row](corrections-log/corrections.md)).
- Plan: local main checkouts fast-forwarded after every merge, by a hook
  ([Hooks](hooks.md#mains)).
- Plan: a stopgap comment names its issue ("until #N"), and closing #N greps for it and resolves it
  ([Starting work](starting-work.md#stopping-and-finishing)).
- Plan: the PR that finishes a split issue carries `Fixes #N`
  ([Starting work](starting-work.md#stopping-and-finishing)).
- Plan: load tests capped on the shared machine (four suites, stop by PID, a timeout on every long command)
  ([A shared machine](workspace.md#shared-machine)).
- Plan: the disk is watched from day one: a guard that frees finished worktrees, idle import caches and scratch
  downloads past their pull request below a soft limit, refuses new agents below a hard one, and names the folders over
  budget; captures and CI artifacts are reduced to what is kept in the same task
  ([The disk guard](workspace.md#disk)).
- Plan: worktrees always take absolute paths, and agent roster changes reach every game with `gds sync`
  ([The shell](shell.md#paths),
  [what went wrong](building-games-with-agents.md#what-went-wrong)).
- Plan: every kit file a game carries a copy of (the checker, the pre-commit message hooks, the agent definitions) is on
  the `gds sync` list from the first game, so a rule changed in the kit reaches the games in one sync pull request
  ([Sync](sync.md#pre-commit-blocks)).
- Plan: issue order and ownership are enforced by a tool from day one: work starts only through `gds issue start`
  (oldest ready issues first, a pull request counts as in progress), and a task agent's prompt names its started issue
  ([Starting work](starting-work.md#the-rule)).
- Plan: a coordinator's owner map is checked against `gh pr list` every time it is re-armed, and `gds issue list` is
  read for issues in progress with no owner ([row](corrections-log/found-by-playing.md)).
- Plan: every fix pull request names the kit doc it updates, the agent that finds a mistake writes its lesson (with
  `areas:`) and opens the kit pull request in the same task, and agents read the checks of their issue's areas before
  they start ([Hooks](hooks.md#docs)).
- Plan: the coordinator names the doc sections each task agent reads in its prompt when it dispatches it (`gds brief`,
  `Read:` lines the Agent guard checks), and the agent's report says what it read and what was missing; no category
  of lessons is pushed at every agent of an area ([Starting an agent](starting-work.md#starting-an-agent)).
- Plan: hit feedback is part of the first weapon: what a hit does to the body (blood or an impact), marks it leaves,
  hit markers and sounds, each in the warm-up and measured on the web build
  ([row](corrections-log/found-by-playing.md), [Shot feedback](../engines/godot/shot-feedback.md#blood)).
- Plan: the coordinator lands what it would recommend; the only merges that wait are `S-hold` and the maintainer
  decisions
  in `AGENTS.md` ([row](corrections-log/found-by-playing.md)).
- Plan: every end step a tool leaves for the maintainer is asked whether it is a real per-game choice or the same every
  time; the second kind becomes a default the agent runs (a new game's GitHub repository, Pages, ruleset, hold sweep and
  an MIT licence, gdstudio #779) ([row](corrections-log/corrections.md)).
- Plan: the docs record what the maintainer decided or pointed out in our words, with the issue or pull request and the
  date, never the prompt; a check fails a corrections row that starts with a quotation mark (gdstudio #780)
  ([row](corrections-log/corrections.md)).
- Plan: a pause of a repository, like every standing rule the maintainer gives, lives from the first day in a file
  the tools read (`paused` in `workspace.toml`), so `gds issue start`, `gds issue list` and the `Stop` hook stop
  offering its issues ([row](corrections-log/corrections.md),
  [Starting work: pausing a game](starting-work.md#paused)).
- Plan: a docs site's navigation is designed for the page count it will reach (a tab per topic, sections that fold
  and nest, `navigation.prune`, an order per folder), and a site change is judged by captures of its built sidebar at
  desktop and phone width, not by its build warnings (gdstudio #790)
  ([row](corrections-log/corrections.md),
  [Docs site: the navigation](docs-site.md#nav)).

## Start of a new game {#start-of-a-new-game}

<!-- new section: the first-day checklist sat on the corrections page, which turns into a log of where each rule
lives (#769); its home is this page, beside the plan it summarises -->

The short list to read on the first day of a new game, by subject; the lines above give the cause of each.

### Feel and camera {#feel-and-camera}

- Name the reference camera and tune it (framing, damping, render interpolation, aim and sprint transitions) first.
- Look at the game from the player's view every day, not only through tests.

### Movement and numbers against the reference {#movement-and-numbers-against-the-reference}

- Collect the reference game's numbers (movement, enemy tiers by round, damage, economy) and cite them.
- Build the balance simulator on the real weapons and tuning, with a gate in CI.

### HUD at real resolutions {#hud-at-real-resolutions}

- Capture every HUD change at 720p, 1080p, 1440p and in the browser; test alignment and overflow.
- One place per number; transient panels for slow progress.

### Art beyond the greybox early {#art-beyond-the-greybox-early}

- Inventory the starter kit against the design; plan the missing content.
- Materials and kit props on the map as soon as the layout holds.

### Animation for every interaction {#animation-for-every-interaction}

- Each interaction (repair, buy, revive, tear) ships with its actor clip and object motion.
- Locomotion rate follows the actor's speed; clip ground speeds are measured, not guessed.
- Held items are checked against the hands, the shoulder and the aim ray.
- A state that changes a pose (aim, sprint, crouch) reaches it through one eased weight; nothing in the pose flips
  on a bool.

### Every input device {#every-input-device}

- Play every build for ten minutes with a mouse and keyboard and with a gamepad, in the editor and in the browser,
  before calling a feature done.

- Touch controls (landscape, safe areas, no browser scroll or zoom) planned with the first playable build when the
  game ships in a browser or Discord.

### AI teammates {#ai-teammates}

- Decide whether bots fill player slots; if so, research them (perception, aim, movement, economy, revives) first.

### Testing and recordings {#testing-and-recordings}

- Every feature names its proof; every visual PR carries before/after captures.
- Recordings use the player's camera.
- Every catalogue entry (weapon, item, perk) is played through in the real game with the real input before it
  counts as done; tests never assert a stand-in as the expected result, and a shipped gap is reported to the maintainer.
- Captures drive the game's real path and switch off the real devices' input.

### Process on a shared machine {#process-on-a-shared-machine}

- Cap load tests, stop processes by PID, time out long commands, and warn neighbouring projects first.

### First use {#first-use}

- Load and draw every enemy, weapon, effect and light state once behind a loading screen; keep the materials of
  short-lived effects alive.
- A browser run with a fresh profile that counts programs linked after the loading screen is the gate (zero).

### Hosting {#hosting}

- A playable web build is live from the first playable night and redeploys on merge.
- Before an online feature is called playable, walk the flow a stranger takes in the browser and in Discord: rooms, an
  invite link or a code, never a server address or `localhost` on a player-facing screen.
