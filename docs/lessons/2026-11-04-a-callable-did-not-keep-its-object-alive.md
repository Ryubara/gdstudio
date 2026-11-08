---
areas: [godot, net]
---
# A queued write was never sent because its Callable's object was freed

2026-11-04

- **Saw:** Deadnight #1106: the night's uploader was set and the round's end did nothing, no error, no request; the
  test counting writes read 0 where the code looked right.
- **Cause:** the uploader was `ProfileUplink.new(api, store).send`, a Callable to a method of a temporary `RefCounted`
  object. A Callable holds the object's id, not a reference: the object was freed at the end of the line, the Callable
  became invalid, and the session's `if uploader.is_valid()` quietly skipped the upload.
- **Fix:** the night holds the uplink in a field (`Night.profile_uplink`) and takes `.send` from it; `send` and `flush`
  hold `self` in a local while a request is out, so a night that ends mid-request still finishes. A test drives the real
  hand-over and asserts the write happened.
- **Check for next time:** a Callable stored for later (`uploader`, `on_done`, a hook) to a method of a `RefCounted`
  object made inline needs a field that owns the object; look for `.new(...).method` and a local `var x := Foo.new()`
  whose method is stored.
- **Docs:** [Callables and coroutines](../engines/godot/callables-and-coroutines.md).
