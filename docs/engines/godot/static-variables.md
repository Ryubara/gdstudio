# Static variables and the order scripts load in

Found in Deadnight #1323; measured on a Web export of the pinned Godot 4.7.2.

## What the engine does

A `static var`'s initialiser runs **when its script is loaded**, not when the first caller reaches it. Scripts that
refer to each other (a type in a signature, a typed member, a call) load one inside the other, so which initialiser runs
first depends on which script something else named first, and a class a scene loads (a bench's `var _night: Night`)
changes that order from the game's own.

When script A's initialiser calls a static function of script B while B is still loading, **B's static variables hold
the type's default**, not their initialiser: an `int` is `0`, a `float` `0.0`, a `bool` `false`, a reference `null`.
B's initialisers run after. Nothing is printed.

## The case

Deadnight `NightScreen.arrival_enabled := ... and not WebProbe.asked()` and `WebProbe` (which names `NightScreen` in
its snapshot) refer to each other. `WebProbe` kept its answer in `static var _asked := -1` ("-1 not read, 0 no, 1 yes"):
`asked()` ran from the night screen's initialiser, saw the default `0` (no), and returned false, so the helicopter drop
played on a page that had asked for the probes. `asked()` was true everywhere after, which hid it. The main menu path
loaded `WebProbe` first and was right; a bench that typed its members (`var _night: Night`) loaded the night first and
was wrong.

## The rule

- A cache or flag that a function reads with "not read yet" as a value says it with **the type's default**: `static
  var _x: int` (0 = unread, 1 = no, 2 = yes), with no initialiser. `:= -1` is read as `0` by an initialiser that runs
  early, and `0` is usually an answer.
- Do not call another script's static function from a static initialiser unless that function is safe on a script whose
  statics are all defaults.
- A test scans the game's scripts for a `static var` that starts on a number other than zero
  (`tests/core/test_static_caches_start_at_the_default.gd` in Deadnight); a sentinel that is only read once the game is
  up is listed there with why.
- Find the cause on the web with a log of the variable at the head of the function (`JavaScriptBridge.eval` to push
  `typeof(_x):_x` into a page array): the first call read `2:0` (an int, zero) where the initialiser said `-1`.

See [the lesson](../lessons/2026-11-06-a-static-cache-read-from-an-initialiser-held-its-default-and-the-page-played-the-drop.md).
