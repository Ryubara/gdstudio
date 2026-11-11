# Menus and settings

The game starts at a main menu, pauses to a pause menu and keeps the player's options. Every screen is a scene of
`gds_ui` controls under `game/ui/menus/`, laid out in the editor and skinned by the project's `UITokens` resource (see
the addon's README for restyling); the scripts only wire them. How each part works is in the kit's
`docs/engines/godot/menus.md` (the parts, the screen host, settings and rebinding).

## What the player sees

| Screen | How it is reached | What is on it |
| --- | --- | --- |
| Main menu | The project starts here | Play, Settings, Quit (not in a browser) |
| Loading | Play | A bar while `main.tscn` is read on a thread |
| Pause menu | Esc, a pad's Start, the Menu button on a touch screen, or losing the mouse's pointer lock in a browser | Resume, Settings, Main menu; the game is paused behind it |
| Inventory | I, a pad's right shoulder, the Bag button on a touch screen | The player's model, weapons and bag: [Inventory](inventory.md) |
| Settings | From either menu | Video (window mode, quality, resolution scale, vsync), Audio (a slider per bus), Controls (mouse sensitivity, invert, pause in the inventory, a button per action for the keyboard and for a pad) |

Mouse, keyboard, gamepad and touch all work on every screen: the arrows and the d-pad move the focus, accept and
cancel are Enter and A, Esc and B, and the touch layer's buttons stand down while a menu is up.

## Things you will do

- **Start in the level while you work on it:** tick `skip_menu` on the `MenuScene` node of `ui/menus/menu_scene.tscn`,
  or run the game with `-- --play` after the engine's arguments. Untick it before you ship.
- **Add a setting:** add a key to `core/settings/settings_service.gd` (a default, a range, and a line in `_apply` if it
  does something), then copy a `SettingRow` in `ui/menus/settings_menu.tscn`, give it the key and put a slider, a switch
  or a selector under it. The service saves it and applies it at start.
- **Let the player rebind another action:** add its name to `actions` on the `ControlsPage` node.
- **Open your own screen from gameplay:** make a scene that extends `UIScreen` (set `back_closes` so Esc closes it),
  then either call `ScreenHost.current.open(preload("res://ui/menus/your_screen.tscn"))` or add its input action and
  scene to `action_screens` on the `Screens` node of `main.tscn` (`ui/menus/screen_host.tscn`). The game pauses, the
  mouse is freed, and everything is put back when the last screen closes.
- **Change what Low, Medium and High do:** edit the three `QualityPreset` resources in the `Settings` scene
  (`core/settings/settings_service.tscn`).
- **Tune the mix without touching the player's choice:** the `AudioSettings` node's volumes are yours; the player's
  sliders are a gain on top of them.

## Where the files are

`ui/menus/` the screens and their scripts, `core/settings/` the service, `gameplay/player/look_settings.gd` the bridge
to the camera, `tools/capture/menus_tour.tscn` a tour for captures (`-- --game` for the part over the game, and
`--shots=<folder>` for a phone-sized window), `tools/web_smoke/pause_smoke.py` the browser test of the pause menu,
pointer lock, Esc and the saved file.
