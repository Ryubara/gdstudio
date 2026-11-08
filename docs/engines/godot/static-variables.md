# Static variables and the order scripts load in

Found in Deadnight #1323; measured on a Web export of the pinned Godot 4.7.2.

## What the engine does {#what-the-engine-does}

A `static var`'s initialiser runs **when its script is loaded**, not when the first caller reaches it. Scripts that
refer to each other (a type in a signature, a typed member, a call) load one inside the other, so which initialiser runs
first depends on which script something else named first, and a class a scene loads (a bench's `var _night: Night`)
changes that order from the game's own.

When script A's initialiser calls a static function of script B while B is still loading, **B's static variables hold
the type's default**, not their initialiser: an `int` is `0`, a `float` `0.0`, a `bool` `false`, a reference `null`.
B's initialisers run after. Nothing is printed.

## The case {#the-case}

Deadnight `NightScreen.arrival_enabled := ... and not WebProbe.asked()` and `WebProbe` (which names `NightScreen` in
its snapshot) refer to each other. `WebProbe` kept its answer in `static var _asked := -1` ("-1 not read, 0 no, 1 yes"):
`asked()` ran from the night screen's initialiser, saw the default `0` (no), and returned false, so the helicopter drop
played on a page that had asked for the probes. `asked()` was true everywhere after, which hid it. The main menu path
loaded `WebProbe` first and was right; a bench that typed its members (`var _night: Night`) loaded the night first and
was wrong.

## The rule {#the-rule}

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

## A flag that nodes read once {#static-flag-changes}

<!-- new section: the rest of the page is about a static var's first value; nothing covered a static flag that changes
while nodes already hold it -->

- **Approach:** Give a static flag that can change while the game runs a setter that emits through a small `RefCounted`
  bus (`UIMotion.changed()`), have every node connect in `_ready` and apply the value at once, and test by flipping the
  flag while the main scene runs. **Watch out for:** a `static var` cannot declare a signal, and nodes that read
  `UIMotion.reduced` once in `_ready` kept their old value, so a film-grain overlay that lives for the whole session
  went on flickering after Reduced motion was switched on. **Seen:** Deadnight, 2026-11-01 (fix: the setter and bus; a
  test flips the flag with the main scene running).
