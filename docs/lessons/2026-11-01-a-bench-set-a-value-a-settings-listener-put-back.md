# A bench set a value directly and a settings listener put it back

2026-11-01

- **Saw:** a browser run set the touch aim assist's strength and auto-fire on the object, and every run behaved the
  same: the first touch reset them to the saved settings.
- **Cause:** the object re-reads its settings on every `changed` signal, and the first-run touch hints write a setting
  at the first touch, so anything set on the object by hand was lost.
- **Fix:** set the setting through the `Settings` service, as the player does (in a test-owned settings file); the
  object follows it. A bench or test of anything that listens to `Settings.changed` sets the setting, not the field.
- **Docs:** Deadnight `docs/research/aim-assist.md`.
