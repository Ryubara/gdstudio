# Menus over a game: the screen host and the settings

<!-- new section: UI controls covers the controls and the online case; nothing held how a solo game pauses behind its
menus or keeps options (gdstudio #881) -->

How a template game shows menus over its running world and keeps the player's options (gdstudio #881): the parts the
3D Third Person template ships with and their inspector list, the `ScreenHost` that pauses the game and gives it back,
and the `Settings` autoload with rebinding. The controls the screens are made of, focus, and the online case (a menu
over a game that must keep running) are on [UI controls](ui-controls.md); the router's calls are in the addon's README
(`godot/addons/gds_ui/README.md`).

## The template's menus and settings {#menus}

The project starts at `ui/menus/menu_scene.tscn`, which shows the main menu on the router (`gds_ui`). Play shows the
loading screen, which reads `main.tscn` on a thread and switches to it; in the game a `ScreenHost` node opens the pause
menu from Esc, a pad's Start or the touch layer's Menu button, pauses the tree and gives it back. Every screen is a
scene of `gds_ui` controls, laid out in the editor; the scripts only wire them. How the pieces work together, and how
to open a screen of your own from gameplay, is in the next section; the settings and rebinding are in the
one after it.

| Part | Where (`templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| Menu scene | `ui/menus/menu_scene.tscn`, `.gd` | The scene the project runs. `skip_menu` (or `--play` after the engine's `--`, or `?play` in a browser) goes straight to the game, for working on the level. |
| Main menu | `ui/menus/main_menu.tscn` | Play, Settings and Quit (Quit is left out in a browser). `game_scene` is the scene Play loads; `title` is the project's name when empty. |
| Loading screen | `ui/menus/loading_screen.tscn` | Takes the scene's path as the `scene` param, shows progress, switches scenes, and on a scene that cannot be read says so and offers the menu. |
| Pause menu | `ui/menus/pause_menu.tscn` | Resume, Settings, Main menu; Esc and B close it; drawn a little transparent over the game. |
| Settings | `ui/menus/settings_menu.tscn` | Tabs Video, Audio and Controls of `SettingRow` nodes and the generated rebinding rows; saves itself, Reset restores the defaults. |
| Screen host | `ui/menus/screen_host.gd`, a `Screens` node in `main.tscn` | Opens screens over the game ([Menus over a game](#screen-host)). |
| Pause button | `ui/menus/pause_button.tscn`, in `MenuLayer` of `main.tscn` | Shows with the touch layer; the way in on a phone, which has no Esc. |
| Settings service | `core/settings/` (autoload `Settings`) | Options, saved and applied; `quality_preset.gd` is one step of the quality choice, `input_bindings.gd` the rebinding. |
| Look bridge | `gameplay/player/look_settings.gd`, a `LookSettings` node | Carries mouse sensitivity and invert to the camera rig. |
| Layout | `ui/menus/menu_fit.gd` | On a phone (short side under 500 px, or a touch screen under 1000) it lays the menu out on a canvas half as big, drawn twice the size, so a button is a finger's size. |

**In the inspector.** `ScreenHost`: `pause_screen`, `action_screens` (action to scene), `transition`, `pause_tree`,
`release_mouse`, `pause_on_focus_loss`, `pause_on_lost_mouse`, `menu_scene`. `Settings` (its scene): `save_delay` and
`presets`, three `QualityPreset` resources (`title`, `msaa`, `shadow_atlas_size`, `shadow_filter`) that Low, Medium and
High apply. `MenuFit`: `phone_short_side`, `touch_short_side`, `phone_factor`, `force`. `SettingRow`: `key`, `format`,
`option_values`, `options_from_presets`, `hide_on_web`. `ControlsPage`: `actions`, the list a player may rebind.
`PauseButton`: `host`, `touch`, `always_shown`. `LookSettings`: `camera`. `MenuScene`: `main_menu`, `game_scene`,
`skip_menu`. `LoadingScreen`: `least_time`.

- **Approach:** Make a menu's parts nodes of its scene and write the scene's `.tscn` with each node's `script =` line
  before the script's own exports. **Watch out for:** a `.tscn` written by a script that put `style = 1` and
  `title = "..."` above `script = ExtResource(...)` loaded with every one of those values dropped, silently: the
  titles were body-sized and the rows had no words, found only by a capture. **Seen:** gdstudio #881, 2026-11-10.
- **Approach:** Capture a phone-shaped menu from the window's own pixels (`get_viewport().get_texture().get_image()`
  after `RenderingServer.frame_post_draw`), and a desktop one with Movie Maker. **Watch out for:** Movie Maker writes
  the project's 1920 x 1080 and crops a canvas that is wider (an 844 x 390 window is 2337 x 1080 units), so the first
  phone captures showed the middle of every card. **Seen:** gdstudio #881, 2026-11-10
  (`tools/capture/menus_tour.gd`, `--shots=<folder>`).
- **Approach:** Give every sub-resource that a test or a designer edits `resource_local_to_scene = true` when the scene
  is made more than once (the `Settings` scene's three presets). **Watch out for:** instances of one scene share its
  sub-resources, so a test that set a preset's `msaa` changed the autoload's too. **Seen:** gdstudio #881, 2026-11-10.
- **Approach:** When the project's main scene stops being the game's, give tools a way past the menu (`--play`,
  `?play`, `skip_menu`) and point every test and capture that wants the game at `res://main.tscn`. **Watch out for:**
  `gds capture frames` without `--scene`, a Playwright probe and a tour that start the main scene now start at the
  menu; the template's `touch_smoke.py` opens `?probe&play`. **Seen:** gdstudio #881, 2026-11-10.

## The HUD {#hud}

<!-- new section: the HUD went from two loose nodes in a layer to regions, widgets and one theme (gdstudio #880) -->

How to use and extend it is in [The template HUD](ui-layout.md#template-hud). In the inspector: on `Hud`, the group Look
(`theme`, `margin`), Phone (`min_text_size`, `max_scale`, `pixel_ratio`, `touch_controls`) and Parts (`root`, `safe_area`,
`minimap_slot`); on every part the group Data (`player`, `hide_without_data`) and Phone (`touch_region`); on a `HudStat`
the Data (`source`, `value_property`, `max_property`, `refresh_signals`), Look (`title`, `show_title`, `show_bar`, the two
formats, `low_share`, `low_color`) and Parts groups; on `ItemCounter` the `separator`. The real player has no health or
ammo yet: those parts stay hidden until the hit zones (#876) and the weapons (#887) make `health`/`max_health` and
`ammo`/`magazine_size` exist, and `tools/capture/hud_tour.tscn` shows them fed by a stand-in.

Cost, measured in Compatibility on Windows (an RTX 5080, vsync off, 150 frames after 150 of warm-up): the game with the
HUD hidden draws 109 calls at 0.48 ms CPU and 0.27 ms GPU, and with the coin counter, health, ammo and the crosshair all
showing it draws 118 calls at 0.54 ms and 0.29 ms (about 9 calls, 0.05 ms CPU, 0.015 ms GPU). The HUD is local: nothing
in it is sent over a network.

## A menu over a game that pauses: the screen host {#screen-host}

<!-- new section: A menu over a live game covers the online case; nothing said how a solo game opens a pause menu, an
inventory or a map over its running world and gives the game back (gdstudio #881) -->

`ScreenHost` (`ui/menus/screen_host.gd` in the 3D Third Person template, one node in the game scene) is the way a game
shows a screen over itself. The screens stay on the `UIRouter` stack, which runs while the tree is paused; the host
adds what the router does not know about a game:

- **Open and close.** `open(screen)` takes a `PackedScene`, a path or a `Control`, pauses the tree, lets the mouse go
  and shows the screen; `close()` clears the stack. When the stack is empty again (a Resume button, Esc, a screen that
  frees itself) the host unpauses, gives the mouse back if the game held it, and puts touch-to-mouse back.
- **Bind a key.** `action_screens` maps an input action to a scene (`inventory` to `inventory.tscn`): the key opens the
  screen and the same key closes it. The `pause` action (Esc, a pad's Start) opens `pause_screen`. Esc and a pad's B
  step back through the router one screen at a time; Start closes everything.
- **Give the screen `back_closes`** so Esc closes it when it is the only one: `UIRouter.pop()` stops at the root, so
  without it a pause menu has no Esc. A screen extends `UIScreen`; `UIRouter.close()` is a pop that may empty the stack
  and `UIRouter.clear()` frees all of it.
- **Keep the game as a node tree, not a screen.** The router disables the screen it covers, so a game that is the
  bottom screen stops whether it wants to or not; as plain nodes under a paused tree it stops by the tree's own
  setting, and a game that must run on (online) turns `pause_tree` off.
- **Web.** The host also opens the pause menu when the game had the mouse captured and no longer has it (a browser's
  first Esc only lets the pointer lock go) or when the window loses focus
  ([Web export](web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night)), and takes the lock
  again from Resume's click.

```gdscript
# From code, anywhere in the game:
ScreenHost.current.open(preload("res://ui/menus/inventory.tscn"))
```

- **Approach:** Open a menu over a solo game from one host node that pauses the tree, frees the mouse, turns
  `Input.emulate_mouse_from_touch` on and gives all three back when the router's stack is empty again; give the router
  a `close` that may empty the stack, and have the touch layer `suspend()` on `opened` and `resume()` on `closed`.
  **Watch out for:** the touch layer turns touch-to-mouse off, so on a phone the buttons heard nothing; `pop()` stops at
  the root, so Esc left the pause menu up; the router disables the screen it covers, a pause for a game that is a
  screen and a bug for one that is not; a paused layer never sees a finger lift, and its buttons (the router's own
  layer) drew over the menu. **Seen:** gdstudio #881, 2026-11-10 (`test_screen_host*.gd`, 19 tests through the real
  input path; `pause_smoke.py` and `menu_smoke.py`: 20 and 12 checks in Chromium).
- **Approach:** Give the host seams for what a headless run cannot do (`mouse_mode_reader`, `mouse_mode_writer`,
  `scene_changer`) and free it in the test's `after_test`, whose `_exit_tree` clears the router. **Watch out for:** a
  headless run reads the mouse mode back as visible whatever was set, and a test that changed the scene would replace
  the one the runner stands in; a host freed with a screen up left the tree paused and a menu on the router for every
  suite after it. **Seen:** gdstudio #881, 2026-11-10.

## Settings and rebinding {#settings-and-rebinding}

<!-- new section: Deadnight's settings are in its own docs; nothing said how a template keeps options, applies them and
lets a player rebind keys (gdstudio #881) -->

The template's `Settings` autoload (`core/settings/settings_service.gd`, from the scene `settings_service.tscn`) holds the
options by `section/name` key, each with a default and a range: it loads `user://settings.cfg` at start, applies every
value at once when it changes (volume through `AudioSettings.set_player_gain`, resolution scale on the root viewport,
window mode, vsync, a quality preset) and writes the file half a second after the last change. Mouse sensitivity and
invert Y are read by `LookSettings`, a node that carries them to the camera rig. A row of the settings screen is a
`SettingRow` (a `UISlider`, `UIToggle` or `UIOptionSelector` under it and a `key`): a new setting is a key in the
service, a row in the scene and, if it does something, a line in `_apply`.

- **Approach:** Keep the player's choices apart from the designer's: the player's volume is a gain on top of the mix
  `AudioSettings` holds (`set_player_gain`, static, so a menu before the game and the game share it), and the player's
  mouse sensitivity and invert are `player_sensitivity` and `player_invert_y` on the camera rig, not edits of its
  `mouse_sensitivity` and `invert_y`. **Watch out for:** writing the slider's value into the bus or the export loses the
  designer's tuning on the next change of either, and a saved choice then cannot tell what the game meant. **Seen:**
  gdstudio #881, 2026-11-10.
- **Approach:** Save a binding as data (`{"type": "key", "code": 70, "physical": true}`), check every field when it is
  read, and keep a test run's, a capture's and an agent's options in memory. **Watch out for:** a `ConfigFile` can hold
  an `Object`, and a file the player edits must not make the game build one; a hand-edited file with a wrong type, an
  out-of-range number or a `NaN` must fall back value by value, not fail the load; the engine's own error is printed
  for a file that is not a config file at all. **Seen:** gdstudio #881, 2026-11-10 (`tests/core/
  test_settings_service.gd`, `test_settings_bindings.gd`, `test_input_bindings.gd`).
- **Approach:** Rebind the first binding of the device the player pressed and leave the others (W stays beside the up
  arrow), swap with the action that used the control, take the next real press (key, mouse button, pad button or a
  stick or trigger past 0.6) and let Escape cancel while the screen's own back is switched off. **Watch out for:** a
  pad's press arrives with the pad's id and must be stored for every device (`device = -1`), a held key repeats as echo
  presses, a button's own accept press must not be the binding, and `DisplayServer.keyboard_get_keycode_from_physical`
  prints an error on the headless display server, so use `InputEventKey.as_text_physical_keycode()` for the label.
  **Seen:** gdstudio #881, 2026-11-10 (`tests/ui/test_settings_rebinding.gd`).
- **Approach:** Set an option selector to the saved value with `jump_to(index)` when a screen is built and with
  `select(index, false)` when a value changes elsewhere. **Watch out for:** the second argument of
  `UIOptionSelector.select` is whether to emit, not whether to animate, so every settings screen showed its selectors
  sliding from the first choice to the saved one as it appeared. **Seen:** gdstudio #881, 2026-11-10 (a capture caught
  `Lo` and `High` on one frame).
- **Approach:** Recognise a run that must not touch the person's file by what it was given (a GdUnit argument, a scene
  named on the command line, `GDS_QUIET`), never by naming the folders of tests and tools in shipped code. **Watch out
  for:** the layout check's `ships-tools` rule fails a shipped script that spells `res://tests/` or `res://tools/`,
  and the first version of `is_harness_run` did. **Seen:** gdstudio #881, 2026-11-10.
