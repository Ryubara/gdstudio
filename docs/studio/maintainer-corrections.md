# What the maintainer caught

A log of what the maintainer corrected or added that neither the coordinator nor any agent had proposed first, from
Deadnight's first nights of work onward, and of what our own checks caught us doing wrong. Each line says what was
pointed out in our words, with its source (the date it was recorded, the game, and the issue or pull request), and
links the topic section it updated: the entry (the approach, what to watch out for, where it was seen) is kept in
the topic page an agent reads for that work, not here ([Learning in the topic pages](rules.md), gdstudio #769).

A new correction updates its topic section and adds one line here, in the same pull request. A prompt is never quoted,
word for word or nearly, here or anywhere in a public repository: the checks fail a row with a cell that starts with a
quotation mark, and a row whose last cell links no section (gdstudio #780).

## Corrections and the checks they become {#corrections-and-the-checks-they-become}

| Recorded | Source | What the maintainer pointed out | Rule |
| --- | --- | --- | --- |
| 2026-11-01 | Deadnight | Multiplayer should run on our own protocol and backend, built network-first, not on the engine's built-in multiplayer | [engines/godot/multiplayer.md#why-our-own-protocol-the-comparison](../engines/godot/multiplayer.md#why-our-own-protocol-the-comparison) |
| 2026-11-01 | Deadnight | Balance and a real wave system belong to the concept from the start, not as extras | [gamedev/design.md#reference](../gamedev/design.md#reference) |
| 2026-11-01 | Deadnight | The game needed boss rounds and zombie types, each clearly announced | [gamedev/design.md#variety](../gamedev/design.md#variety) |
| 2026-11-01 | Deadnight | Every issue and pull request needs screenshots and videos from before and after | [studio/capture.md#attaching](capture.md#attaching) |
| 2026-11-01 | Deadnight | Agents test everything themselves; nothing is handed to the maintainer to try | [studio/capture.md#feature-proof](capture.md#feature-proof) |
| 2026-11-01 | Deadnight | Pull requests should carry an Issues affected section and a Failed first test | [studio/hooks.md#pr-body](hooks.md#pr-body) |
| 2026-11-01 | Deadnight | The starter kit had few guns; the game needed more weapons in its own style | [gamedev/design.md#content](../gamedev/design.md#content) |
| 2026-11-01 | Deadnight | The HUD's text was out of line and the whole HUD too big | [gamedev/ui.md#hud](../gamedev/ui.md#hud) |
| 2026-11-01 | Deadnight | Points should read as a portrait and the points in the player's colour, not as a PLAYER 1 POINTS label | [gamedev/ui.md#hud](../gamedev/ui.md#hud) |
| 2026-11-01 | Deadnight | The generator panel should show only while progress is made, and ammo did not belong under the health bar | [gamedev/ui.md#hud](../gamedev/ui.md#hud) |
| 2026-11-01 | Deadnight | Recordings should come from the player's over-the-shoulder camera, not a spectator camera | [studio/capture.md#frames](capture.md#frames) |
| 2026-11-01 | Deadnight | The shoulder camera should be closer and fluid, tuned against a reference camera | [gamedev/controller.md#feel](../gamedev/controller.md#feel) |
| 2026-11-01 | Deadnight | Textures and the kit's own props would improve the map a lot | [gamedev/design.md#content](../gamedev/design.md#content) |
| 2026-11-01 | Deadnight | Tearing and repairing boards needed real animation | [gamedev/design.md#interactions](../gamedev/design.md#interactions) |
| 2026-11-01 | Deadnight | Zombie speed had to be researched against the player's walk and sprint in the reference | [gamedev/design.md#reference](../gamedev/design.md#reference) |
| 2026-11-01 | Deadnight | Bot teammates needed research in depth: reviving, buying, moving and every weapon | [gamedev/design.md#bot-teammates](../gamedev/design.md#bot-teammates) |
| 2026-11-01 | Deadnight | 93 Godot processes held the CPU at 100%, reported from a neighbouring project | [studio/workspace.md#shared-machine](workspace.md#shared-machine) |
| 2026-11-01 | Deadnight | The web build should be hosted on Railway | [engines/godot/web-export.md#live-build](../engines/godot/web-export.md#live-build) |
| 2026-11-01 | Deadnight | The deployed build hitched the first time a shot or a zombie appeared | [engines/godot/first-use-hitches.md#the-warm-up](../engines/godot/first-use-hitches.md#the-warm-up) |
| 2026-11-01 | Deadnight | The game needed researched, intuitive mobile controls for landscape play | [gamedev/controller.md#devices](../gamedev/controller.md#devices) |
| 2026-11-01 | Deadnight | Local main checkouts should follow every merge, set up from the start | [studio/hooks.md#mains](hooks.md#mains) |
| 2026-11-01 | Deadnight | Rounds have no time limit, and a 3x zombie count means a 3x spawn rate too | [gamedev/design.md#settings](../gamedev/design.md#settings) |
| 2026-11-01 | Deadnight | Desktop should hold over 100 zombies at once without lag on a fast machine | [engines/godot/performance-budgets.md#the-rule](../engines/godot/performance-budgets.md#the-rule) |
| 2026-11-01 | Deadnight #260 | The dead's animation should follow their speed and the round | [engines/godot/crowds.md#gait-follows-speed](../engines/godot/crowds.md#gait-follows-speed) |
| 2026-11-01 | Deadnight | Guns had to be scaled, angled and placed correctly on the player | [tools/blender/weapons.md#axes-origin-and-the-hold](../tools/blender/weapons.md#axes-origin-and-the-hold) |
| 2026-11-01 | Deadnight | Research pages and the corrections page should be kept current as work lands | [studio/hooks.md#docs](hooks.md#docs) |
| 2026-11-01 | Deadnight #299 | Mouse look still did not work on the web after its fix merged, because the live site kept the old build | [engines/godot/web-export.md#live-build](../engines/godot/web-export.md#live-build) |
| 2026-11-01 | Deadnight | Godot windows agents opened took the cursor and then the keyboard from the maintainer | [engines/godot/no-focus.md#what-to-know](../engines/godot/no-focus.md#what-to-know) |
| 2026-11-01 | Deadnight | Corrections should be written into the docs, and that should be enforced | [studio/hooks.md#learning](hooks.md#learning) |
| 2026-11-01 | Deadnight | Pull requests opened hours earlier were still unmerged with no label saying why | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-02 | Deadnight #402 | New pull requests kept opening while older ones stayed unmerged, one for four hours | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-02 | Deadnight #447 | Open pull requests were backing up the queue and had to be landed first | [studio/starting-work.md#merging-main-into-a-pull-request](starting-work.md#merging-main-into-a-pull-request) |
| 2026-11-02 | Deadnight #415 | Every tuned number should be an exported variable, and the docs should map the scenes and the one that loads the game | [engines/godot/project-conventions.md#rules](../engines/godot/project-conventions.md#rules) |
| 2026-11-06 | Deadnight #1366 | Creating a match from the lobby in the Discord Activity stuck on the loading screen with no progress | [engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe) |
| 2026-11-07 | gdstudio #779 | `gds new game` should finish the GitHub steps itself, with MIT as the default licence, not leave them to the maintainer | [engines/godot/new-game.md#github](../engines/godot/new-game.md#github) |
| 2026-11-07 | gdstudio #780 | The maintainer's prompts were quoted in the public docs; none belongs in a public repository | [studio/rules.md#rule](rules.md#rule) |
| 2026-11-07 | gdstudio #786 | Deadnight was paused for kit work, yet a Deadnight issue was started and a pull request opened for it | [studio/starting-work.md#paused](starting-work.md#paused) |
| 2026-11-08 | gdstudio #790 | The new site listed about 970 lessons in one sidebar group that was always open; sections should fold and nest | [studio/docs-site.md#nav](docs-site.md#nav) |
| 2026-11-08 | gdstudio #769 | The maintainer questioned whether agents use per-mistake lesson pages at all; a learning belongs in the page an agent reads for the task | [studio/rules.md#where](rules.md#where) |

## Found by playing: concepts and details we missed {#found-by-playing-concepts-and-details-we-missed}

The maintainer played the build with a mouse, a gamepad and a browser and found these within minutes; every system had
passing tests. Each rule names the concept nobody planned for and the detail that was built without being checked.

| Recorded | Source | What the maintainer pointed out | Rule |
| --- | --- | --- | --- |
| 2026-11-01 | Deadnight | The mouse did not turn the camera in the editor or the browser | [engines/godot/mouse-look.md#godot-specifics](../engines/godot/mouse-look.md#godot-specifics) |
| 2026-11-01 | Deadnight | The gamepad worked only sometimes | [gamedev/controller.md#devices](../gamedev/controller.md#devices) |
| 2026-11-01 | Deadnight | A slightly moved mouse made the gamepad look undetected | [gamedev/controller.md#devices](../gamedev/controller.md#devices) |
| 2026-11-01 | Deadnight | Weapons switched in the rules but not on screen, and the guns sat wrong in the hands | [gamedev/testing.md#catalogue](../gamedev/testing.md#catalogue) |
| 2026-11-01 | Deadnight | Firing from the hip neither turned the character nor tightened the camera | [gamedev/controller.md#conventions](../gamedev/controller.md#conventions) |
| 2026-11-01 | Deadnight | The HUD had no crosshair | [gamedev/ui.md#hud](../gamedev/ui.md#hud) |
| 2026-11-01 | Deadnight | Repairing took one press per board instead of a hold | [gamedev/controller.md#conventions](../gamedev/controller.md#conventions) |
| 2026-11-01 | Deadnight | Firing had no camera shake | [gamedev/controller.md#feel](../gamedev/controller.md#feel) |
| 2026-11-01 | Deadnight | The muzzle flash was a yellow sphere and bullet impacts were far too large | [engines/godot/shot-feedback.md#impacts](../engines/godot/shot-feedback.md#impacts) |
| 2026-11-01 | Deadnight | The ammo count did not update after buying ammo until a weapon swap | [gamedev/ui.md#hud](../gamedev/ui.md#hud) |
| 2026-11-01 | Deadnight | The look saved in the wardrobe did not show on the character in the game | [gamedev/testing.md#real-path](../gamedev/testing.md#real-path) |
| 2026-11-01 | Deadnight | The fire effect has to start at each weapon's own muzzle | [tools/blender/weapons.md#attachment-points](../tools/blender/weapons.md#attachment-points) |
| 2026-11-01 | Deadnight | Each player looked different on the other player's screen in a two-window game | [engines/godot/multiplayer.md#appearance](../engines/godot/multiplayer.md#appearance) |
| 2026-11-01 | Deadnight | A player was taller on the other player's screen | [engines/godot/multiplayer.md#appearance](../engines/godot/multiplayer.md#appearance) |
| 2026-11-01 | Deadnight | Camera shake was wanted very subtle and came for firing only; sprinting had none | [gamedev/controller.md#feel](../gamedev/controller.md#feel) |
| 2026-11-01 | Deadnight | The character could not sprint backwards, and free movement felt wrong | [gamedev/controller.md#conventions](../gamedev/controller.md#conventions) |
| 2026-11-01 | Deadnight | The settings rows sometimes collapsed into each other | [engines/godot/ui-controls.md#animating-a-containers-children](../engines/godot/ui-controls.md#animating-a-containers-children) |
| 2026-11-01 | Deadnight | Seen from the side, the moving character looked blurry and jittery | [engines/godot/physics-interpolation.md#using-it](../engines/godot/physics-interpolation.md#using-it) |
| 2026-11-01 | Deadnight #351 | Grenades could not be thrown | [gamedev/testing.md#real-path](../gamedev/testing.md#real-path) |
| 2026-11-01 | Deadnight #285 | The crowbar used a bat model with no swing, a muzzle flash and no effect; the revolver did not show in the hand | [gamedev/testing.md#catalogue](../gamedev/testing.md#catalogue) |
| 2026-11-01 | Deadnight #300 | Hip fire did not reach the aim pose, aiming snapped the gun, and the hip-fire zoom did not follow the aim's logic | [gamedev/controller.md#aim](../gamedev/controller.md#aim) |
| 2026-11-01 | Deadnight #344 | The side-view judder looked unchanged in the web build after its fix was closed | [engines/godot/physics-interpolation.md#using-it](../engines/godot/physics-interpolation.md#using-it) |
| 2026-11-01 | Deadnight #384 | The voice lines sounded robotic: short captions of the event instead of a person reacting | [gamedev/audio/voice-lines.md#2-writing-the-lines](../gamedev/audio/voice-lines.md#2-writing-the-lines) |
| 2026-11-01 | gdstudio #77 | A hidden game under test still held the cursor inside an invisible box while its audio played | [engines/godot/no-focus.md#the-cursor-clip-crosses-desktops](../engines/godot/no-focus.md#the-cursor-clip-crosses-desktops) |
| 2026-11-01 | Deadnight | An agent's headless browser probe trapped the cursor in an invisible window until Esc | [engines/godot/no-focus.md#browser-probes-and-any-other-program-gds-quiet](../engines/godot/no-focus.md#browser-probes-and-any-other-program-gds-quiet) |
| 2026-11-01 | Deadnight #391 | The online Join screen offered a localhost address and left open how players find each other on the web | [gamedev/ui.md#online](../gamedev/ui.md#online) |
| 2026-11-01 | Deadnight #405 | Sprint shake was too strong and kept going in a sprint-jump; the view was to sit 10% closer | [engines/godot/camera.md#shake-and-sway](../engines/godot/camera.md#shake-and-sway) |
| 2026-11-01 | Deadnight #408 | The muzzle flash looked weaker than it should | [engines/godot/measuring-effects-on-screen.md#method](../engines/godot/measuring-effects-on-screen.md#method) |
| 2026-11-01 | Deadnight #428 | The hip-fire zoom came on after aiming, shooting and letting go of aim | [gamedev/controller.md#aim](../gamedev/controller.md#aim) |
| 2026-11-02 | Deadnight #469 | Playing together in the Discord Activity could not reach the servers, though the browser could | [engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe) |
| 2026-11-02 | Deadnight #479 | The gamepad did not work in the Discord Activity until the window was clicked and the stick moved | [engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe) |
| 2026-11-02 | Deadnight #516 | Copy and paste did not work in the Discord Activity | [engines/godot/web-export.md#discord-activity-copy-and-paste-in-the-frame](../engines/godot/web-export.md#discord-activity-copy-and-paste-in-the-frame) |
| 2026-11-05 | Deadnight #1183 | No keyboard opened on a phone to type a room number in the Discord Activity | [engines/godot/web-export.md#a-phones-keyboard-in-the-web-build](../engines/godot/web-export.md#a-phones-keyboard-in-the-web-build) |
| 2026-11-02 | Deadnight #407 | The tommy gun sounded distant with uneven shots, and every gun needed more power | [engines/godot/audio.md#close-and-powerful-sounds](../engines/godot/audio.md#close-and-powerful-sounds) |
| 2026-11-02 | Deadnight #464 | In the Activity, the zoom stayed a moment after releasing aim, and hip fire was to lose its zoom | [studio/starting-work.md#stopping-and-finishing](starting-work.md#stopping-and-finishing) |
| 2026-11-02 | Deadnight #477 | A hip-fire shot left at once instead of waiting for the body to turn to the cursor | [gamedev/controller.md#states](../gamedev/controller.md#states) |
| 2026-11-02 | Deadnight #470 | On phones the move stick also turned the camera, and the look thumb turned it far too fast | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-02 | Deadnight #489 | Outfits reset on a weapon change or a tab switch; they were to save once on leaving the menu | [gamedev/ui.md#choices](../gamedev/ui.md#choices) |
| 2026-11-02 | Deadnight #460 | Hands sat wrong on the weapons, the trigger finger worst, and were too big for some guns | [tools/blender/weapons.md#hands-on-the-weapon](../tools/blender/weapons.md#hands-on-the-weapon) |
| 2026-11-02 | gdstudio #97 | A new issue was started at once while older ones waited; starting work was to go through a tool that keeps the order | [studio/starting-work.md#the-rule](starting-work.md#the-rule) |
| 2026-11-02 | Deadnight #488 | A pull request sat red long enough to ask whether its agent was stuck or needed a stronger model | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-02 | gdstudio #102 | Godot and game windows launched by agents were to be muted unless sound is needed to debug | [engines/godot/no-focus.md#sound](../engines/godot/no-focus.md#sound) |
| 2026-11-02 | Deadnight #507 | Docs for gaps not planned at the start kept needing a request; writing them was to be an enforced learning loop | [studio/hooks.md#docs](hooks.md#docs) |
| 2026-11-02 | Deadnight #483 | A client that froze for a moment flew across the map once it caught up; lag on a connected client needed a test | [engines/godot/multiplayer.md#a-client-that-freezes-measured-on-the-live-server](../engines/godot/multiplayer.md#a-client-that-freezes-measured-on-the-live-server) |
| 2026-11-02 | Deadnight #518 | Clients could not see the weapons other clients held | [engines/godot/multiplayer.md#appearance](../engines/godot/multiplayer.md#appearance) |
| 2026-11-02 | Deadnight #495 | The Discord Activity opened on the Play together screen instead of the main menu | [engines/godot/web-export.md#activity-same-game](../engines/godot/web-export.md#activity-same-game) |
| 2026-11-02 | Deadnight #529 | The crosshair was missing on entering a game until the player paused and resumed | [engines/godot/ui-controls.md#a-menu-over-a-live-game](../engines/godot/ui-controls.md#a-menu-over-a-live-game) |
| 2026-11-02 | Deadnight #494 | A controller's Start button did not pause the game | [engines/godot/ui-controls.md#menus-under-test](../engines/godot/ui-controls.md#menus-under-test) |
| 2026-11-02 | Deadnight #526 | Play together and Quick join did the same thing; Quick join was to join the first game found | [studio/starting-work.md#stopping-and-finishing](starting-work.md#stopping-and-finishing) |
| 2026-11-02 | Deadnight #459 | Weapons stayed frozen during the sprint; they needed sprint clips of their own or swinging arms | [engines/godot/animation-tree.md#one-action-state-for-every-body](../engines/godot/animation-tree.md#one-action-state-for-every-body) |
| 2026-11-02 | Deadnight #497 | On a phone, looking with the right thumb while moving flicked the view fast; a held aim button should also look | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-02 | Deadnight #461 | Every weapon had to be in the game and reachable from the prize crane | [gamedev/balance.md#roster](../gamedev/balance.md#roster) |
| 2026-11-02 | Deadnight #515 | Nobody could tell who was in a lobby or whether joining mid-match worked; a lobby the host starts was needed | [engines/godot/multiplayer.md#player-states](../engines/godot/multiplayer.md#player-states) |
| 2026-11-02 | gdstudio #107 | Agents should never need to force-push; their branches should be ready before they are assigned | [studio/starting-work.md#worktree](starting-work.md#worktree) |
| 2026-11-02 | Deadnight #598 | Turning the camera with the right touch stick was playable but still jittery | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-02 | Deadnight #599 | The camera could not be turned while a grenade was held | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-02 | Deadnight #601 | On iOS in the browser, shots did not land where the crosshair was | [engines/godot/camera.md#projecting-world-points-to-the-hud](../engines/godot/camera.md#projecting-world-points-to-the-hud) |
| 2026-11-03 | Deadnight #703 | A neon sign's glow halo bled through a wall and the maintainer moved map pieces by hand to hide it | [engines/godot/compat-lighting.md#a-lamp-near-a-wall](../engines/godot/compat-lighting.md#a-lamp-near-a-wall) |
| 2026-11-03 | Deadnight #832 | A sign's glow still came through the wall, because nobody thought of it when the sign was made | [engines/godot/compat-lighting.md#a-lamp-near-a-wall](../engines/godot/compat-lighting.md#a-lamp-near-a-wall) |
| 2026-11-03 | Deadnight #831 | Interact prompts showed through walls, and the collision checks needed a second look | [gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall](../gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall) |
| 2026-11-03 | Deadnight #830 | The weapon the prize crane picked was sometimes hard to see | [studio/capture.md#before-captures](capture.md#before-captures) |
| 2026-11-03 | Deadnight #859 | The second map's soda fountain, perks and re-cut bench stay, and every map gets them | [gamedev/level-design.md#p1-judge-the-map-by-its-own-numbers-measured-first](../gamedev/level-design.md#p1-judge-the-map-by-its-own-numbers-measured-first) |
| 2026-11-03 | Deadnight #902 | Some repairable windows showed a boarded outline suggesting they could be boarded, and others had none | [gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall](../gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall) |
| 2026-11-03 | Deadnight #897 | The quick melee one-shot zombies after round 1, which it must not | [gamedev/balance.md#shots-to-kill](../gamedev/balance.md#shots-to-kill) |
| 2026-11-03 | Deadnight #911 | The prize crane's beam showed through objects; it should rise only until it meets a floor or an object | [engines/godot/compat-lighting.md#a-column-of-light-has-a-length-from-what-is-above-it](../engines/godot/compat-lighting.md#a-column-of-light-has-a-length-from-what-is-above-it) |
| 2026-11-03 | Deadnight #905 | Mouse look went wrong whenever the game lagged, which other games do not do | [engines/godot/mouse-look.md#the-fault-set-the-child-then-the-parent](../engines/godot/mouse-look.md#the-fault-set-the-child-then-the-parent) |
| 2026-11-03 | Deadnight #909 | Re-cutting a second weapon should not cost 3,000; a re-cut costs 5,000 and a weapon is re-cut once | [gamedev/balance.md#prices](../gamedev/balance.md#prices) |
| 2026-11-03 | Deadnight #898 | The start revolver one-shot heads on rounds 1 and 2; a lighter pistol should take 3 head or 7 body shots on round 1 | [gamedev/balance.md#shots-to-kill](../gamedev/balance.md#shots-to-kill) |
| 2026-11-03 | Deadnight #910 | Melee weapons are too strong to be sold on the walls | [gamedev/balance.md#comparing](../gamedev/balance.md#comparing) |
| 2026-11-03 | Deadnight #893 | The menu character looked slightly pixelated with jagged edges, raising whether to add anti-aliasing | [engines/godot/ui-controls.md#3d-in-a-menu](../engines/godot/ui-controls.md#3d-in-a-menu) |
| 2026-11-03 | Deadnight #906, #907 | Performance is to be weighed at all times, naming the places that will lag; objects left in memory were a suspect | [engines/godot/performance-review.md#the-rule](../engines/godot/performance-review.md#the-rule) |
| 2026-11-03 | Deadnight #916 | Points always come in steps of 5, so a score never reads 31 to 34 | [gamedev/balance.md#denomination](../gamedev/balance.md#denomination) |
| 2026-11-03 | Deadnight #895 | Menu player models had see-through necks, a line for a mouth, a mask-like face, ill-fitting clothes and clipping limbs | [tools/blender/variants.md#closed-and-fitting-in-every-combination](../tools/blender/variants.md#closed-and-fitting-in-every-combination) |
| 2026-11-03 | Deadnight #904 | Some weapons taken from the prize crane never reached the player's inventory | [engines/godot/multiplayer.md#player-states](../engines/godot/multiplayer.md#player-states) |
| 2026-11-03 | Deadnight #908 | Boarding a window sometimes bought the wall weapon or perk beside it; interactions need spacing | [engines/godot/map-review.md#5-landmarks-wayfinding-and-readability](../engines/godot/map-review.md#5-landmarks-wayfinding-and-readability) |
| 2026-11-03 | Deadnight #917 | The second map's layout made no sense (flat land from both floors, a window over the stairs, perks too close) | [engines/godot/map-review.md#does-it-make-sense](../engines/godot/map-review.md#does-it-make-sense) |
| 2026-11-03 | Deadnight #940 | In the loadout, turning the character broke the arms and a weapon switch pointed arms and weapon back through the body | [engines/godot/animation-tree.md#a-modifier-that-aims-in-the-world-needs-the-world-value-written-on-every-turn](../engines/godot/animation-tree.md#a-modifier-that-aims-in-the-world-needs-the-world-value-written-on-every-turn) |
| 2026-11-03 | Deadnight #914 | Players ran straight through zombies; they should be blocked but able to nudge a zombie aside | [engines/godot/crowds.md#a-players-body-against-a-crowd-that-is-not-physics-bodies](../engines/godot/crowds.md#a-players-body-against-a-crowd-that-is-not-physics-bodies) |
| 2026-11-03 | Deadnight #915 | Zombies passed through the wall at windows instead of climbing over, and no climb clip seemed to exist | [engines/godot/map-review.md#3-spawns-and-how-the-dead-arrive](../engines/godot/map-review.md#3-spawns-and-how-the-dead-arrive) |
| 2026-11-04 | Deadnight #944 | None of the host's lobby settings applied, and every night started on the drive-in | [engines/godot/multiplayer.md#across-services](../engines/godot/multiplayer.md#across-services) |
| 2026-11-05 | Deadnight #1177 | After leaving a match, joining another was refused as already in a night; empty lobbies should disband | [engines/godot/multiplayer.md#player-states](../engines/godot/multiplayer.md#player-states) |
| 2026-11-03 | Deadnight #915 | Every barricade is to be a window, not a door-shaped gap that suggests players can walk through | [gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall](../gamedev/level-design.md#p10-what-can-be-used-reads-as-usable-and-nothing-works-through-a-wall) |
| 2026-11-04 | gdstudio #489 | The C drive was nearly full; clearing unneeded storage should be enforced and watched all the time | [studio/workspace.md#disk](workspace.md#disk) |
| 2026-11-04 | Deadnight #971 | Crawlers stood up to attack; they needed a proper crawling attack | [engines/godot/animation-tree.md#one-action-state-for-every-body](../engines/godot/animation-tree.md#one-action-state-for-every-body) |
| 2026-11-04 | Deadnight #978 | The female characters' arms looked too long, and the male ones needed checking too | [tools/blender/variants.md#proportions-measure-the-arm](../tools/blender/variants.md#proportions-measure-the-arm) |
| 2026-11-04 | Deadnight #980 | The UI has to fit every screen, with no container too tall or running under the footer's key hints | [engines/godot/ui-controls.md#a-card-taller-than-its-screen](../engines/godot/ui-controls.md#a-card-taller-than-its-screen) |
| 2026-11-03 | Deadnight #906 | Performance is to be weighed at all times, and should have been from the start | [engines/godot/performance-budgets.md#the-rule](../engines/godot/performance-budgets.md#the-rule) |
| 2026-11-04 | Tether checkpoint | Tether's checkpoint likely did not fire because a stray newline left the input non-empty, and the context ran on | [studio/agents.md#the-loop](agents.md#the-loop) |
| 2026-11-05 | Deadnight #1178 | The Activity's shortcut past Play together gave a second player a lobby of their own; it should work as the website does | [engines/godot/web-export.md#activity-same-game](../engines/godot/web-export.md#activity-same-game) |
| 2026-11-05 | Deadnight #1275 to #1280 | The phone interface was the desktop with touch buttons, not its own design, with duplicate controls | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-05 | Deadnight #1277 | Every button on the right side of a phone screen should still look around while it is held | [engines/godot/ui-controls.md#touch-controls](../engines/godot/ui-controls.md#touch-controls) |
| 2026-11-05 | Deadnight #1278 | A weapon at 0 rounds should reload by itself; aimed auto-fire on a phone did not | [gamedev/controller.md#states](../gamedev/controller.md#states) |

## Done wrong first, caught by our own checks {#done-wrong-first-caught-by-our-own-checks}

Mistakes the maintainer did not have to point out, because a test, a measurement or a review caught them.

| Recorded | Source | What went wrong first | Rule |
| --- | --- | --- | --- |
| 2026-11-01 | Deadnight #260, #271 | Two pull requests each passed the balance gate alone and broke it together on main | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-01 | Deadnight | A merge of main doubled a step in a test, so the branch failed | [studio/starting-work.md#merging-main-into-a-pull-request](starting-work.md#merging-main-into-a-pull-request) |
| 2026-11-01 | Deadnight | World triplanar materials slowed the web frame from 79 to 90 ms | [engines/godot/surface-materials.md#measured](../engines/godot/surface-materials.md#measured) |
| 2026-11-01 | Deadnight | A headless import left new 3D textures without mipmaps | [engines/godot/surface-materials.md#pitfalls](../engines/godot/surface-materials.md#pitfalls) |
| 2026-11-01 | Deadnight | Walk and run blend points were guessed (1.0 and 3.0 m/s) while the clips move at 0.97 and 4.4 | [engines/godot/crowds.md#gait-follows-speed](../engines/godot/crowds.md#gait-follows-speed) |
| 2026-11-01 | Deadnight #288 | Guns modelled at real length beside a Soldier scaled to 0.8, held from a one-handed pose, and every gun showed the rifle | [tools/blender/weapons.md#axes-origin-and-the-hold](../tools/blender/weapons.md#axes-origin-and-the-hold) |
| 2026-11-01 | Deadnight | A balance fix ran only the gate test; four simulator tests beside it failed in CI and main stayed red | [studio/starting-work.md#stopping-and-finishing](starting-work.md#stopping-and-finishing) |
| 2026-11-01 | Deadnight #290 | Main's CI cancelled a run when the next merge landed, so four of five merges in three minutes went unchecked | [studio/ci.md#main-runs](ci.md#main-runs) |
| 2026-11-01 | Deadnight | The browser smoke read the probe through named fields, so a new field read as missing on a working build | [engines/godot/web-export.md#browser-probes](../engines/godot/web-export.md#browser-probes) |
| 2026-11-01 | Deadnight | A pull request body wrote None without the expected form and the CI body check refused it | [studio/hooks.md#pr-body](hooks.md#pr-body) |
| 2026-11-01 | Deadnight #346 | UI input tests passed alone and failed in the folder run: an earlier suite's menu on the router took the clicks | [engines/godot/ui-controls.md#menus-under-test](../engines/godot/ui-controls.md#menus-under-test) |
| 2026-11-01 | Deadnight #362 | A smoothness test timed frames by the real clock and failed on busy machines, turning main red | [engines/godot/mouse-look.md#how-to-measure-it](../engines/godot/mouse-look.md#how-to-measure-it) |
| 2026-11-01 | Deadnight #364 | The real mouse of the person at the machine turned a capture's camera by up to 65 degrees | [engines/godot/no-focus.md#what-to-know](../engines/godot/no-focus.md#what-to-know) |
| 2026-11-01 | Deadnight #384 | The first voice samples used a model chosen from memory while the account offered a newer, more emotive one | [gamedev/audio/voice-lines.md#generate](../gamedev/audio/voice-lines.md#generate) |
| 2026-11-01 | Deadnight #418, #446 | Test suites wrote camera_shake=0 into the player's real settings file, and two agents edited the real file | [engines/godot/throwaway-user-folder.md#tests](../engines/godot/throwaway-user-folder.md#tests) |
| 2026-11-02 | Deadnight | Esc in the web build freed the cursor without pausing, and look and fire kept running with a free cursor | [engines/godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night](../engines/godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night) |
| 2026-11-02 | Deadnight #466, #484 | Each browser probe walked the menu its own way, so the menu rework broke two of them silently | [engines/godot/web-export.md#browser-probes](../engines/godot/web-export.md#browser-probes) |
| 2026-11-02 | GDStudio coordinator | No pull requests were open while startable kit issues waited and three agents had stalled for hours unnoticed | [studio/starting-work.md#parallel](starting-work.md#parallel) |
| 2026-11-02 | GDStudio coordinator, gdstudio #165 | Parallel work lived in the coordinator's attention; unlabelled waiting issues held the window | [studio/starting-work.md#parallel](starting-work.md#parallel) |
| 2026-11-02 | GDStudio coordinator, gdstudio #218 | Four issues were blocked on one running issue for sharing a subsystem, so they ran one at a time | [studio/starting-work.md#parallel](starting-work.md#parallel) |
| 2026-11-02 | Deadnight #621 | Hands sat wrong on the menu's guns because the menu soldier had its own copy of the hold code | [tools/blender/weapons.md#hands-on-the-weapon](../tools/blender/weapons.md#hands-on-the-weapon) |
| 2026-11-02 | Deadnight #620 | A finished Play screen with the match settings was never routed from the menu, so Solo never offered them | [studio/starting-work.md#stopping-and-finishing](starting-work.md#stopping-and-finishing) |
| 2026-11-03 | GDStudio coordinator | Expired monitors left 35 polling loops running, which kept opening bash windows | [studio/agents.md#the-loop](agents.md#the-loop) |
| 2026-11-03 | Deadnight #564 | Bots were built as followers tuned toward a distance gate; their default behaviour and orders were never asked | [gamedev/design.md#bot-teammates](../gamedev/design.md#bot-teammates) |
| 2026-11-02 | Deadnight #619 | A sprint start popped: the arms stayed in the IK pose as the modifier faded and snapped to the clip in one tick | [engines/godot/animation-tree.md#a-clip-on-top-of-a-pose-a-modifier-fades-out](../engines/godot/animation-tree.md#a-clip-on-top-of-a-pose-a-modifier-fades-out) |
| 2026-11-02 | Deadnight #627 | Share in Discord claimed Discord's picker had opened whatever Discord answered; the stub always said yes | [engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe) |
| 2026-11-02 | Deadnight #628 | Buttons that grow on hover were clipped by the scroll area around them | [engines/godot/ui-controls.md#a-control-that-draws-outside-its-rect](../engines/godot/ui-controls.md#a-control-that-draws-outside-its-rect) |
| 2026-11-02 | Deadnight #617 | The zombie outline had a glow and showed on visible parts, not only on the part hidden behind cover | [engines/godot/outline-through-walls.md#only-where-it-is-hidden](../engines/godot/outline-through-walls.md#only-where-it-is-hidden) |
| 2026-11-02 | Deadnight #618 | Shots on zombies showed nothing on the body: hit feedback was never planned with the combat loop | [engines/godot/shot-feedback.md#blood](../engines/godot/shot-feedback.md#blood) |
| 2026-11-03 | gdstudio #241 | Finished worktrees were never removed, and 64 of them with import caches filled the disk to 8 GB free | [studio/workspace.md#sweep](workspace.md#sweep) |
| 2026-11-03 | Deadnight #655, #656, #660, #661 | Five parallel art pull requests edited the same docs rows and test and conflicted, whatever the merge order | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-03 | Deadnight #681 | Zombies kept their spawn height and never climbed ramps or stairs: the sim assumed a flat lot | [engines/godot/crowds.md#height-a-crowd-off-the-physics-engine-must-be-given-its-floor](../engines/godot/crowds.md#height-a-crowd-off-the-physics-engine-must-be-given-its-floor) |
| 2026-11-03 | Deadnight #702 | With bots seated, the view followed a bot: every body's camera was current and the first fix went into callers | [engines/godot/camera.md#one-current-camera-per-viewport](../engines/godot/camera.md#one-current-camera-per-viewport) |
| 2026-11-03 | Deadnight #686 | Opening the road showed an unfinished placeholder area that had stayed visible for a hundred pull requests | [gamedev/level-design.md#p19-the-place-makes-sense-to-a-player](../gamedev/level-design.md#p19-the-place-makes-sense-to-a-player) |
| 2026-11-03 | Deadnight #685 | Every solo night started from one fixed seed, so the prize crane rolled the same prizes in the same order | [gamedev/testing.md#random-draws](../gamedev/testing.md#random-draws) |
| 2026-11-03 | Deadnight #692 | A teammate bot answered a person's ping for ammo but had no needs of its own to rank against orders | [gamedev/design.md#bot-teammates](../gamedev/design.md#bot-teammates) |
| 2026-11-03 | Deadnight #701 | Glow-pane windows showed from one side only and were holes from inside the room | [engines/godot/compat-lighting.md#light-cards-indoors-moon-shafts-door-glow-chalk](../engines/godot/compat-lighting.md#light-cards-indoors-moon-shafts-door-glow-chalk) |
| 2026-11-03 | Deadnight #689 | The game lagged on a phone: the canvas used the phone's full pixel ratio with MSAA, and checks ran on desktop | [engines/godot/web-phone-frames.md#measuring-a-phone-without-one](../engines/godot/web-phone-frames.md#measuring-a-phone-without-one) |
| 2026-11-03 | Deadnight #627, #649 | Discord invites failed for a missing authenticate call; the first fix passed a harness that never refused | [engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe](../engines/godot/web-export.md#discord-activity-the-proxy-and-the-iframe) |
| 2026-11-03 | Deadnight #732 | Deploy jobs skipped unless their commit was still main's head, so every run skipped and Railway fell 13 merges behind | [studio/ci.md#main-runs](ci.md#main-runs) |
| 2026-11-03 | Deadnight #694 | Crawler hit zones were one standing set that ignored the pose, so most shots on a crawler's head missed | [gamedev/testing.md#what-is-drawn](../gamedev/testing.md#what-is-drawn) |
| 2026-11-03 | Deadnight #781 | A cut to the crickets was set as one dB figure by loudness and was not heard: their band and chirp rate were ignored | [engines/godot/audio.md#is-a-sound-heard-under-fire](../engines/godot/audio.md#is-a-sound-heard-under-fire) |
| 2026-11-03 | Deadnight #781 | A 50% cut was taken from the already-cut level and as amplitude, not from the original level as heard | [studio/asks.md#numbers](asks.md#numbers) |
| 2026-11-04 | Deadnight | A reply gave the average of a rising XP curve, which read as a flat pace nobody plays | [studio/asks.md#numbers](asks.md#numbers) |
| 2026-11-04 | Deadnight | A rule about guests was read as guests having no account, and issues were filed on that reading unchecked | [studio/asks.md#decision-words](asks.md#decision-words) |
| 2026-11-04 | Deadnight | Costume default colours were read as fixed data, when a Default option beside player-picked colours was meant | [studio/asks.md#decision-words](asks.md#decision-words) |
| 2026-11-04 | Deadnight #1115 | Icon, level and name were ordered without showing the maintainer, and each screen placed the level its own way | [gamedev/ui.md#many-places](../gamedev/ui.md#many-places) |
| 2026-11-04 | Deadnight #1077 | The player boxes at the bottom left were left out of the identity feature: the places a name shows were never listed | [gamedev/ui.md#many-places](../gamedev/ui.md#many-places) |
| 2026-11-04 | Deadnight #1161 | The level digits and the icon beside a name were not aligned: each was placed from its own box, not its ink | [engines/godot/ui-controls.md#a-part-placed-from-another-parts-rectangle](../engines/godot/ui-controls.md#a-part-placed-from-another-parts-rectangle) |
| 2026-11-06 | Deadnight #1322 | Bots paid for the prize crane again and again but never took the weapon | [gamedev/design.md#bot-teammates](../gamedev/design.md#bot-teammates) |
| 2026-11-06 | Deadnight #1199, #1244, #1252 | Green pull requests the coordinator recommended were parked waiting for a yes | [studio/starting-work.md#landing](starting-work.md#landing) |
| 2026-11-06 | gdstudio | gds posted 595 status comments under the maintainer's account; the guard read only what agents typed | [studio/hooks.md#comments](hooks.md#comments) |
| 2026-11-06 | Deadnight #1366 | A lobby start stuck for one account whose ticket pushed the hello past its byte limit; every probe was a fresh guest | [engines/godot/multiplayer.md#small-things-that-cost-time](../engines/godot/multiplayer.md#small-things-that-cost-time) |
| 2026-11-07 | gdstudio #771 | A mod and a new repository were proposed for work the orchestrator, a guard and the kit already did | [studio/asks.md#new-tools](asks.md#new-tools) |

## Start of a new game {#start-of-a-new-game}

The checklist drawn from these corrections is now part of
[What to plan from the start](plan-from-the-start.md#start-of-a-new-game).
