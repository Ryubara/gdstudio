# What to plan from the start

A checklist for the first day of the next GDStudio game. Every line is a gap that Deadnight's maintainer or its own
work exposed and that nobody planned for at the start; each links to the row, lesson or issue that taught it. Where a
cause is still being found, the line says "known gap, cause pending" with its issue.

Keep it current: each new row on [What the maintainer caught](maintainer-corrections.md) adds or updates a line here.

## Design, feel and the reference

- Plan: the reference game's core loop, variety beats (bosses, special rounds, enemy types) and numbers (movement,
  tiers, economy), collected and cited before tuning ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).
- Plan: the genre's controller conventions (hip fire turns the body, sprint any way unless aiming, hold to interact)
  listed before the controller is built ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: for every state (turning, reloading, swapping) and action (fire), whether the action leaves, waits or cancels;
  the shot waits for the body's turn
  ([lesson](../lessons/2026-11-02-hip-fire-shot-before-the-body-turned.md)).
- Plan: a rule that follows from a state (empty, downed) is evaluated from that state on the server each tick, never
  as a side effect of an action a control can stop sending
  ([lesson](../lessons/2026-11-05-a-reload-that-needed-a-trigger-pull-never-ran-on-a-phone.md)).
- Plan: a bot sends a person's command (it looks where it acts and moves under that view), so a rule on the view holds
  it as it holds a person ([lesson](../lessons/2026-11-02-a-rule-on-the-view-held-a-bot-that-looked-where-it-walked.md)).
- Plan: one camera input per behaviour the maintainer names; aim zoom only from the aim button
  ([lesson](../lessons/2026-11-02-a-shared-aim-weight-coupled-hip-fire-to-the-aim-zoom.md)).
- Plan: a reference camera, tuned (framing, damping, interpolation, FOV as a number) before content
  ([lesson](../lessons/2026-11-02-sprint-sway-kept-going-in-the-air.md)).
- Plan: a feel pass per verb (shake, kick, flash, hit feedback), each effect measured on screen from the player's
  camera ([lesson](../lessons/2026-11-02-a-flash-in-the-guns-plane-was-hidden-by-the-gun.md)).
- Plan: a setting that scales a quantity keeps the pace: a test that each round lasts about as long at 1x, 2x, 3x
  ([lesson](../lessons/2026-11-02-a-scaling-setting-needs-a-pace-test.md)).
- Plan: the HUD element by element, read in half a second, captured at 720p, 1080p, 1440p and in the browser
  ([lesson](../lessons/2026-11-01-layout-test-found-hud-overlaps-no-eye-would.md)).
