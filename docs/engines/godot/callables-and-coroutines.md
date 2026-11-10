# Callables and coroutines

Found in Deadnight #1106 (a night's XP sent to the backend through a `Callable` that awaits an HTTP request), measured
in a throwaway project on Godot 4.7.2. Three behaviours that each cost a silent failure, then two more GDScript
behaviours of the same kind (packed arrays, the order of a signal's handlers).

## A Callable does not keep a RefCounted object alive {#a-callable-does-not-keep-a-refcounted-object-alive}

`obj.method` made from a `RefCounted` object holds the object's id, not a reference. When the last real reference goes,
the object is freed and the Callable is invalid (`is_valid()` is `false`); calling it does nothing and prints nothing.

```gdscript
var c := Uploader.new().send     # the temporary is freed at the end of this line
print(c.is_valid())              # false
```

The usual shape of the bug is a hand-over: `session.uploader = ProfileUplink.new(api, store).send`, or a local `var
uplink := ...` in `_ready` whose `send` is stored. A guard such as `if uploader.is_valid()` then skips the work with no
error, and a test that checks only "no error" passes. **Keep the object in a field of something that lives as long as
the Callable is used** (Deadnight: `Night.profile_uplink`), and test the hand-over with the real wiring, asserting that
the call happened.

## A coroutine of a RefCounted object does not keep it alive either {#refcounted-coroutine}

A method that awaits a timer or a request, called on an object nothing else references, is dropped: the code after the
`await` never runs (no error). The fix is a local in the coroutine that holds the object, which lives in the saved
stack until the method returns:

```gdscript
func send(write: Dictionary) -> bool:
    @warning_ignore("unused_variable")
    var held := self
    var latest := await api.read_save(SLOT)
    ...
```

Measured: with the local the continuation ran 0.2 s later; without it, it never did.

## `await` on a value that is not a signal or a suspended coroutine does not wait {#await-non-signal}

`await f()` where `f` returns a plain value, or is a coroutine that never suspends, continues at once, in the same
frame. So a fake backend whose methods return a Dictionary makes the whole send finish before the call returns, and a
suite needs no `await` to read the result. A real request does suspend, and the test waits for what the code sets
(a flag, the queue), never a fixed time.

Calling a coroutine as a statement (`store.flush(send)`) is fine. Using its **result** without `await` is a parse error
(`Function "flush()" is a coroutine, so it must be called with "await"`): a function that gains an `await` needs
`await` at every caller that reads its value, tests included.

## A timer belongs to the tree, not the node {#a-timer-belongs-to-the-tree}

<!-- new section: the page covers what keeps an object alive and what await returns; none covered whose timer a wait
     is -->

- **Approach:** Wait on a screen with a child `Timer` node (it stops with a disabled parent and is freed with it),
  take focus only while the screen is the router's top, and make the delay settable so tests need no wall time.
  **Watch out for:** `SceneTree.create_timer` belongs to the tree, not the node: it ignores the node's disabled
  `process_mode` and outlives it, so a main menu that waited 0.55 s before focusing `Play` stole the focus back from a
  screen pushed over it inside that window. **Seen:** Deadnight, 2026-11-01 (fix: a `Timer` child and a top-of-router
  check).

## Where an await resumes {#where-an-await-resumes}

<!-- new section: the page covers what await does with a value; none covered a signal that already fired or one that
     frees its listener -->

- **Approach:** Do not `await` a signal after the call that emits it: check the state (`is_arriving()`) or connect
  before the call; give every capture script a hard stop in frames of its own (a counter in `_process` that quits)
  besides `--quit-after`, bound every wait loop, run a new capture with a small `--quit-after` first, and delete the
  frames once the sheet or clip is made. **Watch out for:** `arrival_show.skip_now()` ended the show inside the call
  and emitted `arrival_ended` there, so the `await` after it began after the signal and waited for ever; Movie Maker
  recorded 3,000 frames of a night that never began, enough to fill the disk. **Seen:** Deadnight #1278, 2026-11-05
  (fix: a state check and a frame counter in the capture).

- **Approach:** Let a fixture yield one frame before it frees what a test awaited (`RouterFixture.clear` does), and
  test that the screen is still alive when `clear` first gives control back; when a headless run must be free of
  `ERROR`, grep the log for it. **Watch out for:** `await signal` resumes the caller synchronously inside the emit: a
  test that freed the screen right after `await night.ready_to_play` freed the night while `Night._go` was still
  emitting ("freed or unreferenced while a signal is being emitted"); the suite stayed green, so no check saw it, and
  the game itself frees nothing there. **Seen:** Deadnight, 2026-11-06 (fix: `clear` yields a frame;
  `test_router_fixture.gd`).

## Packed arrays are values {#packed-arrays}

<!-- new section: the page covers Callables and coroutines; another silent GDScript failure (a copy that is changed
instead of the original) had no home -->

- **Approach:** Append to the property itself (`data.names.append(x)`), or assign the copy back, when the array is a
  `Packed*Array`. **Watch out for:** packed arrays are value types, so `var list := data.names; list.append(x)` changes
  a copy and the property stays empty, with no error: a credits list stayed empty although every line was appended.
  **Seen:** Deadnight, 2026-11-01 (fix: append to the property; a test caught it).
- **Approach:** `duplicate()` a packed array another object keeps appending to before a coroutine reads it across
  frames (a replay of a server's history, a list of samples). **Watch out for:** the other way round from the entry
  above: passed to a function, `peer.history_steps` was the same array, so a replay loop that awaited a frame for each
  entry grew with the server that went on stepping, ran 1025 frames instead of 126 and let the server drop the client
  as silent. **Seen:** gdstudio #904, 2026-11-10 (fix: the test replays a copy taken when it read the body).

## Handlers of one signal run in the order they connected {#signal-order}

<!-- new section: nothing on the page covered two handlers of one signal that undo each other -->

- **Approach:** Give a late handler that undoes another's work a guard on the state the first one set, never rely on
  which handler runs first, and end the night under the drop on purpose in a test. **Watch out for:** the night
  screen's `night_over` handler hid the HUD and put the board up, then the night's own handler closed a drop still
  playing and its `arrival_ended` showed the HUD again over the board; the screen connects before the night, a headless
  run has no drop, and the rules never end a night under one, so only a windowed test that forced it failed. **Seen:**
  Deadnight, 2026-11-05 (fix: `_on_arrival_ended` does nothing when the board is up).
- **Approach:** To connect a handler that takes no arguments to a signal that carries some, read the argument count from
  `get_signal_list()` and use `callable.unbind(count)` only when it is above zero. **Watch out for:** `unbind(0)` is an
  error ("Amount of unbind() arguments must be 1 or greater") printed on every connect, and a connection test that
  looks only at the result passes. **Seen:** gdstudio #880, 2026-11-10 (the HUD's `refresh_on`).
