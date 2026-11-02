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
  the shot waits for the body's turn (known gap, fix pending,
  [deadnight #477](https://github.com/Ryubara/deadnight/issues/477)).
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

## Input

- Plan: every device class the game ships on (keyboard and mouse, gamepad on any device id, touch), each played on
  every platform ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: pointer lock and Esc on the web: pause on lock loss, nothing fires while unlocked
  ([web export](../godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night)).
- Plan: pause on a pad's Start, in the build players use (known gap, cause pending,
  [deadnight #494](https://github.com/Ryubara/deadnight/issues/494)).
- Plan: a gamepad inside an embedded iframe (the Discord Activity) needs the focus: prompt one click
  ([lesson](../lessons/2026-11-02-an-activity-iframe-lists-no-gamepad-until-a-click.md)).
- Plan: touch proved in a phone-emulated browser; a finger is also a mouse motion in the web runtime
  ([lesson](../lessons/2026-11-02-a-finger-is-a-mouse-motion-too-in-the-web-runtime.md)).
- Plan: multi-touch with two thumbs at once, and hold buttons (aim) that also drag to look (known gap, cause pending,
  [deadnight #497](https://github.com/Ryubara/deadnight/issues/497)).
- Plan: every input edge counted once per physics tick by the game, not by `is_action_just_pressed`
  ([lesson](../lessons/2026-11-01-a-held-action-counted-as-two-presses.md)).

## Platforms

- Plan: one opening screen everywhere, the main menu, the Discord Activity included (known gap, fix pending,
  [deadnight #495](https://github.com/Ryubara/deadnight/issues/495)).
- Plan: player identity and display names per platform (Discord nickname, a guest name prompt, Steam later)
  (known gap, [deadnight #485](https://github.com/Ryubara/deadnight/issues/485)).
- Plan: store, key-art and Discord asset sizes listed with the first art pass
  ([deadnight #492](https://github.com/Ryubara/deadnight/issues/492), [key art](../blender/key-art.md)).
- Plan: the Activity stood in locally (mapping prefix, gzip, iframe focus) before the maintainer tries it
  ([web export](../godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: rooms, invite links and codes on player-facing screens, never an address or `localhost`
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).
- Plan: a performance budget per platform (desktop, browser, server), never one cap for all
  ([lesson](../lessons/2026-11-02-a-web-budget-became-the-desktop-cap.md)).

## Netcode

- Plan: a client that stalls or freezes (0.5, 2, 5 s) over the real socket, not only steady lag (known gap, cause
  pending, [deadnight #483](https://github.com/Ryubara/deadnight/issues/483)).
- Plan: protocol and snapshot version bumps that collide across branches: bump past main right before the last push
  ([lesson](../lessons/2026-11-01-two-branches-bumped-the-same-snapshot-version.md)).
- Plan: deploy skew between the web build and the game server: wait for the same commit
  ([lesson](../lessons/2026-11-02-web-and-server-deployed-minutes-apart.md)).
- Plan: never deploy a branch to the shared web service; a CI deploy of main replaces it anyway
  ([deadnight #491](https://github.com/Ryubara/deadnight/issues/491),
  [web export](../godot/web-export.md#discord-activity-the-proxy-and-the-iframe)).
- Plan: events the server causes alone reach every client
  ([lesson](../lessons/2026-11-01-events-the-server-causes-alone-never-reach-the-client.md)).
- Plan: appearance and bodies replicated from one owner, the same scene local and remote
  ([row](maintainer-corrections.md#found-by-playing-concepts-and-details-we-missed)).

## Saving

- Plan: hold menu choices and commit once on leaving the menu, never per click (known gap, cause pending,
  [deadnight #489](https://github.com/Ryubara/deadnight/issues/489)).
- Plan: a test for every choice against another choice, a tab change and a reload
  ([deadnight #489](https://github.com/Ryubara/deadnight/issues/489)).
- Plan: tests point the settings and save files away from the player's own `user://`
  ([lesson](../lessons/2026-11-02-tests-wrote-the-players-settings.md)).

## Co-op rules

- Plan: downs, revives and the scoreboard designed together
  ([deadnight #472](https://github.com/Ryubara/deadnight/issues/472),
  [deadnight #486](https://github.com/Ryubara/deadnight/issues/486)).
- Plan: whether bots fill player slots, researched before the systems they use
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).

## Content: weapons, art and animation

- Plan: a roster table (model, definition, source, numbers) with a test that every weapon can be obtained (known gap,
  [deadnight #461](https://github.com/Ryubara/deadnight/issues/461)).
- Plan: every catalogue entry played through in the real night with the real input
  ([lesson](../lessons/2026-11-01-a-catalogue-weapon-was-never-played-in-the-night.md)).
- Plan: weapons sized against the hand that holds them, not only the body
  ([lesson](../lessons/2026-11-02-hand-guns-disappeared-into-a-chibi-fist.md),
  [deadnight #460](https://github.com/Ryubara/deadnight/issues/460)).
- Plan: what each body layer plays in every movement state (walk, sprint, crouch, air) (known gap,
  [deadnight #459](https://github.com/Ryubara/deadnight/issues/459)).
- Plan: an animation for every interaction, and clip speeds measured before blend points
  ([lesson](../lessons/2026-11-01-walk-and-run-blend-points-were-guessed.md)).
- Plan: kit props and materials on the map as soon as the layout holds
  ([row](maintainer-corrections.md#corrections-and-the-checks-they-become)).

## Audio

- Plan: loudness, first-50 ms energy and pitch spread measured from a recording of the real service
  ([lesson](../lessons/2026-11-02-gun-shots-sounded-distant-by-the-numbers-nobody-took.md)).
- Plan: voice lines written as a person speaking, with many takes per event
  ([lesson](../lessons/2026-11-01-voice-lines-written-as-captions-sounded-robotic.md)).
- Plan: no sound design in bus effects, which the web build ignores
  ([lesson](../lessons/2026-11-01-web-samples-ignore-bus-effects.md)).

## Performance

- Plan: first-use hitches: warm up every effect, enemy and shader behind a loading screen
  ([first-use hitches](../godot/first-use-hitches.md)).
- Plan: web spikes on shot and kill: no allocation per event, short sounds decoded at load
  ([lesson](../lessons/2026-11-01-ogg-starts-cost-a-millisecond-in-the-browser.md)).

## Test infrastructure

- Plan: quiet runs for anything that can take the mouse, Godot or browser
  ([lesson](../lessons/2026-11-02-a-headless-browser-under-pointer-lock-held-the-cursor.md)).
- Plan: one shared start helper for every browser probe, so a menu change cannot break them (known gap,
  [deadnight #484](https://github.com/Ryubara/deadnight/issues/484)).
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
- Plan: the PR that finishes a split issue carries `Fixes #N`
  ([lesson](../lessons/2026-11-02-an-issue-stayed-open-after-both-halves-merged.md)).
- Plan: load tests capped on the shared machine (four suites, stop by PID, a timeout on every long command)
  ([lesson](../lessons/2026-11-01-load-tests-starved-another-project.md)).
- Plan: worktrees always take absolute paths, and agent roster changes reach every game with `gds sync`
  ([lesson](../lessons/2026-11-01-git-worktree-add-path-is-relative-to-the-c-repo.md),
  [what went wrong](building-games-with-agents.md#what-went-wrong)).
