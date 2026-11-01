# No-focus spike

Which way of starting a windowed Godot leaves the foreground window and the keyboard alone? `probe.py <show> <godot
command line>` holds the foreground with a test window of its own, starts Godot with the given `STARTUPINFO` show state
(`none`, `4`, `7`) or on a private desktop (`desktop`), and prints whether Godot's window took the foreground. The
scene is a solid colour that changes every frame. The findings, and the finished launcher, are in
`docs/godot/no-focus.md`.
