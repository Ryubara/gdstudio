# UI and HUD

<!-- new section: gamedev had pages for level design and audio only; nothing held the engine-neutral rules of what a
HUD shows, how a screen of choices keeps them and what an online menu offers a player -->

What the player reads and chooses on screen, as principles: the HUD's elements and how they follow the game state, a
screen that holds several choices, and the flow an online menu offers. How Godot's controls do it is in
[UI controls](../engines/godot/ui-controls.md).

## The HUD {#hud}

<!-- new section: what a HUD holds and how its values follow the state had no home -->

- **Approach:** Inventory the genre's HUD elements (reticle, hit marker, ammo, prompts) against the design before
  polishing the layout. **Watch out for:** a basic element of the genre was missing while the HUD was polished: there
  was no crosshair, though the HUD placed items beside it. **Seen:** Deadnight, 2026-11-01 (fix: the crosshair was added
  and the design lists the HUD's elements).
- **Approach:** Bind HUD values to the replicated state so they refresh on any change, with a test that changes the
  state another way (buy ammo) and reads the HUD without a swap. **Watch out for:** the HUD was driven by one-off
  events: the ammo card re-read only on equip, so bought ammo did not show until a weapon swap. **Seen:** Deadnight,
  2026-11-01 (fix: the card follows the state).
- **Approach:** Capture the HUD at 720p, 1080p and 1440p and in the web build, and measure alignment and overflow in
  tests. **Watch out for:** the HUD was judged on its own at one size, so its text sat out of line and the whole HUD was
  too big at the sizes players run. **Seen:** Deadnight, 2026-11-01 (fix: HUD changes carry captures at the three sizes
  and the browser, and a layout test finds overlaps no eye would
  ([lesson](../lessons/2026-11-01-layout-test-found-hud-overlaps-no-eye-would.md))).
- **Approach:** For each HUD element, ask what the player reads in half a second during a fight and design that: a
  portrait beside the points in the player's colour, not a PLAYER 1 POINTS label. **Watch out for:** the data was
  labelled instead of designed for a glance. **Seen:** Deadnight, 2026-11-01 (fix: deadnight's points became the
  portrait and the points in the seat's colour).
- **Approach:** Give every number one home on the HUD, and show a panel for slow progress only while the progress moves,
  then let it leave. **Watch out for:** each system got an always-on panel, some numbers twice: the generator panel
  stayed up when nothing happened and ammo also sat under the health bar. **Seen:** Deadnight, 2026-11-01 (fix: the
  generator panel shows only while progress is made and ammo has one place).

## A screen of choices {#choices}

<!-- new section: how a screen with several choices holds and saves them had no home -->

- **Approach:** Hold a screen's choices in one place while it is open, commit them once when the player leaves, and draw
  the preview from that held state; test every panel with more than one choice: change A, then B, tab away and back,
  reload from the file, and count writes (0 while open, 1 on leaving). Never route held choices through a setting other
  views react to. **Watch out for:** a showcase-weapon click wrote a setting, a view reread the saved look on that
  change and erased the unsaved outfit, and leaving wrote nothing; the tests called `apply_preset` and `save()`
  directly. **Seen:** Deadnight #489, 2026-11-02 (fix: deadnight #493
  ([lesson](../lessons/2026-11-02-a-view-that-rereads-saved-state-erased-unsaved-choices.md))).

## Playing online {#online}

<!-- new section: what an online menu offers a player had no home -->

- **Approach:** Before an online feature is called playable, walk the flow a stranger takes on each platform the game
  ships on (browser, Discord); no address, port or localhost appears on a player-facing screen. **Watch out for:**
  players play with friends, not addresses: the flow is rooms (a Discord instance, an invite link, a code, quick join),
  but the networking spike's Join screen (`ws://localhost:8910`) shipped as the online menu while the backend's lobbies
  were never deployed or wired in. **Seen:** Deadnight #391, 2026-11-01 (fix: rooms replaced the address screen).

## A thing shown in many places {#many-places}

<!-- new section: the HUD section covers what the HUD holds; nothing covered one identity drawn the same way in every
place -->

- **Approach:** When several pieces always travel together, fix their order and gaps once, as one shared layout, and
  show the order in words before building each screen. **Watch out for:** the level and icon were asked for beside the
  names; the issue set icon, name, level without showing it, and each screen placed the level its own way (over a head,
  at the far edge of a lobby row), where icon, level, a gap, then the name was wanted. **Seen:** Deadnight #1115,
  2026-11-04 (fix: one order for the game and the lobby).
- **Approach:** Before an identity feature (a level, a tag, a card), list every place the name is drawn by searching the
  code, put the list in the issue, and count the player's own HUD first. **Watch out for:** the places a player's name
  shows were never listed, so the most-looked-at one, the player's own box at the bottom left, got no level or calling
  card (Deadnight #1077 listed tags, scoreboard, report and lobby). **Seen:** Deadnight #1077, 2026-11-04 (fix: the list
  goes in the issue).
