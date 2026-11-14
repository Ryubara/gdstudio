class_name AiCallCounts
extends RefCounted
## The calls every `CountingAi` has made so far, shared by all of them (gdstudio #970).
##
## They live here, not in `CountingAi`: a script that extends a game class and keeps a static
## variable of its own left GdUnit4's scripts and the autoloads' in use at exit (779 objects)
## when a suite named the base class first (gdstudio #1499; the kit's
## `docs/engines/godot/test-exit-leaks.md#a-subclass-with-statics`).

static var physics := 0
static var process := 0
static var thinks := 0
