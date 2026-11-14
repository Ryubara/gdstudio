class_name ProbeSettle
extends RefCounted
## Draws the reflection probes of a new view to the end before a capture films it.
##
## Godot draws a `ReflectionProbe` that updates once a step a frame (six faces, then its blur
## steps) from one queue that every world in the process shares, and the probe is read from its
## first step on, while its cube is still black: a body inside it goes dark above the hips until
## the faces are drawn. With several worlds in one process (`OnlineRig`), the later worlds' probes
## wait behind the earlier ones, and the dark frames landed two seconds into a capture. Each
## `RenderingServer.force_draw` is one more step of that queue, drawn within the frame, so a
## capture records no frame of it (engines/godot/first-use-hitches.md#reflection-probes).

## A draw or two more than the steps: the first draw of a new view is the one that queues them.
const SPARE_DRAWS := 2


## True when this process draws nothing (a headless run): there is nothing to wait for.
static func draws_nothing() -> bool:
	return DisplayServer.get_name() == "headless"


## The probes under `views` that update once and draw a step a frame. The level's
## `EffectEmitter` visits every probe of its world when it starts, so each is queued, seen or not.
static func probes_to_draw(views: Array[Viewport]) -> int:
	var count := 0
	for view in views:
		for node in view.find_children("*", "ReflectionProbe", true, false):
			var probe := node as ReflectionProbe
			if probe.update_mode == ReflectionProbe.UPDATE_ONCE and probe.is_visible_in_tree():
				count += 1
	return count


## Draws every view on, within this frame, for as many steps as `probes` probes that update once
## take (`EffectEmitter.PROBE_FRAMES` each).
static func draw_through(probes: int) -> void:
	if draws_nothing() or probes == 0:
		return
	for _i in probes * EffectEmitter.PROBE_FRAMES + SPARE_DRAWS:
		RenderingServer.force_draw(false)
