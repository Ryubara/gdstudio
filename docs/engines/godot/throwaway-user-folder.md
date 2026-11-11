# A throwaway user folder for the real game

A capture that has to run the game's own `main.tscn` against a real sign-in must not read or write the person's saves
(`user://profile.json`, `user://guest_account.json`, the settings). Godot has no command-line switch for another user
folder, but on Windows it takes the folder from the `APPDATA` environment variable.

- **Start the run with `APPDATA` pointing at a folder of its own**: `APPDATA='<scratch>\appdata' gds godot -- --path
  <game> res://tests/captures/x.tscn ...` (`gds godot` passes the environment through). `OS.get_user_data_dir()` then
  prints `<scratch>/appdata/Godot/app_userdata/<project>`; print it first in the capture, so the log shows where it ran.
  Every default path of the game is then a throwaway user's, with nothing seeded by hand but what the capture makes.
- **Seed it the way a player would**: sign in once through the game's own API against the real backend (`BackendFixture`
  in the game's tests runs it from `spikes/backend` with memory storage), so the guest credential and the profile file
  come from a real sign-in; then change only what the story needs (another machine's progress goes through the backend's
  report endpoint, the older cache is written with the store). Delete the folder afterwards.
- **`gds godot` is a harness run**: it sets `GDS_QUIET`, and a game that keeps its credential and settings out of such
  runs (Deadnight's `SettingsService.is_harness_run`) reads no kept credential, so the game's own start-up sign-in
  does nothing. The capture calls the same function with the same arguments the game gives it (a path to the throwaway
  credential, the backend's address) after loading the real scene; say so in the pull request.
- **Not a test of the game's own start-up order** to the frame: what is loaded is the real scene and the real code, the
  one call that a harness run leaves out is made by the capture.

## Tests never write the real folder {#tests}

<!-- new section: the page covers captures of the real game; nothing covered test suites that write the person's folder
-->

- **Approach:** Point a settings or save autoload away from `user://` from a game's first test, fail a test when a suite
  run changes the real file, and never edit `app_userdata` by hand: report it. **Watch out for:** suites saved
  `camera_shake=0` through the `Settings` autoload into the player's real `user://settings.cfg`; the game lost its
  camera shake and two agents fixed it by editing the real file. **Seen:** Deadnight #418 and #446, 2026-11-01 (fix:
  tests and captures use their own settings store, and a test fails if a suite run changes the real file).
- **Approach:** A suite that has to write a file names it by process id and deletes it before and after each test
  (`TempUserFile.path` in the 3D Third Person template), as [Running more than one](running-gdunit.md#parallel) says.
  **Watch out for:** a fixed name such as `user://settings_test.cfg` is shared by every run of the game at the same
  time, the throwaway games of `gds template test` included. **Seen:** gdstudio #1043, 2026-11-10.