- Plan: one written order and spacing for anything shown together on several screens (a player's icon, level
  and name), set once and shared by every screen ([row](maintainer-corrections.md#done-wrong-first-caught-by-our-own-checks)).
- Plan: for an identity feature, every place a name is drawn, found by searching the code and listed in the issue, the
  HUD's own player boxes first ([row](maintainer-corrections.md#done-wrong-first-caught-by-our-own-checks)).
- Plan: the genre's feature list as players know it, checked against the issues before the first playtest: a
  character choice and its voice, the full set of perks (own names, close in meaning), weapon slot keys and
  silhouettes, a grenade's fuse beep and weight, a reload you notice, the player count; in Deadnight each arrived
  as a request after play (#678, #679, #687, #682, #680, #683, #690)
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).

## Input

- Plan: every device class the game ships on (keyboard and mouse, gamepad on any device id, touch), each played on
  every platform ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: pointer lock and Esc on the web: pause on lock loss, nothing fires while unlocked
  ([web export](../engines/godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night)).
- Plan: pause on a pad's Start as the first press, in the build players use; a button shared with a `ui_*` action
  is tested on a screen with no focus ([lesson](../lessons/2026-11-02-start-was-eaten-by-the-routers-first-focus-key.md)).
- Plan: a gamepad inside an embedded iframe (the Discord Activity) needs the focus: prompt one click
  ([lesson](../lessons/2026-11-02-an-activity-iframe-lists-no-gamepad-until-a-click.md)).
- Plan: touch proved in a phone-emulated browser; a finger is also a mouse motion in the web runtime
  ([lesson](../lessons/2026-11-02-a-finger-is-a-mouse-motion-too-in-the-web-runtime.md)).
- Plan: multi-touch with two thumbs at once, and hold buttons (aim) that also drag to look; per-finger positions,
  never `relative` ([lesson](../lessons/2026-11-02-a-second-finger-broke-screen-drag-relative-on-the-web.md)).
- Plan: touch designed as its own interface before its first button: every action and every element on the screen for
  that device gets a verdict (keep, make the existing element tappable, drop as a duplicate), and rules the player
  expects everywhere (reload at 0) are proved through each device's real input path
  ([lesson](../lessons/2026-11-05-a-phone-was-built-as-a-keyboard-on-glass.md)).
- Plan: a touch action is listed by what it does, derived from one table, not by an allow-list: every button looks while
  dragged unless its row owns the drag, so a new one cannot opt out unseen
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: every input edge counted once per physics tick by the game, not by `is_action_just_pressed`
  ([lesson](../lessons/2026-11-01-a-held-action-counted-as-two-presses.md)).

## Platforms

- Plan: one opening screen everywhere, the main menu, the Discord Activity included; a platform shortcut is the
  maintainer's call ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: a platform differs from the website only in sign-in and chrome: list every branch on the platform (an instance
  id, the Discord host) in the first build and keep none that changes what a press does; players reach each other by
  a code, a link or a list, never by a platform identity
  ([lesson](../lessons/2026-11-05-a-platform-shortcut-outlived-the-fix-that-moved-its-first-screen.md),
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
  ([lesson](../lessons/2026-11-05-a-phone-test-read-the-canvas-not-the-page-and-the-layout-never-applied.md),
  [deadnight #1197](https://github.com/Ryubara/deadnight/issues/1197)).
- Plan: list the browser abilities each embed grants (focus, gamepad, pointer lock, clipboard, autoplay, fullscreen) and
  probe each inside the Activity frame with Discord's policy before shipping
  ([web export](../engines/godot/web-export.md#discord-activity-copy-and-paste-in-the-frame)).
- Plan: every text field is opened, typed in, closed and submitted with a finger on a phone-shaped page (the export's
  virtual keyboard option on, the field kept above the keyboard, a keypad for a code) before a flow that needs text
  is called done ([web export](../engines/godot/web-export.md#a-phones-keyboard-in-the-web-build),
  [lesson](../lessons/2026-11-05-a-phone-could-not-open-a-keyboard-in-the-web-build.md)).
- Plan: a visible pre-game lobby (members, host, a start the host controls) and mid-match join, every player state
  designed and tested with real clients ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: rooms, invite links and codes on player-facing screens, never an address or `localhost`
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: a performance budget per platform (desktop, browser, server), never one cap for all
  ([lesson](../lessons/2026-11-02-a-web-budget-became-the-desktop-cap.md)).

## Netcode

- Plan: test every closed loop (prediction, interpolation, rate limits) at the worst shipped round trip (300 ms and
  more) with a push, and with the client's own thread frozen (0.5, 2, 5 s) over the real socket, not only steady lag
  ([lesson](../lessons/2026-11-02-a-correction-must-move-the-history-it-is-judged-against.md),
  [deadnight #483](https://github.com/Ryubara/deadnight/issues/483)).
- Plan: protocol and snapshot version bumps that collide across branches: bump past main right before the last push
  ([lesson](../lessons/2026-11-01-two-branches-bumped-the-same-snapshot-version.md)).
- Plan: deploy skew between the web build and the game server: wait for the same commit
  ([lesson](../lessons/2026-11-02-web-and-server-deployed-minutes-apart.md)).
- Plan: never deploy a branch to the shared web service; a CI deploy of main replaces it anyway
  ([deadnight #491](https://github.com/Ryubara/deadnight/issues/491),
  [web export](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: events the server causes alone reach every client
  ([lesson](../lessons/2026-11-01-events-the-server-causes-alone-never-reach-the-client.md)).
- Plan: appearance and bodies replicated from one owner, the same scene local and remote
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: every player feature is specified and tested from another player's view: a two-client test over the real
  socket for what the other screen shows, and captures from the second client's screen
  ([lesson](../lessons/2026-11-02-a-remote-player-was-a-model-with-nothing-to-hold-a-weapon.md),
  [deadnight #518](https://github.com/Ryubara/deadnight/issues/518)).
- Plan: where a player is (menu, waiting room, night, away, reopened lobby) and what ends each state, written as one
  table of states and ways out before the lobby is built; a player moves between lobbies by creating or joining
  (never a refusal for being in another), and a lobby with no person is gone at once, with the game server saying
  when a seat is empty ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed),
  [lesson](../lessons/2026-11-05-a-lobby-the-backend-reopened-held-players-who-never-saw-it.md)).

## Saving

- Plan: hold menu choices in one draft, preview the draft, and commit once on leaving; no other view rereads saved
  state while the screen is open ([lesson](../lessons/2026-11-02-a-view-that-rereads-saved-state-erased-unsaved-choices.md)).
- Plan: a test for every choice against another choice, a tab change and a reload, counting writes
  ([lesson](../lessons/2026-11-02-a-view-that-rereads-saved-state-erased-unsaved-choices.md)).
- Plan: tests point the settings and save files away from the player's own `user://`
  ([lesson](../lessons/2026-11-02-tests-wrote-the-players-settings.md)).

## Co-op rules

- Plan: downs, revives and the scoreboard designed together
  ([deadnight #472](https://github.com/Ryubara/deadnight/issues/472),
  [deadnight #486](https://github.com/Ryubara/deadnight/issues/486)).
- Plan: whether bots fill player slots, researched before the systems they use
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).

## Content: weapons, art and animation

- Plan: a roster table (model, definition, source, numbers) with a test that every weapon can be obtained
  ([lesson](../lessons/2026-11-02-weapon-models-sat-without-definitions-or-a-source.md)).
- Plan: every catalogue entry played through in the real night with the real input
  ([lesson](../lessons/2026-11-01-a-catalogue-weapon-was-never-played-in-the-night.md)).
- Plan: weapons sized against the hand that holds them, not only the body ([lesson](../lessons/2026-11-01-a-chibi-hand-needs-guns-sized-for-it.md)).
- Plan: hand sockets on every held model and a solved grip, with skin-against-weapon contact tested in every pose;
  the kit's clips never move the fingers ([Hands on the weapon](../tools/blender/weapons.md#hands-on-the-weapon)).
- Plan: what each body layer plays in every movement state (walk, sprint, crouch, air)
  ([lesson](../lessons/2026-11-02-a-carry-posed-from-the-front-was-hidden-from-the-game-camera.md)).
- Plan: an animation for every interaction, and clip speeds measured before blend points
  ([lesson](../lessons/2026-11-01-walk-and-run-blend-points-were-guessed.md)).
- Plan: kit props and materials on the map as soon as the layout holds
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).
- Plan: a map design review before a map ships and after its layout changes, run as a level designer from the
  player's camera: loops and kiting space, chokepoints, spawns, pacing of the doors, landmarks, lighting, and every
  out-of-bounds and door-skip candidate proven by movement, not by eye; Deadnight's two maps were first reviewed after
  more than a hundred pull requests (#833; [checklist](../engines/godot/map-review.md)).

## Audio

- Plan: loudness, first-50 ms energy and pitch spread measured from a recording of the real service
  ([lesson](../lessons/2026-11-02-gun-shots-sounded-distant-by-the-numbers-nobody-took.md)).
- Plan: voice lines written as a person speaking, with many takes per event
  ([lesson](../lessons/2026-11-01-voice-lines-written-as-captions-sounded-robotic.md)).
- Plan: no sound design in bus effects, which the web build ignores
  ([lesson](../lessons/2026-11-01-web-samples-ignore-bus-effects.md)).

## Performance

- Plan: first-use hitches: warm up every effect, enemy and shader behind a loading screen
  ([first-use hitches](../engines/godot/first-use-hitches.md)).
- Plan: web spikes on shot and kill: no allocation per event, short sounds decoded at load
  ([lesson](../lessons/2026-11-01-ogg-starts-cost-a-millisecond-in-the-browser.md)).
- Plan: performance from the first playable night, not after a lag report: one command for the worst case (latest
  round, most players, strongest intensity setting, platform ceiling), a sampler of counts and labelled times, a budget
  file held in CI (counts tight, time as a ratio of a calibration loop), and a page of per-system limits with what the
  game does past each. Deadnight had measured the web build and a bare crowd, never its own worst night, and a maintainer
  found the lag first ([performance budgets](../engines/godot/performance-budgets.md),
  [lesson](../lessons/2026-11-03-nobody-knew-the-games-limits-until-a-maintainer-lagged.md),
  [row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).

## Test infrastructure

- Plan: agent launches are silent, unfocused and cursor-free from day one, one wrapper for each (`gds godot` mutes with
  `--audio-driver Dummy`, `gds quiet` sets `GDS_QUIET=1` and every probe launch adds `--mute-audio`)
  ([lesson](../lessons/2026-11-02-agent-launched-godot-played-through-the-speakers.md)).
- Plan: quiet runs for anything that can take the mouse, Godot or browser
  ([lesson](../lessons/2026-11-02-a-headless-browser-under-pointer-lock-held-the-cursor.md)).
- Plan: one shared start helper for every browser probe, so a menu change cannot break them
  ([lesson](../lessons/2026-11-02-each-browser-probe-walked-the-menu-its-own-way.md)).
- Plan: a screen's first running frame tested through every route into it (solo, join, resume, the Activity)
  ([lesson](../lessons/2026-11-02-an-online-join-never-restored-the-crosshair.md)).
- Plan: no flaky exit-leak checks to stall the queue: disconnect test lambdas
  ([lesson](../lessons/2026-11-01-refcounted-lambda-cycle-leaks-at-exit.md)).
- Plan: one-tick flags latched per physics tick, and motion bounded per tick, not per frame
  ([lesson](../lessons/2026-11-01-a-held-action-counted-as-two-presses.md)).
- Plan: suites clear the UI router and every wait loop has a bound
  ([lesson](../lessons/2026-11-02-a-suite-that-ends-on-a-router-screen-eats-later-clicks.md),
  [lesson](../lessons/2026-11-02-a-test-wait-loop-without-a-bound-hung-the-suite.md)).
- Plan: captures and recordings from the player's camera, with the real devices switched off
  ([lesson](../lessons/2026-11-01-the-real-mouse-turned-a-capture-camera.md)).

## Process

- Plan: land old PRs before new ones, reporting from the oldest down
  ([lesson](../lessons/2026-11-02-new-prs-opened-while-old-ones-stalled.md)).
- Plan: rerun known flakes at once and push only what a merge needs
  ([lesson](../lessons/2026-11-02-every-push-restarted-ci-for-the-whole-queue.md)).
- Plan: a fix is done when it is live where the maintainer plays (deployed commit named, probe run on the live URL)
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).
- Plan: local main checkouts fast-forwarded after every merge, by a hook
  ([lesson](../lessons/2026-11-02-local-main-fell-behind-the-merges.md)).
- Plan: a stopgap comment names its issue ("until #N"), and closing #N greps for it and resolves it
  ([lesson](../lessons/2026-11-02-an-until-issue-stopgap-outlived-its-issue.md)).
- Plan: the PR that finishes a split issue carries `Fixes #N`
  ([lesson](../lessons/2026-11-02-an-issue-stayed-open-after-both-halves-merged.md)).
- Plan: load tests capped on the shared machine (four suites, stop by PID, a timeout on every long command)
  ([lesson](../lessons/2026-11-01-load-tests-starved-another-project.md)).
- Plan: the disk is watched from day one: a guard that frees finished worktrees, idle import caches and scratch
  downloads past their pull request below a soft limit, refuses new agents below a hard one, and names the folders over
  budget; captures and CI artifacts are reduced to what is kept in the same task
  ([lesson](../lessons/2026-11-04-the-shared-disk-filled-and-nothing-watched-it.md), [The disk guard](workspace.md#disk)).
- Plan: worktrees always take absolute paths, and agent roster changes reach every game with `gds sync`
  ([lesson](../lessons/2026-11-01-git-worktree-add-path-is-relative-to-the-c-repo.md),
  [what went wrong](building-games-with-agents.md#what-went-wrong)).
- Plan: every kit file a game carries a copy of (the checker, the pre-commit message hooks, the agent definitions) is on
  the `gds sync` list from the first game, so a rule changed in the kit reaches the games in one sync pull request
  ([lesson](../lessons/2026-11-02-a-kit-change-to-a-copied-file-never-reached-the-games.md), [Sync](sync.md)).
- Plan: issue order and ownership are enforced by a tool from day one: work starts only through `gds issue start`
  (oldest ready issues first, a pull request counts as in progress), and a task agent's prompt names its started issue
  ([lesson](../lessons/2026-11-02-a-rule-in-memory-is-broken-under-pressure.md),
  [Starting work](starting-work.md)).
- Plan: a coordinator's owner map is checked against `gh pr list` every time it is re-armed, and `gds issue list` is
  read for issues in progress with no owner ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: every fix pull request names the kit doc it updates, the agent that finds a mistake writes its lesson (with
  `areas:`) and opens the kit pull request in the same task, and agents read the checks of their issue's areas before
  they start ([lesson](../lessons/2026-11-02-docs-written-on-a-branch-were-left-for-a-batch.md),
  the mistakes glossary (`gds lessons <area>`)).
- Plan: hit feedback is part of the first weapon: what a hit does to the body (blood or an impact), marks it leaves,
  hit markers and sounds, each in the warm-up and measured on the web build
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed), [Shot feedback](../engines/godot/shot-feedback.md#blood)).
- Plan: the coordinator lands what it would recommend; the only merges that wait are `S-hold` and the maintainer decisions
  in `AGENTS.md` ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: every end step a tool leaves for the maintainer is asked whether it is a real per-game choice or the same every
  time; the second kind becomes a default the agent runs (a new game's GitHub repository, Pages, ruleset, hold sweep and
  an MIT licence, gdstudio #779) ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).
- Plan: the docs record what the maintainer decided or pointed out in our words, with the issue or pull request and the
  date, never the prompt; a check fails a corrections row that starts with a quotation mark (gdstudio #780)
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).
- Plan: a pause of a repository, like every standing rule the maintainer gives, lives from the first day in a file
  the tools read (`paused` in `workspace.toml`), so `gds issue start`, `gds issue list` and the `Stop` hook stop
  offering its issues ([row](maintainer-corrections.md#corrections-and-the-checks-they-become),
  [lesson](../lessons/2026-11-07-a-pause-kept-in-memory-lost-to-the-hook-that-offers-work.md),
  [Starting work: pausing a game](starting-work.md#paused)).

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
